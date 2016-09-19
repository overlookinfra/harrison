module Harrison
  class Package < Base
    def initialize(opts={})
      # Config helpers for Harrisonfile.
      self.class.option_helper(:host)
      self.class.option_helper(:commit)
      self.class.option_helper(:purge)
      self.class.option_helper(:destination)
      self.class.option_helper(:remote_dir)
      self.class.option_helper(:exclude)

      # Command line opts for this action. Will be merged with common opts.
      arg_opts = [
        [ :commit, "Specific commit to be packaged. Accepts anything that `git rev-parse` understands.", :type => :string, :default => "HEAD" ],
        [ :purge, "Remove all previously packaged commits and working copies from the build host when finished.", :type => :boolean, :default => false ],
        [ :destination, "Local or remote folder to save package to. Remote syntax is: (user@)host:/path", :type => :string, :default => "pkg" ],
        [ :remote_dir, "Remote working folder.", :type => :string, :default => "~/.harrison" ],
      ]

      super(arg_opts, opts)
    end

    def remote_exec(cmd)
      ensure_remote_dir("#{remote_project_dir}/package")

      if @_remote_context
        super("cd #{@_remote_context} && #{cmd}")
      else
        super("cd #{remote_project_dir}/package && #{cmd}")
      end
    end

    def run(&block)
      return super if block_given?

      # Find the URL of the remote in case it differs from git_src.
      remote_url = find_remote(self.commit)

      # Resolve commit ref to an actual short SHA.
      resolve_commit!

      puts "Packaging #{commit} from #{remote_url} for \"#{project}\" on #{host}..."

      # Make sure the folder to save the artifact to locally exists.
      ensure_destination(destination)

      # To avoid collisions, we use a version of the full URL as remote name.
      remote_cache_name = remote_url.gsub(/[^a-z0-9_]/i, '_')

      # Fetch/clone git repo on remote host.
      remote_exec <<~ENDCMD
        if [ -d cached ]
        then
          cd cached
          if [ -d .git/refs/remotes/#{remote_cache_name} ]
          then
            git fetch #{remote_cache_name} -p
          else
            git remote add -f #{remote_cache_name} #{remote_url}
          fi
        else
          git clone -o #{remote_cache_name} #{remote_url} cached
        fi
      ENDCMD

      build_dir = remote_cache_name + '-' + artifact_name(commit)

      # Clean up any stale build folder of the target remote/commit.
      remote_exec("rm -rf #{build_dir} && mkdir -p #{build_dir}")

      # Check out target commit into the build_dir.
      remote_exec("cd cached && GIT_WORK_TREE=../#{build_dir} git checkout --detach -f #{commit} && git checkout -f -") # TODO: When git is upgraded: --ignore-other-worktrees

      # Run user supplied build code in the context of the checked out code.
      begin
        @_remote_context = "#{remote_project_dir}/package/#{build_dir}"
        super
      ensure
        @_remote_context = nil
      end

      # Package build folder into tgz.
      remote_exec("rm -f #{artifact_name(commit)}.tar.gz && cd #{build_dir} && tar #{excludes_for_tar} -czf ../#{artifact_name(commit)}.tar.gz .")

      if match = remote_regex.match(destination)
        # Copy artifact to remote destination.
        dest_user, dest_host, dest_path = match.captures
        dest_user ||= self.user

        remote_exec("scp #{artifact_name(commit)}.tar.gz #{dest_user}@#{dest_host}:#{dest_path}")
      else
        # Download (Expand remote path since Net::SCP doesn't expand ~)
        download(remote_exec("readlink -m #{artifact_name(commit)}.tar.gz"), "#{destination}/#{artifact_name(commit)}.tar.gz")
      end

      if purge
        remote_exec("rm -rf #{build_dir}")
        remote_exec("rm #{artifact_name(commit)}.tar.gz")
      end

      puts "Sucessfully packaged #{commit} to #{destination}/#{artifact_name(commit)}.tar.gz"
    end

    protected

    def remote_project_dir
      "#{remote_dir}/#{project}"
    end

    def find_remote(ref)
      remote = nil
      remote_url = nil

      catch :failure do
        # If it's a branch, try to resolve what it's tracking.
        # This will exit non-zero (and throw :failure) if the ref is
        # not a branch.
        remote = exec("git rev-parse --symbolic-full-name #{ref}@{upstream} 2>/dev/null")&.match(/\Arefs\/remotes\/(.+)\/.+\Z/i)&.captures.first
      end

      # Fallback to 'origin' if not deploying a branch with a tracked
      # upstream.
      remote ||= 'origin'

      catch :failure do
        # Look for a URL for whatever remote we have. git-config exits
        # non-zero if the requested value doesn't exist.
        remote_url = exec("git config remote.#{remote}.url 2>/dev/null")
      end

      # If we found a remote_url, return that, otherwise fall back to
      # configured git_src.
      return remote_url || self.git_src
    end

    def resolve_commit!
      self.commit = exec("git rev-parse --short #{self.commit} 2>/dev/null")
    end

    def excludes_for_tar
      return '' if !exclude || exclude.empty?

      "--exclude \"#{exclude.join('" --exclude "')}\""
    end

    def artifact_name(commit)
      @_timestamp ||= Time.new.utc.strftime('%Y%m%d%H%M%S')
      "#{@_timestamp}-#{commit}"
    end

    def ensure_destination(destination)
      if match = remote_regex.match(destination)
        dest_user, dest_host, dest_path = match.captures
        dest_user ||= self.user

        ensure_remote_dir(dest_path, Harrison::SSH.new(host: dest_host, user: dest_user))
      else
        ensure_local_dir(destination)
      end
    end
  end
end
