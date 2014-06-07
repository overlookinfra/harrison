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
Harrison.package do |h|
  # Config
  h.project = 'harrison'
  h.host = '10.0.0.5'
  h.user = 'jesse'

  h.run do |h|
    # Actual packaging process.

    # Find some things from git.
    h.git_src = h.exec("git config --get remote.origin.url")
    h.commit = h.exec("git rev-parse --short #{h.commit} 2>/dev/null")

    # Things we don't want to package.
    h.exclude = %w(.git config coverage examples log module_files pkg tmp spec)

    # Fetch/clone git repo on remote host.
    h.remote_exec("if [ -d cached ] ; then cd cached && git fetch origin -p ; else git clone #{h.git_src} cached ; fi")

    # Check out target commit.
    h.remote_exec("cd cached && git reset --hard #{h.commit}")
  end
end

Harrison.deploy do |h|
  # Some other stuff.
end
```

## Contributing

1. Fork it ( https://github.com/[my-github-username]/harrison/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
