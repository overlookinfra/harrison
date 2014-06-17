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

      # Command line opts for this action. Will be merged with common opts.
      arg_opts = [
        [ :hosts, "List of remote hosts to deploy to. Can also be specified in Harrisonfile.", :type => :strings ],
        [ :env, "Environment to deploy to. This can be examined in your Harrisonfile to calculate target hosts.", :type => :string ],
      ]

      super(arg_opts, opts)
    end

    def parse(args)
      # Preserve Harrisonfile hosts setting in case it's not passed.
      hf_hosts = self.hosts.dup

      super

      self.hosts ||= hf_hosts
      self.artifact = args[1] || abort("ERROR: You must specify the artifact to be deployed as an argument to this command.")
      self.base_dir ||= '/opt' # Default deployment location.
    end

    def remote_exec(cmd)
      super("cd #{remote_project_dir} && #{cmd}")
    end

    def run(&block)
      return super if block_given?

      puts "Deploying #{artifact} for \"#{project}\" onto #{hosts.size} hosts..."


      self.release_dir = "#{remote_project_dir}/releases/" + File.basename(artifact, '.tar.gz')
      self.deploy_link = "#{remote_project_dir}/deploys/" + Time.new.utc.strftime('%Y-%m-%d_%H%M%S')

      hosts.each do |h|
        self.host = h

        ensure_remote_dir(self.host, "#{remote_project_dir}/deploys")
        ensure_remote_dir(self.host, "#{remote_project_dir}/releases")

        # Make folder for release or bail if it already exists.
        remote_exec("mkdir #{release_dir}")

        # Upload artifact to host.
        upload(artifact, "#{remote_project_dir}/releases/")

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

        close(self.host)
      end

      puts "Sucessfully deployed #{artifact} to #{hosts.join(', ')}."
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
  end
end
