require 'git'

# JRuby can have issues with backticks, use IO.popen
module Git
  class Lib
    def run_command(git_cmd, &block)
      if block_given?
        IO.popen(git_cmd, &block)
      else
        IO.popen(git_cmd) { |io| io.read }.chomp
      end
    end
  end
  # Bug with encodings
  class Diff
  private
    def cache_full
      unless @full_diff
        @full_diff = @base.lib.diff_full(@from, @to, {:path_limiter => @path})
        return unless @full_diff.respond_to?(:valid_encoding?)
        unless @full_diff.valid_encoding?
          unless @full_diff.force_encoding("iso-8859-1").valid_encoding?
            @full_diff.force_encoding("utf-8").
              encode("UTF-16le", :invalid => :replace, :undef => :replace).
              encode("utf-8")
          end
        end
      end
    end
  end
end

class GitHelper
  MAX_COMMITS_UPDATE = 50
  MAX_COMMITS_INIT = 10
  CloneError = Class.new(StandardError)
  FetchError = Class.new(StandardError)

  def initialize(path, repo_url, branch_cache)
    @path = path
    @repo_url = repo_url
    @branch_cache = branch_cache
    @commits = {}
    @branch_diffs = {}
  end

  def git_clone
    Timeout::timeout(30 * 60) do
      name = File.basename(@path)
      dir = File.expand_path('..', @path)
      exec_git_clone(@repo_url, name, dir)
    end
  ensure
    raise GitHelper::CloneError unless File.exist?("#{@path}/.git")
  end

  def git_fetch
    Timeout::timeout(15 * 60) do
      git_repo.fetch(git_repo.remotes.first) # TODO: find origin
    end
  rescue Git::GitExecuteError
    raise GitHelper::FetchError
  end

  def refresh(refresh_remote = true)
    max_commits_to_process = if File.exist?(@path)
      git_fetch
      MAX_COMMITS_UPDATE
    else
      git_clone
      MAX_COMMITS_INIT
    end

    branches.each do |branch|
      get_new_commits(branch, max_commits_to_process)
      get_branch_diff(branch)
    end
  end

  def new_commits
    @commits
  end

  def branch_diffs
    @branch_diffs
  end

  def last_commits
    result = {}
    branches.each do |branch|
      # sha = git rev-parse origin/BRANCH
      commit = git_repo.log(1).
        object("origin/#{branch}").first
      result[branch] = commit.sha if commit
    end
    result
  end

private
  def get_new_commits(branch, max)
    # TODO: max
    stop_at ||= find_merge_base(branch) unless branch == "master"

    (0..max).each do |idx|
      # git rev-list --pretty=raw --max-count=2 --skip=0 master
      commit = git_repo.log(1).
        object("origin/#{branch}").
        skip(idx).first
      break unless commit
      break if commit.sha == stop_at
      break if commit.sha == @branch_cache[branch]

      add_commit(branch, commit)
    end
  end

  def get_branch_diff(branch)
    base_branch = 'master'
    return if branch == base_branch

    last_branch_commit = git_repo.log(1).
      object("origin/#{branch}").first
    return if last_branch_commit.sha == @branch_cache[branch]

    merge_base_sha = find_merge_base(branch, base_branch)
    unless merge_base_sha
      merge_base_sha = git_repo.log(1).object("origin/#{base_branch}").first
      merge_base_sha = merge_base_sha.sha if merge_base_sha
    end

    return unless merge_base_sha

    git_diffs = git_repo.diff(merge_base_sha, "origin/#{branch}")
    return if git_diffs.size == 0 # branch already merged into master

    if first_commit_sha = find_commit_after_diverge(branch, base_branch)
      if first_commit = git_repo.gcommit(first_commit_sha)
        author_name = first_commit.author.name
        author_email = first_commit.author.email
        branched_at = first_commit.author.date
      end
    end

    stats = git_diffs.stats[:total]
    add_branch_diff(branch,
      :author_name => author_name,
      :author_email => author_email,
      :base_branch => base_branch,
      :base_branch_sha => merge_base_sha,
      :branch => branch,
      :branch_sha => last_branch_commit.sha,
      :branched_at => branched_at,
      :additions => stats[:insertions],
      :deletions => stats[:deletions],
      :diffs => git_diffs.map { |diff_file| diff_data(diff_file) }
      )
  end

  def get_branch_diffs()
    puts "TODO"
    # diff = .. git diff master branch1
    if diff =~ /diff --git a/
      diff = diff.sub(/.*?(diff --git a)/m, '\1')
    else
      diff = ''
    end
  end

  def add_commit(branch, commit)
    data = commit_data(commit)
    return unless data
    @commits[branch] ||= []
    @commits[branch].push(data)
  end

  def add_branch_diff(branch, data)
    @branch_diffs[branch] = data
  end

  def commit_data(commit)
    return unless commit.parent
    begin
      diff = commit.parent.diff(commit)
      stats = diff.stats[:total]
    rescue Git::GitExecuteError
      return
    end
    {
      :sha => commit.sha,
      :parents_sha => commit.parents.map{|c| c.sha},
      :message => commit.message,
      :authored_date => commit.author.date,
      :author_name => commit.author.name,
      :author_email => commit.author.email,
      :committed_date => commit.committer.date,
      :committer_name => commit.committer.name,
      :committer_email => commit.committer.email,
      :additions => stats[:insertions],
      :deletions => stats[:deletions],
      :diffs => diff.map { |diff_file| diff_data(diff_file) }
    }
  end

  def diff_data(diff_file)
    {
      :patch => diff_file.patch,
      :binary => diff_file.binary?
    }
  end

  def branches
    @branches ||= get_branches
  end

  def find_merge_base(branch, base_branch = 'master')
    cmd =  "git merge-base origin/#{branch} origin/#{base_branch} | "
    cmd += "head -1"
    presence(%x[cd "#{@path}" && bash -c "#{cmd}"].strip)
  end

  def find_commit_after_diverge(branch, base_branch = 'master')
    cmd =  "diff --unchanged-line-format='' "
    cmd += "<(git rev-list --first-parent origin/#{base_branch}) "
    cmd += "<(git rev-list --first-parent origin/#{branch}) | "
    cmd += "tail -1"
    presence(%x[cd "#{@path}" && bash -c "#{cmd}"].strip)
  end

  def git_repo
    Git.open(@path)
  end

  def exec_git_clone(url, name, path)
    Git.clone(url, name, :path => path)
  end

  def get_branches
    # git branch -r
    git_repo.branches.remote.map{|r| r.name}.reject { |name| name =~ /->/ }
  end

  def presence(value)
    value == "" ? nil : value
  end
end
