require "trollop"
require "harrison/version"
require "harrison/ssh"
require "harrison/config"
require "harrison/base"
require "harrison/package"
require "harrison/deploy"

module Harrison

  def self.invoke(args)
    @@args = args.freeze

    abort("No command given. Run with --help for valid commands and options.") if @@args.empty?

    # Catch root level --help
    Harrison::Base.new.parse(@@args.dup) and exit(0) if @@args[0] == '--help'

    # Find Harrisonfile.
    hf = find_harrisonfile
    abort("ERROR: Could not find a Harrisonfile in this directory or any ancestor.") if hf.nil?

    # Find the class to handle command.
    @@runner = find_runner(@@args[0])
    abort("ERROR: Unrecognized command \"#{@@args[0]}\".") unless @@runner

    # Eval the Harrisonfile.
    eval_script(hf)

    # Invoke command and cleanup afterwards.
    begin
      @@runner.call.run
    ensure
      @@runner.call.close
    end
  end

  def self.config(opts={})
    @@config ||= Harrison::Config.new(opts)

    if block_given?
      yield @@config
    else
      @@config
    end
  end

  def self.package(opts={})
    @@packager ||= Harrison::Package.new(opts)

    # Parse options if this is the target command.
    @@packager.parse(@@args.dup) if @@runner && @@runner.call == @@packager

    yield @@packager
  end

  def self.deploy(opts={})
    @@deployer ||= Harrison::Deploy.new(opts)

    # Parse options if this is the target command.
    @@deployer.parse(@@args.dup) if @@runner && @@runner.call == @@deployer

    yield @@deployer
  end


  private

  def self.find_harrisonfile
    previous = nil
    current  = File.expand_path(Dir.pwd)

    until !File.directory?(current) || current == previous
      filename = File.join(current, 'Harrisonfile')
      return filename if File.file?(filename)
      current, previous = File.expand_path("..", current), current
    end
  end

  def self.eval_script(filename)
    proc = Proc.new {}
    eval(File.read(filename), proc.binding, filename)
  end

  def self.find_runner(command)
    case command.downcase
      when 'package' then lambda { @@packager if self.class_variable_defined?(:@@packager) }
      when 'deploy' then lambda { @@deployer if self.class_variable_defined?(:@@deployer) }
    end
  end
end
