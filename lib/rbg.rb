require 'rbg/config'

module Rbg
  class Error < StandardError; end

  class << self

    ## An array of child PIDs for the current process which have been spawned
    attr_accessor :child_processes

    ## The path to the config file that was specified
    attr_accessor :config_file

    ## Return a configration object for this backgroundable application.
    def config
      @config ||= Rbg::Config.new
    end

    # Return a logger object for this application
    def logger
      self.config.logger
    end

    # Creates a 'parent' process. This is responsible for executing 'before_fork'
    # and then forking the worker processes.
    def start_parent
      # Record the PID of this parent in the Master
      parent_pid = fork do
        # Clear the child process list as this fork doesn't have any children yet
        self.child_processes = Hash.new

        # Set the process name (Parent)
        $0="#{self.config.name}[Parent]"

        # Debug information
        logger.info "New parent process: #{Process.pid}"
        STDOUT.flush

        # Run the before_fork function
        if config.before_fork.is_a?(Proc)
          self.config.before_fork.call
        end

        # Fork an appropriate number of workers
        self.fork_workers(self.config.workers)

        # If we get a TERM, send the existing workers a TERM then exit
        Signal.trap("TERM", proc {
          # Debug output
          logger.info "Parent got a TERM."
          STDOUT.flush

          # Send TERM to workers
          kill_child_processes

          # Exit the parent
          Process.exit(0)
        })

        # Ending parent processes on INT is not useful or desirable
        # especially when running in the foreground
        Signal.trap('INT', proc {})
        Signal.trap('HUP', proc {})

        # Parent loop, the purpose of this is simply to do nothing until we get a signal
        # We will exit if all child processes die
        # We may add memory management code here in the future
        loop do
          sleep 2
          child_processes.dup.each do |id, opts|
            begin

              Process.getpgid(opts[:pid])

              if config.memory_limit
                # Lookup the memory usge for this PID
                memory_usage = `ps -o rss= -p #{opts[:pid]}`.strip.to_i / 1024
                if memory_usage > config.memory_limit
                  logger.info "#{self.config.name}[#{id}] is using #{memory_usage}MB of memory (limit: #{config.memory_limit}MB). It will be killed."
                  kill_child_process(id)
                end
              end

            rescue Errno::ESRCH
              logger.info "Child process #{config.name}[#{id}] has died (from PID #{opts[:pid]})"
              child_processes[id][:pid] = nil

              if config.respawn
                if opts[:started_at] > Time.now - config.respawn_limits[1]
                  if opts[:respawns] >= config.respawn_limits[0]
                    logger.info "Process #{config.name}[#{id}] has instantly respawned #{opts[:respawns]} times. It won't be respawned again."
                    child_processes.delete(id)
                  else
                    logger.info "Process has died within #{config.respawn_limits[1]}s of the last spawn."
                    child_processes[id][:respawns] += 1
                    fork_worker(id)
                  end
                else
                  logger.info "Process was started more than #{config.respawn_limits[1]}s since the last spawn. Resetting spawn counter"
                  child_processes[id][:respawns] = 0
                  fork_worker(id)
                end
              else
                child_processes.delete(id)
              end
            end
          end

          if child_processes.empty?
            logger.info "All child processes died, exiting parent"
            Process.exit(0)
          end
        end
      end

      # Store the PID for the parent
      child_processes[0] = {:pid => parent_pid, :respawns => 0}
      # Ensure the new parent is detached
      Process.detach(parent_pid)
    end

    # Wrapper to fork multiple workers
    def fork_workers(n)
      n.times do |i|
        self.fork_worker(i)
      end
    end

    # Fork a single worker
    def fork_worker(id)
      pid = fork do
        # Set process name
        $0="#{config.name}[#{id}]"

        # Ending workers on INT is not useful or desirable
        Signal.trap('INT', proc {})
        Signal.trap('HUP', proc {})
        # Restore normal behaviour
        Signal.trap('TERM', proc {Process.exit(0)})

        # Execure before_fork code
        if config.after_fork.is_a?(Proc)
          self.config.after_fork.call
        end

        if self.config.script.is_a?(String)
          require self.config.script
        elsif self.config.script.is_a?(Proc)
          self.config.script.call
        end
      end

      # Print some debug info and save the pid
      logger.info "Spawned #{config.name}[#{id}] (with PID #{pid})"
      STDOUT.flush

      # Detach to eliminate Zombie processes later
      Process.detach(pid)

      # Save the worker PID into the Parent's child process list
      self.child_processes[id]                    ||= {}
      self.child_processes[id][:pid]              ||= pid
      self.child_processes[id][:respawns]         ||= 0
      self.child_processes[id][:started_at]         = Time.now
    end

    # Kill a given child process
    def kill_child_process(id)
      if opts = self.child_processes[id]
        logger.info "Killing #{config.name}[#{id}] (with PID #{opts[:pid]})"
        STDOUT.flush
        begin
          Process.kill('TERM', opts[:pid])
        rescue
          logger.info "Process already gone away"
        end
      end
    end

    # Kill all child processes
    def kill_child_processes
      logger.info 'Killing child processes...'
      STDOUT.flush
      self.child_processes.keys.each { |id| kill_child_process(id) }
      self.child_processes = Hash.new
    end

    # This is the master process, it spawns some workers then loops
    def master_process
      # Log the master PID
      logger.info "New master process: #{Process.pid}"
      STDOUT.flush

      # Set the process name
      $0="#{self.config.name}[Master]"

      # Fork a Parent process
      # This will load the before_fork in a clean process then fork the script as required
      self.start_parent

      # A restart is not required yet...
      restart_needed = false

      # If we get a USR1, set this process as waiting for a restart
      Signal.trap("USR1", proc {
        logger.info "Master got a USR1."
        restart_needed = true
      })

      # If we get a TERM, send the existing workers a TERM before bowing out
      Signal.trap("TERM", proc {
        logger.info "Master got a TERM."
        STDOUT.flush
        kill_child_processes
        Process.exit(0)
      })

      # INT is useful for when we don't want to background
      Signal.trap("INT", proc {
        logger.info "Master got an INT."
        STDOUT.flush
        kill_child_processes
        Process.exit(0)
      })

      Signal.trap('HUP', proc {})

      # Main loop, we mostly idle, but check if the parent we created has died and exit
      loop do
        sleep 2
        if restart_needed
          STDOUT.flush
          self.kill_child_processes
          load_config
          self.start_parent
          restart_needed = false
        end

        self.child_processes.each do |id, opts|
          begin
            Process.getpgid(opts[:pid])
          rescue Errno::ESRCH
            logger.info "Parent process #{config.name}[#{id}] has died (from PID #{opts[:pid]}), exiting master"
            Process.exit(0)
          end
        end
      end
    end

    # Load or reload the config file defined at startup
    def load_config
      @config = nil
      if File.exist?(self.config_file.to_s)
        load self.config_file
      else
        raise Error, "Configuration file not found at '#{config_file}'"
      end
    end

    def start(config_file, options = {})
      options[:background]  ||= false
      options[:environment] ||= "development"
      $rbg_env = options[:environment].dup

      # Define the config file then load it
      self.config_file = config_file
      self.load_config

      # If the PID file is set and exists, check that the process is not running
      if self.config.pid_path and File.exists?(self.config.pid_path)
        oldpid = File.read(self.config.pid_path)
        begin
          Process.getpgid( oldpid.to_i )
          raise Error, "Process already running! PID #{oldpid}"
        rescue Errno::ESRCH
          # No running process
          false
        end
      end

      # Initialize child process array
      self.child_processes = Hash.new

      if options[:background]
        # Fork the master control process and return to a shell
        master_pid = fork do
          # Ignore input and log to a file
          STDIN.reopen('/dev/null')
          if self.config.log_path
            STDOUT.reopen(self.config.log_path, 'a')
            STDOUT.sync = true
            STDERR.reopen(self.config.log_path, 'a')
            STDERR.sync = true
          else
            raise Error, "Log location not specified in '#{config_file}'"
          end

          self.master_process
        end

        # Ensure the process is properly backgrounded
        Process.detach(master_pid)
        if self.config.pid_path
          File.open(self.config.pid_path, 'w') {|f| f.write(master_pid) }
        end

        logger.info "Master started as PID #{master_pid}"
      else
        # Run using existing STDIN / STDOUT and set logger to use use STDOUT regardless
        self.config.logger = MonoLogger.new(STDOUT)
        self.master_process
      end
    end

    # Get the PID from the pidfile defined in the config
    def pid_from_file
      raise Error, "PID not defined in '#{config_file}'" unless self.config.pid_path
      begin
        File.read(self.config.pid_path).strip.to_i
      rescue
        raise Error, "PID file not found"
      end
    end

    # Stop the running instance
    def stop(config_file, options = {})
      options[:environment] ||= "development"
      $rbg_env = options[:environment].dup

      # Define the config file then load it
      self.config_file = config_file
      self.load_config

      pid = self.pid_from_file

      begin
        Process.kill('TERM', pid)
        say "Sent TERM to PID #{pid}"
      rescue
        raise Error, "Process #{pid} not found"
      end
    end

    # Reload the running instance
    def reload(config_file, options = {})
      options[:environment] ||= "development"
      $rbg_env = options[:environment].dup

      # Define the config file then load it
      self.config_file = config_file
      self.load_config

      pid = self.pid_from_file

      begin
        Process.kill('USR1', pid)
        say "Sent USR1 to PID #{pid}"
      rescue
        raise Error, "Process #{pid} not found"
      end
    end

    def say(msg)
      msg = "      #{msg}" if ENV['PROCMAN_ENABLED']
      puts msg
    end

  end
end

