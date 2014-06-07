module Harrison
  class Package < Base
    def initialize(args, opts={})
      self.class.option_helper(:project)
      self.class.option_helper(:git_src)
      self.class.option_helper(:commit)
      self.class.option_helper(:purge)
      self.class.option_helper(:exclude)
      self.class.option_helper(:pkg_dir)

      arg_opts = [
        [ :commit, "Specific commit to be packaged. Accepts anything that `git rev-parse` understands.", :type => :string, :default => "HEAD" ],
        [ :purge, "Remove all previously packaged commits from the build host's working directory when finished.", :type => :boolean, :default => false ],
        [ :pkg_dir, "Local folder to save package to.", :type => :string, :default => "pkg" ],
      ]

      super(args, arg_opts, opts)
    end

    def run(&block)
      return super if block_given?

      # Things to run before the user provided code.
      ensure_local_dir(pkg_dir)

      super
    end

    def remote_exec(cmd)
      ensure_remote_dir("#{remote_project_dir}/package")

      super("cd #{remote_project_dir}/package && #{cmd}")
    end
  end
end
