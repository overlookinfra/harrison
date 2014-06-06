require "harrison/version"
require "harrison/ssh"
require "harrison/package"
require "harrison/deploy"

module Harrison

  def self.invoke(opts={})
    hf = find_harrisonfile
    abort("Error: Could not find a Harrisonfile in this directory or any ancestor.") if hf.nil?

    eval_script(hf, opts)
  end

  def self.package(opts={})
    packager = Harrison::Package.new(opts)
    yield packager
    packager.ssh.close
  end

  def self.deploy(opts={})
    yield Harrison::Deploy.new(opts)
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

  def self.eval_script(filename, opts={})
    proc = Proc.new {}
    eval(File.read(filename), proc.binding, filename)
  end
end
