module Harrison
  class Base
    attr_reader :ssh
    attr_accessor :options

    def initialize(arg_opts=[], opts={})
      # Config helpers for Harrisonfile.
      self.class.option_helper(:user)
      self.class.option_helper(:env)

      @arg_opts = arg_opts
      @arg_opts << [ :debug, "Output debug messages.", :type => :boolean, :default => false ]
      @arg_opts << [ :env, "Environment to package for or deploy to. This can be examined in your Harrisonfile to calculate target hosts.", :type => :string ]

      @options = opts
    end

    def self.option_helper(option)
      send :define_method, option do
        @options[option]
      end

      send :define_method, "#{option}=" do |val|
        @options[option] = val
      end
    end

    # Add config getter methods from Harrison.config to this class.
    Harrison::Config.config_keys.each do |key|
      define_method(key) do
        Harrison.config.send(key)
      end
    end

    def exec(cmd)
      result = `#{cmd}`

      if ($?.success? && result)
        result.strip
      else
        throw :failure, true
      end
    end

    def remote_exec(cmd)
      result = ssh.exec(cmd)

      if result
        result.strip
      else
        throw :failure, true
      end
    end

    def parse(args)
      opt_parser = Trollop::Parser.new

      @arg_opts.each do |arg_opt|
        opt_parser.opt(*arg_opt)
      end

      @options.merge!(Trollop::with_standard_exception_handling(opt_parser) do
        opt_parser.parse(args)
      end)

      Harrison.send(:remove_const, "DEBUG") if Harrison.const_defined?("DEBUG")
      Harrison.const_set("DEBUG", @options[:debug])
    end

    def run(&block)
      if block_given?
        # If called with a block, convert it to a proc and store.
        @run_block = block
      else
        # Otherwise, invoke the previously stored block with self.
        @run_block && @run_block.call(self)
      end
    end

    def download(remote_path, local_path)
      ssh.download(remote_path, local_path)
    end

    def upload(local_path, remote_path)
      ssh.upload(local_path, remote_path)
    end

    def close
      ssh.close if @ssh
    end

    protected

    def ssh
      @ssh ||= Harrison::SSH.new(host: @options[:host], user: @options[:user])
    end

    def remote_regex
      /^(?:(\S+)@)?(\S+):(\S+)$/
    end

    def ensure_local_dir(dir)
      @_ensured_local ||= {}
      @_ensured_local[dir] || (system("if [ ! -d #{dir} ] ; then mkdir -p #{dir} ; fi") && @_ensured_local[dir] = true) || abort("Error: Unable to create local directory \"#{dir}\".")
    end

    def ensure_remote_dir(dir, with_ssh = nil)
      with_ssh ||= ssh
      host = with_ssh.host

      @_ensured_remote ||= {}
      @_ensured_remote[host] ||= {}
      @_ensured_remote[host][dir] || (with_ssh.exec("if [ ! -d #{dir} ] ; then mkdir -p #{dir} ; fi") && @_ensured_remote[host][dir] = true) || abort("Error: Unable to create remote directory \"#{dir}\" on \"#{host}\".")
    end
  end
end
