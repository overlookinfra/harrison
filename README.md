# Harrison

TODO: Write a gem description

## Installation

Add this line to your application's Gemfile:

    gem 'harrison'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install harrison

## Usage

Example Harrisonfile:

```ruby
# This is an example Harrisonfile used for development/testing.

# Project-wide Config
Harrison.config do |h|
  h.project = 'harrison'
  h.git_src = "git@github.com:puppetlabs/harrison.git"
end

Harrison.package do |h|
  # Where to build package.
  h.host = '10.16.18.207'
  h.user = 'jesse'

  # Things we don't want to package.
  h.exclude = %w(.git config coverage examples log module_files pkg tmp spec)

  # Define the build process here.
  h.run do |h|
    # Bundle Install
    h.remote_exec("cd #{h.commit} && bash -l -c \"bundle install --path=vendor --without=\\\"development packaging test doc\\\"\"")
  end
end

Harrison.deploy do |h|
  h.hosts = [ '10.16.18.207' ]
  h.user = 'jesse'
  h.base_dir = '/opt'

  # Run block will be invoked once for each host after new code is in place.
  h.run do |h|
    # You can interrogate h.host to see what host you are currently running on.
    if h.host =~ /util/
      # Do something on the util box.
    else
      puts "Reloading Unicorn on #{h.host}..."
      h.remote_exec("sudo -- /etc/init.d/unicorn_#{h.project} reload")
    end
  end
end
```

## Contributing

1. Fork it ( https://github.com/[my-github-username]/harrison/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
