module Harrison
  class Deploy < Base
    attr_accessor :artifact
    attr_accessor :host # The specific host among --hosts that we are currently working on.
    attr_accessor :release_dir
    attr_accessor :deploy_link

    attr_accessor :rollback
    attr_accessor :phases

    alias :invoke_user_block :run

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

      self.add_default_phases
    end

    def parse(args)
      super

      # Preserve argv hosts if it's been passed.
      @_argv_hosts = self.hosts.dup if self.hosts

      self.rollback = args[0] == 'rollback'

      unless self.rollback
        # Make sure they passed an artifact.
        self.artifact = args[1] || abort("ERROR: You must specify the artifact to be deployed as an argument to this command.")
      end
    end

    def add_phase(name, &block)
      @_phases ||= Hash.new

      @_phases[name] = Harrison::Deploy::Phase.new(name, &block)
    end

    def remote_exec(cmd)
      super("cd #{remote_project_dir} && #{cmd}")
    end

    def current_symlink
      "#{self.remote_project_dir}/current"
    end

    def update_current_symlink
      @_old_current = self.remote_exec("if [ -L #{current_symlink} ]; then readlink -vn #{current_symlink}; fi")
      @_old_current = nil if @_old_current.empty?

      # Symlink current to new deploy.
      self.remote_exec("ln -sfn #{self.deploy_link} #{self.current_symlink}")
    end

    def revert_current_symlink
      # Restore current symlink to previous if set.
      if @_old_current
        self.remote_exec("ln -sfn #{@_old_current} #{self.current_symlink}")
      end
    end

    def run
      # Override Harrisonfile hosts if it was passed on argv.
      self.hosts = @_argv_hosts if @_argv_hosts

      # Require at least one host.
      if !self.hosts || self.hosts.empty?
        abort("ERROR: You must specify one or more hosts to deploy/rollback on, either in your Harrisonfile or via --hosts.")
      end

      # Default to just built in deployment phases.
      self.phases ||= [ :upload, :extract, :link, :cleanup ]

      # Default base_dir.
      self.base_dir ||= '/opt'

      if self.rollback
        puts "Rolling back \"#{project}\" to previously deployed release on #{hosts.size} hosts...\n\n"

        # Find the prior deploy on the first host.
        self.host = hosts[0]
        last_deploy = self.deploys.sort.reverse[1] || abort("ERROR: No previous deploy to rollback to.")
        self.release_dir = remote_exec("cd deploys && readlink -vn #{last_deploy}")

        # No need to upload or extract for rollback.
        self.phases.delete(:upload)
        self.phases.delete(:extract)

        # Don't cleanup old deploys either.
        self.phases.delete(:cleanup)
      else
        puts "Deploying #{artifact} for \"#{project}\" onto #{hosts.size} hosts...\n\n"
        self.release_dir = "#{remote_project_dir}/releases/" + File.basename(artifact, '.tar.gz')
      end

      self.deploy_link = "#{remote_project_dir}/deploys/" + Time.new.utc.strftime('%Y-%m-%d_%H%M%S')

      progress_stack = []

      failed = catch(:failure) do
        self.phases.each do |phase_name|
          phase = @_phases[phase_name] || abort("ERROR: Could not resolve \"#{phase_name}\" as a deployment phase.")

          self.hosts.each do |host|
            self.host = host

            phase._run(self)

            # Track what phases we have completed on which hosts, in a stack.
            progress_stack << { host: host, phase: phase_name }
          end
        end

        # We want "failed" to be false if nothing was caught.
        false
      end

      if failed
        print "\n"

        progress_stack.reverse.each do |progress|
          self.host = progress[:host]
          phase = @_phases[progress[:phase]]

          # Don't let failures interrupt the rest of the process.
          catch(:failure) do
            phase._fail(self)
          end
        end

        abort "\nDeployment failed, previously completed deployment actions have been reverted."
      else
        if self.rollback
          puts "\nSucessfully rolled back #{project} on #{hosts.join(', ')}."
        else
          puts "\nSucessfully deployed #{artifact} to #{hosts.join(', ')}."
        end
      end
    end

    def cleanup_deploys(limit)
      # Grab a list of deploys to be removed.
      purge_deploys = self.deploys.sort.reverse.slice(limit..-1) || []

      if purge_deploys.size > 0
        puts "[#{self.host}]   Purging #{purge_deploys.size} old deploys. (Keeping #{limit}...)"

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

    def add_default_phases
      self.add_phase :upload do |phase|
        phase.on_run do |h|
          h.ensure_remote_dir("#{h.remote_project_dir}/deploys")
          h.ensure_remote_dir("#{h.remote_project_dir}/releases")

          # Remove if it already exists.
          # TODO: if --force only?
          h.remote_exec("rm -f #{h.remote_project_dir}/releases/#{File.basename(h.artifact)}")

          if match = h.remote_regex.match(h.artifact)
            # Copy artifact to host from remote source.
            src_user, src_host, src_path = match.captures
            src_user ||= h.user

            h.remote_exec("scp #{src_user}@#{src_host}:#{src_path} #{h.remote_project_dir}/releases/")
          else
            # Upload artifact to host.
            h.upload(h.artifact, "#{h.remote_project_dir}/releases/")
          end
        end

        phase.on_fail do |h|
          # Remove staged artifact.
          h.remote_exec("rm -f #{h.remote_project_dir}/releases/#{File.basename(h.artifact)}")
        end
      end

      self.add_phase :extract do |phase|
        phase.on_run do |h|
          # Make folder for release or bail if it already exists.
          h.remote_exec("mkdir #{h.release_dir}")

          # Unpack.
          h.remote_exec("cd #{h.release_dir} && tar -xzf ../#{File.basename(h.artifact)}")

          # Clean up artifact.
          h.remote_exec("rm -f #{h.remote_project_dir}/releases/#{File.basename(h.artifact)}")
        end

        phase.on_fail do |h|
          # Remove release.
          h.remote_exec("rm -rf #{h.release_dir}")
        end
      end

      self.add_phase :link do |phase|
        phase.on_run do |h|
          # Symlink new deploy to this release.
          h.remote_exec("ln -s #{h.release_dir} #{h.deploy_link}")
        end

        phase.on_fail do |h|
          # Remove broken deploy.
          h.remote_exec("rm -f #{h.deploy_link}")
        end
      end

      self.add_phase :cleanup do |phase|
        phase.on_run do |h|
          if (h.keep)
            h.cleanup_deploys(h.keep)
            h.cleanup_releases
          end
        end
      end
    end

    def ssh
      @_conns ||= {}
      @_conns[self.host] ||= Harrison::SSH.new(host: self.host, user: @options[:user], proxy: self.deploy_via)
    end

    def remote_project_dir
      "#{base_dir}/#{project}"
    end

    # Return a list of deploys, unsorted.
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
