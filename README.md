# The Ruby Backgrounding Toolkit

RBG (Ruby BackGrounder) is a small utility to help running a process
in the background (or foreground). It provides a method for starting, 
stopping & restarting a background process.

## Features

* Automatically spawn multiple instances of your processes.
* Easily deploy & run processes in the background.
* Monitor memory usage of processes and respawn when they reach a limit.
* Automatically restart processes which stop running.

## Installation

Just add the gem to your Gemfile.

```ruby
gem 'rbg', '~> 1.8.0'
```

## Setup

Depending on your application, there are a number of ways to get started.
If you have an application which only needs to run a single process, 
you'll just need to add an `Rbgfile` to the root of your project.

An example `Rbgfile` looks like this. This example if for a Rails application
which wishes to run 4 background workers.

```ruby
Rbg.config.tap do |config|

  # Enter a name for the process (this will be displayed in your process list)
  config.name = "worker"

  # Enter the number of these processes which should be running
  config.workers = 4
  
  # Configure a block of code to execute before child processes are spawned
  config.before_fork do
    ENV['RAILS_ENV'] = $rbg_env
    require File.join(config.root, 'config', 'environment')
  end
  
  # Configure a block to execute in each child after it has been forked
  config.after_fork do
    ActiveRecord::Base.establish_connection
    srand
  end
  
  # Configure the script/process to run. You can either specifiy the path
  # to a script (as a string) or you can pass a block to this method.
  config.script do
    Delayed::Worker.new.start
  end
  
  # Automatically respawn this process if it fails and set the respawn limits
  # to only respawn if the process doesn't die 5 times within 30 seconds of 
  # starting.
  config.respawn = true
  config.respawn_limits = [5,30]
  
  # Sets the memory limit (in MB) for each child process. When the child process
  # reaches this limit, it will be sent a kill signal. It is recommended to use
  # this with the respawn options above.
  config.memory_limit = 100
  
end
```

There are various other configuration options which you can specify however they 
are not required and will assume the defaults shown below.

* `config.root` - the root of your application/script. By default we assume this
  to be the directory you executed the `rbg` command from.
  
* `config.log_path` - the path were you would like STDOUT and STDERR to be stored
  when the process is running. By default this will be `{root}/log/{name}.log`.

* `config.pid_path` - the path to the PID file where the process ID will be stored
  when the process runs in the background. By default this will be `{root}/log/{name}.pid`.


## Starting/Stopping

Once you have configured your `Rbgfile`, you can use the following commands to 
manage the process.

* `rbg start` - this will execute your process in the background.

* `rbg stop` - this will stop the background process.

* `rbg restart` - this will restart the background process by stopping it and 
  starting it again.

* `rbg run` - this will run the process in the foreground and log output will be 
  sent to your terminal.

There are a number of options which can be passed to any of these commands:

* `-E {environment}` - the environment which will be set. This is set as $rbg_env
  and is 'development' by default. 

* `-c path/to/config` - the path to your Rbgfile. By default, this is just `Rbgfile`
  in your current directory. 

## How it works...

* In the background, the system works by creating a number of management processes.

* When you first run start your process, a `master` process will be created. This 
  process will exist until you stop the command. This process doesn't run any of 
  your code and simply exists to receive signals. Any control signal you wish to
  send to your process(es) should be sent to this `master` process.

* The master process will then fork to a `parent` process which in turn will fork
  a number of `child` processes. The number of processes will depend on the value 
  you set in `workers` in your Rbgfile. 

* Your `before_fork` method will be executed in your parent process before it 
  creates the child processes. Each child process will then run `after_fork`,
  followed immediately by the `script` block/script.

* When you restart, the parent process (along with its children) will be killed 
  entirely and respawned. Therefore, if you have changed any code which has been
  required, you should ensure that it is required in the `before_fork` block
  rather than in the root of the configuration file.
