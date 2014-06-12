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

    abort("No command given.") if @@args.empty?

    hf = find_harrisonfile
    abort("Error: Could not find a Harrisonfile in this directory or any ancestor.") if hf.nil?

    eval_script(hf)

    runner = case @@args[0].downcase
      when 'package' then @@packager
      when 'deploy' then @@deployer
      else
        abort("ERROR: Unrecognized command \"#{@@args[0]}\".")
    end

    runner.parse(@@args.dup)

    begin
      runner.run
    ensure
      runner.close
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
    @@packager = Harrison::Package.new(@@args.dup, opts)
    yield @@packager
  end

  def self.deploy(opts={})
    @@deployer = Harrison::Deploy.new(@@args.dup, opts)
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
end
