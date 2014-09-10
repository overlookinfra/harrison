# Harrison

Simple artifact-based deployment for web applications.

[![Build Status](https://travis-ci.org/scotje/harrison.svg?branch=master)](https://travis-ci.org/scotje/harrison)

## Installation

Add this line to your application's Gemfile:

    gem 'harrison'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install harrison

## Usage

First, create a Harrisonfile in the root of your project. Here's an example:

```ruby
# Project-wide Config
Harrison.config do |h|
  h.project = 'harrison'
  h.git_src = "git@github.com:scotje/harrison.git"
end

Harrison.package do |h|
  # Where to build package.
  h.host = 'build-server.example.com'
  h.user = 'jesse'

  # Things we don't want to package.
  h.exclude = %w(.git ./config ./coverage ./examples ./log ./pkg ./tmp ./spec)

  # Where to save the artifact by default.
  h.destination = 'pkg' # Local folder
  # h.destination = 'jesse@artifact-host.example.com:/tmp/artifacts' # Remote folder

  # Define the build process here.
  h.run do |h|
    # Bundle Install
    h.remote_exec("cd #{h.commit} && bash -l -c \"bundle install --path=vendor --without=\\\"development packaging test doc\\\"\"")
  end
end

Harrison.deploy do |h|
  h.hosts = [ 'util-server-01.example.com', 'app-server-01.example.com', 'app-server-02.example.com' ]
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

Next, ensure that your SSH key is authorized to log in as the `user` you have specified in
the Harrisonfile for each task. (Or be ready to type the password a lot. :weary:)

### Building a Release

Use the `harrison package` command:

```
$ harrison package
```

By default this will build and package `HEAD` of your current branch. You may specify another commit to
build using the `--commit` option:

```
$ harrison package --commit mybranch
```

The `--commit` option understands anything that `git rev-parse` understands. *NOTE: The commit you
reference must be pushed to the repository referenced as `git_src` in the Harrisonfile before
you can build it.*

The packaged release artifact will, by default, be saved into a local 'pkg' subfolder:

```
$ harrison package
Packaging 5a547d8 for "harrison" on build-server.example.com...
Sucessfully packaged 5a547d8 to pkg/20140711170226-5a547d8.tar.gz
```

You can set the destination on the command line with the `--destination` option, or
specify a new default in your Harrisonfile:

```
h.destination = '/tmp'
```

You can also specify a remote destination:

```
h.destination = 'jesse@artifact-host.example.com:/tmp/artifacts'
```

The username is optional and, if omitted, the build user will be used. *NOTE: Your build server
must have already accepted the SSH host key of the destination server in order to transfer the
artifact.*

There are some additional options available, run `harrison package --help` to see everything available.


### Deploying a Release

Use the `harrison deploy` command passing the artifact to be deployed as an argument:

```
$ harrison deploy pkg/20140711170226-5a547d8.tar.gz
```

You can also deploy from a remote artifact source:

```
$ harrison deploy jesse@artifact-host.example.com:/tmp/artifacts/20140711170226-5a547d8.tar.gz
```

*NOTE: Each target server must have already accepted the SSH host key of the source server in order to
transfer the artifact.*

By default, the artifact will be deployed to the list of hosts defined in your Harrisonfile.

You can override the target hosts by passing a `--hosts` option:

```
$ harrison deploy pkg/20140711170226-5a547d8.tar.gz --hosts test-app-server-01.example.com test-app-server-02.example.com
```

You can also pass an `--env` option to deploy into multi-stage environments:

```
$ harrison deploy pkg/20140711170226-5a547d8.tar.gz --env prod
```

This value can then be tested to alter the default target hosts in your Harrisonfile:

```ruby
if h.env =~ /prod/
  h.hosts = [ 'app-server-01.prod.example.com', 'app-server-02.prod.example.com' ]
else
  h.hosts = [ 'app-server-01.stage.example.com', 'app-server-02.stage.example.com' ]
end
```

You can use the `--keep` option (or set it in the deploy section of your Harrisonfile) to specify the total number of
deploys you want to retain on each server after a successful deployment. The default is to keep all previous deploys
around indefinitely.

There are some additional options available, run `harrison deploy --help` to see everything available.


## Contributing

1. Fork it ( https://github.com/scotje/harrison/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
