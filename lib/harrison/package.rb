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

      # Resolve commit ref to an actual short SHA.
      resolve_commit!

      puts "Packaging #{commit} for \"#{project}\" on #{host}..."

      # Make sure the folder to save the artifact to locally exists.
      ensure_destination(destination)

      # Fetch/clone git repo on remote host.
      remote_exec("if [ -d cached ] ; then cd cached && git fetch origin -p ; else git clone #{git_src} cached ; fi")

      # Make a build folder of the target commit.
      remote_exec("rm -rf #{artifact_name(commit)} && cp -a cached #{artifact_name(commit)}")

      # Check out target commit.
      remote_exec("cd #{artifact_name(commit)} && git reset --hard #{commit} && git clean -f -d")

      # Run user supplied build code in the context of the checked out code.
      begin
        @_remote_context = "#{remote_project_dir}/package/#{artifact_name(commit)}"
        super
      ensure
        @_remote_context = nil
      end

      # Package build folder into tgz.
      remote_exec("rm -f #{artifact_name(commit)}.tar.gz && cd #{artifact_name(commit)} && tar #{excludes_for_tar} -czf ../#{artifact_name(commit)}.tar.gz .")

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
        remote_exec("rm -rf #{artifact_name(commit)}")
      end

      puts "Sucessfully packaged #{commit} to #{destination}/#{artifact_name(commit)}.tar.gz"
    end

    protected

    def remote_project_dir
      "#{remote_dir}/#{project}"
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
