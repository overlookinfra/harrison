module Harrison
  class Deploy < Base
    attr_accessor :artifact
    attr_accessor :host # The specific host among --hosts that we are currently working on.
    attr_accessor :release_dir
    attr_accessor :deploy_link

    def initialize(opts={})
      # Config helpers for Harrisonfile.
      self.class.option_helper(:hosts)
      self.class.option_helper(:env)
      self.class.option_helper(:base_dir)
      self.class.option_helper(:deploy_via)
      self.class.option_helper(:keep)

      # Command line opts for this action. Will be merged with common opts.
      arg_opts = [
        [ :hosts, "List of remote hosts to deploy to. Can also be specified in Harrisonfile.", :type => :strings ],
        [ :env, "Environment to deploy to. This can be examined in your Harrisonfile to calculate target hosts.", :type => :string ],
        [ :keep, "Number of recent deploys to keep after a successful deploy. (Including the most recent deploy.) Defaults to keeping all deploys forever.", :type => :integer ],
      ]

      super(arg_opts, opts)
    end

    def parse(args)
      super

      # Preserve argv hosts if it's been passed.
      @_argv_hosts = self.hosts.dup if self.hosts

      # Make sure they passed an artifact.
      self.artifact = args[1] || abort("ERROR: You must specify the artifact to be deployed as an argument to this command.")
    end

    def remote_exec(cmd)
      super("cd #{remote_project_dir} && #{cmd}")
    end

    def run(&block)
      return super if block_given?

      # Override Harrisonfile hosts if it was passed on argv.
      self.hosts = @_argv_hosts if @_argv_hosts

      if !self.hosts || self.hosts.empty?
        abort("ERROR: You must specify one or more hosts to deploy to, either in your Harrisonfile or via --hosts.")
      end

      # Default base_dir.
      self.base_dir ||= '/opt'

      puts "Deploying #{artifact} for \"#{project}\" onto #{hosts.size} hosts..."

      self.release_dir = "#{remote_project_dir}/releases/" + File.basename(artifact, '.tar.gz')
      self.deploy_link = "#{remote_project_dir}/deploys/" + Time.new.utc.strftime('%Y-%m-%d_%H%M%S')

      hosts.each do |h|
        self.host = h

        ensure_remote_dir("#{remote_project_dir}/deploys", self.ssh)
        ensure_remote_dir("#{remote_project_dir}/releases", self.ssh)

        # Make folder for release or bail if it already exists.
        remote_exec("mkdir #{release_dir}")

        if match = remote_regex.match(artifact)
          # Copy artifact to host from remote source.
          src_user, src_host, src_path = match.captures
          src_user ||= self.user

          remote_exec("scp #{src_user}@#{src_host}:#{src_path} #{remote_project_dir}/releases/")
        else
          # Upload artifact to host.
          upload(artifact, "#{remote_project_dir}/releases/")
        end

        # Unpack.
        remote_exec("cd #{release_dir} && tar -xzf ../#{File.basename(artifact)}")

        # Clean up artifact.
        remote_exec("rm -f #{remote_project_dir}/releases/#{File.basename(artifact)}")

        # Symlink a new deploy to this release.
        remote_exec("ln -s #{release_dir} #{deploy_link}")

        # Symlink current to new deploy.
        remote_exec("ln -sfn #{deploy_link} #{remote_project_dir}/current")

        # Run user supplied deploy code to restart server or whatever.
        super

        # Cleanup old releases if a keep value is set.
        if (self.keep)
          cleanup_deploys(self.keep)
          cleanup_releases
        end

        close(self.host)
      end

      puts "Sucessfully deployed #{artifact} to #{hosts.join(', ')}."
    end

    def cleanup_deploys(limit)
      # Grab a list of deploys to be removed.
      purge_deploys = self.deploys.sort.reverse.slice(limit..-1) || []

      if purge_deploys.size > 0
        puts "Purging #{purge_deploys.size} old deploys on #{self.host}, keeping #{limit}..."

        purge_deploys.each do |stale_deploy|
          remote_exec("cd deploys && rm -f #{stale_deploy}")
        end
      end
    end

    def cleanup_releases
      # Figure out which releases need to be kept.
      keep_releases = self.active_releases

      self.releases.each do |release|
        unless keep_releases.include?(release)
          remote_exec("cd releases && rm -rf #{release}")
        end
      end
    end

    def close(host=nil)
      if host
        @_conns[host].close if @_conns && @_conns[host]
      elsif @_conns
        @_conns.keys.each do |host|
          @_conns[host].close unless @_conns[host].closed?
        end
      end
    end

    protected

    def ssh
      @_conns ||= {}
      @_conns[self.host] ||= Harrison::SSH.new(host: self.host, user: @options[:user], proxy: self.deploy_via)
    end

    def remote_project_dir
      "#{base_dir}/#{project}"
    end

    # Return a sorted list of deploys, unsorted.
    def deploys
      remote_exec("cd deploys && ls -1").split("\n")
    end

    # Return a list of all releases, unsorted.
    def releases
      remote_exec("cd releases && ls -1").split("\n")
    end

    # Return a list of releases with at least 1 deploy pointing to them, unsorted.
    def active_releases
      self.deploys.collect { |deploy| remote_exec("cd deploys && basename `readlink #{deploy}`") }.uniq
    end
  end
end
