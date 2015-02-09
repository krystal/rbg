Rbg.config.tap do |config|

  # The name of this task used in the process list
  config.name = "example-job"
  # Path to the main script to execute
  config.script = "example-job.rb"
  # Log path
  config.log_path = "/tmp/example.log"
  # PID save path (optional)
  config.pid_path = "/tmp/example.pid"
  # Number of workers
  config.workers = 4

  # Code to run before forking
  # Usually requiring libraries and configuration
  config.before_fork do
    require 'date'
  end

  # Code to run after forking
  # This will often be: ActiveRecord::Base.establish_connection
  config.after_fork do
    puts "The date is #{Date.today.to_s}"
  end

end

