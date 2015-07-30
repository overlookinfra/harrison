require "trollop"
require "harrison/version"
require "harrison/ssh"
require "harrison/config"
require "harrison/base"
require "harrison/package"
require "harrison/deploy"
require "harrison/deploy/phase"

begin
  require "pry"
rescue LoadError
end

module Harrison

  def self.invoke(args)
    @@args = args.freeze
    @@task_runners = {
      package: nil,
      deploy: nil,
    }

    abort("No command given. Run with --help for valid commands and options.") if @@args.empty?

    # Catch root level --help
    Harrison::Base.new.parse(@@args.dup) and exit(0) if @@args[0] == '--help'

    # Find Harrisonfile.
    hf = find_harrisonfile || abort("ERROR: Could not find a Harrisonfile in this directory or any ancestor.")

    # Find the class to handle command.
    @@runner = find_runner(@@args[0]) || abort("ERROR: Unrecognized command \"#{@@args[0]}\".")

    # Eval the Harrisonfile.
    eval_script(hf)

    # Invoke command and cleanup afterwards.
    begin
      @@runner.call.run
    rescue => e
      raise e
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
    @@task_runners[:package] ||= Harrison::Package.new(opts)

    # Parse options if this is the target command.
    @@task_runners[:package].parse(@@args.dup) if @@runner && @@runner.call == @@task_runners[:package]

    yield @@task_runners[:package]
  end

  def self.deploy(opts={})
    @@task_runners[:deploy] ||= Harrison::Deploy.new(opts)

    # Parse options if this is the target command.
    @@task_runners[:deploy].parse(@@args.dup) if @@runner && @@runner.call == @@task_runners[:deploy]

    yield @@task_runners[:deploy]
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
    command = 'deploy' if command == 'rollback'

    lambda { @@task_runners[command.to_sym] } if @@task_runners.has_key?(command.to_sym)
  end
end
