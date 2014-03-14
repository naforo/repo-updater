require 'rubygems'
require 'rack'
require 'json'

require File.expand_path('../client_config.rb', __FILE__)
require File.expand_path('../pusher.rb', __FILE__)

class NaforoServer
  def bitbucket?
    @data["canon_url"] && @data["repository"] &&
      @data["repository"]["absolute_url"]
  end

  def github?
    @data["repository"] &&
      @data["repository"]["owner"].kind_of?(Hash) &&
      @data["repository"]["name"]
  end

  def error_response
    [422, {"Content-Type" => "text/html"}, "Unprocessable Entity"]
  end

  def process_request
    Pusher.named_update(@repo_url, @repo_name)
  end

  def call(env)
    req = Rack::Request.new(env)
    if REPOSITORY_URL == "auto"
      if req.post?
        if payload = req.POST["payload"]
          @data = JSON.load(payload)

          if bitbucket?
            abs_url = payload["repository"]["absolute_url"]
            path = abs_url[1, path.size-2]
            @repo_name = path.split('/')[1]
            @repo_url = "git@bitbucket.org:#{path}.git"
          elsif github?
            rdata = payload["repository"]
            @repo_name = rdata['name']
            @repo_url = "git@github.com:#{rdata['owner']['name']}/#{@repo_name}.git"
          else
            $stderr.puts "Invalid request:\n---\n#{req.body.read}\n---"
            nil
          end
        end
      end
    else
      @repo_name = "repository"
      @repo_url = REPOSITORY_URL
    end

    return error_response unless @repo_url

    if process_request
      [200, {"Content-Type" => "text/html"}, "OK"]
    else
      error_response
    end
  end
end
