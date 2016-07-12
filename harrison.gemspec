# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'harrison/version'

Gem::Specification.new do |spec|
  spec.name          = "harrison"
  spec.version       = Harrison::VERSION
  spec.authors       = ["Jesse Scott"]
  spec.email         = ["jesse@puppetlabs.com"]
  spec.summary       = %q{Simple artifact-based deployment for web applications.}
  spec.homepage      = "https://github.com/puppetlabs/harrison"
  spec.license       = "Apache 2.0"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = ["harrison"]
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.required_ruby_version = '>= 1.9.3'

  spec.add_runtime_dependency "trollop", "~> 2.1.2"
  spec.add_runtime_dependency "net-ssh", "~> 2.9.1"
  spec.add_runtime_dependency "net-scp", "~> 1.2.1"
  spec.add_runtime_dependency "highline", "~> 1.7.8"

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "pry-debugger" if RUBY_VERSION < "2.0.0"
  spec.add_development_dependency "pry-byebug" if RUBY_VERSION >= "2.0.0"
  spec.add_development_dependency "sourcify"
end
