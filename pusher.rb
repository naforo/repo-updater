require 'net/http'
require 'uri'
require 'json'
require 'zlib'
require 'stringio'

require File.expand_path('../client_config.rb', __FILE__)
require File.expand_path('../git_helper.rb', __FILE__)

class Pusher
  def initialize(data)
    @data = data

    raise "Please set ACCESS_TOKEN in config.rb." if ClientConfig['ACCESS_TOKEN'] == 'change-me'
  end

  def push
    request_data = @data.merge(
      "client_version" => "1.0alpha",
      "access_token" => ClientConfig['ACCESS_TOKEN']
      )
    # TODO: test for HUGE payload size
    gzip_data(request_data) do |data|
      url = URI.parse(ClientConfig['NAFORO_URL'])
      post_request = Net::HTTP::Post.new(url.path,
        "Content-Encoding" => "gzip",
        "Content-Type" => "application/json",
        "Content-Length" => "#{data.size}")
      post_request.body = data
      http = Net::HTTP.new(url.host, url.port)
      http.read_timeout = 600
      http.start { http.request(post_request) }
    end
    # TODO: More error handling
    true
  end

  def self.named_update(repo_url, repo_name = nil)
    repo_name ||= "repository"
    repo_path = File.expand_path("../#{repo_name}", __FILE__)
    cache_path = "#{repo_path}.json"

    update(repo_url, repo_path, cache_path)
  end

  def self.update(repo_url, repo_path, cache_path, data = {})
    # Read last fetched branches
    cache = if File.exist?(cache_path)
      JSON.load(File.read(cache_path))
    else
      {}
    end

    # Refresh repository
    git_helper = GitHelper.new(repo_path, repo_url, cache)
    git_helper_proc = data.delete(:git_helper_proc)
    git_helper_proc.call(git_helper) if git_helper_proc
    git_helper.refresh(!ClientConfig['MANUAL_REFRESH'])

    # Get data
    data = data.merge(
      'commits' => git_helper.new_commits,
      'branch_diffs' => git_helper.branch_diffs
    )

    # Push data to Naforo
    if Pusher.new(data).push
      # Remember last updated commits
      File.open(cache_path, 'w') { |f| f.write(JSON.dump(git_helper.last_commits)) }
    end
  end

private
  def gzip_data(request_data)
    io = StringIO.new('', IO::RDWR)
    gz = Zlib::GzipWriter.new(io)
    gz.write(JSON.dump(request_data))
    gz.close
    yield(io.string)
  ensure
    gz.close rescue nil
    io.close rescue nil
  end
end
