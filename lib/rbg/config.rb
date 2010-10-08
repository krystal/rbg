module Rbg
  class Config
    
    ## The name of the application as used in the proclist
    attr_accessor :name
    
    ## The ruby script which should be backgrounded
    attr_accessor :script
    
    ## Path to the log file for the master process
    attr_accessor :log_path
    
    ## Path to the PID file for the master process
    attr_accessor :pid_path
    
    ## Number of workers to start
    attr_accessor :workers
    
    ## Block of code to be executed in the master process before the process
    ## has been forked.
    def before_fork(&block)
      if block_given?
        @before_fork = block
      else
        @before_fork
      end
    end
    
    ## Block of code to be executed in the child process after forking has
    ## taken place.
    def after_fork(&block)
      if block_given?
        @after_fork = block
      else
        @after_fork
      end
    end
    
  end
end
