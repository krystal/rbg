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
    
    # Creates a 'parent' process. This is responsible for executing 'before_fork'
    # and then forking the worker processes.
    def start_parent
      # Record the PID of this parent in the Master
      self.child_processes << fork do
        # Clear the child process list as this fork doesn't have any children yet
        self.child_processes = Array.new

        # Set the process name (Parent)
        $0="#{self.config.name}[P]"

        # Debug information
        puts "New parent process: #{Process.pid}"
        STDOUT.flush
        
        # Run the before_fork function
        self.config.before_fork.call
        
        # Fork an appropriate number of workers
        self.fork_workers(self.config.workers)
        
        # If we get a TERM, send the existing workers a TERM then exit
        Signal.trap("TERM", proc {
          # Debug output
          puts "Parent got a TERM."
          STDOUT.flush

          # Send TERM to workers
          kill_child_processes
          
          # Exit the parent
          Process.exit(0)
        })
        
        # Ending parent processes on INT is not useful or desirable
        # especially when running in the foreground
        Signal.trap('INT', proc {})
        
        # Parent loop, the purpose of this is simply to do nothing until we get a signal
        # We may add memory management code here in the future
        loop do
          sleep 1
        end
        
      end
    end
    
    # Wrapper to fork multiple workers
    def fork_workers(n)
      n.times do |i|
        self.fork_worker(i)
      end
    end
    
    # Fork a single worker
    def fork_worker(i)
      pid = fork do
        # Set process name
        $0="#{self.config.name}[#{i}]"
        
        # Ending workers on INT is not useful or desirable
        Signal.trap('INT', proc {})
        # Restore normal behaviour
        Signal.trap('TERM', proc {Process.exit(0)})
        
        # Execure before_fork code
        self.config.after_fork.call
        
        # The actual code to run
        require self.config.script
      end
      
      # Print some debug info and save the pid
      puts "Spawned: #{self.config.name}[#{i}] as PID #{pid}"
      STDOUT.flush
      
      # Detach to eliminate Zombie processes later
      Process.detach(pid)
      
      # Save the worker PID into the Parent's child process list
      self.child_processes << pid
    end
    
    # Kill all children
    def kill_child_processes
      puts 'Killing child processes...'
      STDOUT.flush
      self.child_processes.each do |p|
        puts "Killing: #{p}"
        STDOUT.flush
        begin
          Process.kill('TERM', p)
        rescue
          puts "Process already gone away"
        end
      end
      # Clear the child process list because we just killed them all
      self.child_processes = Array.new
    end
    
    # This is the master process, it spawns some workers then loops
    def master_process
      # Log the master PID
      puts "New master process: #{Process.pid}"
      STDOUT.flush
      
      # Set the process name
      $0="#{self.config.name}[M]"
      
      # Fork some child processes
      self.start_parent
      
      # If we get a USR1, send the existing workers a TERM before starting some new ones
      Signal.trap("USR1", proc {
        puts "Master got a USR1."
        STDOUT.flush
        self.kill_child_processes
        load_config
        self.start_parent
      })
      
      # If we get a TERM, send the existing workers a TERM before bowing out
      Signal.trap("TERM", proc {
        puts "Master got a TERM."
        STDOUT.flush
        kill_child_processes
        Process.exit(0)
      })
      
      # INT is useful for when we don't want to background
      Signal.trap("INT", proc {
        puts "Master got an INT."
        STDOUT.flush
        kill_child_processes
        Process.exit(0)
      })
      
      # Main loop, the purpose of this is simply to do nothing until we get a signal
      loop do
        sleep 1
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
      
      # Define the config file then load it
      self.config_file = config_file
      self.load_config
      
      self.child_processes = Array.new
      self.command = $0.to_a + ARGV
      
      if options[:background]
        # Ignore input and log to a file
        STDIN.reopen('/dev/null')
        if self.config.log_path
          STDOUT.reopen(self.config.log_path, 'a')
        else
          raise Error, "Log location not specified in '#{config_file}'"
        end
        # Fork the master control process and return to a shell
        master_pid = fork do
          self.master_process
        end
        # Ensure the process is properly backgrounded
        Process.detach(master_pid)
        if self.config.pid_path
          File.open(self.config.pid_path, 'w') {|f| f.write(master_pid) }
        end
      else
        # Run using existing STDIN / STDOUT
        # This might be a user terminal, or an already re-opened STDOUT
        self.master_process
      end
    end
    
  end
end

