module Harrison
  class Base
    attr_reader :ssh
    attr_accessor :options

    def initialize(arg_opts=[], opts={})
      # Config helpers for Harrisonfile.
      self.class.option_helper(:user)

      @arg_opts = arg_opts
      @arg_opts << [ :debug, "Output debug messages.", :type => :boolean, :default => false ]

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

    # Find config from Harrison.config if it's not on this class.
    def method_missing(meth, *args, &block)
      if Harrison.config.respond_to?(meth)
        Harrison.config.send(meth, *args, &block)
      else
        super
      end
    end

    def exec(cmd)
      result = `#{cmd}`
      abort("ERROR: Unable to execute local command: \"#{cmd}\"") if !$?.success? || result.nil?
      result.strip
    end

    def remote_exec(cmd)
      result = ssh.exec(cmd)
      abort("ERROR: Unable to execute remote command: \"#{cmd}\"") if result.nil?
      result.strip
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

    def ensure_local_dir(dir)
      @_ensured_local ||= {}
      @_ensured_local[dir] || (system("if [ ! -d #{dir} ] ; then mkdir -p #{dir} ; fi") && @_ensured_local[dir] = true) || abort("Error: Unable to create local directory \"#{dir}\".")
    end

    def ensure_remote_dir(dir)
      @_ensured_remote ||= {}
      @_ensured_remote[dir] || (ssh.exec("if [ ! -d #{dir} ] ; then mkdir -p #{dir} ; fi") && @_ensured_remote[dir] = true) || abort("Error: Unable to create remote directory \"#{dir}\".")
    end
  end
end
