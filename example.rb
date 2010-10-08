Rbg.config.tap do |config|

  config.name = "example-job"
  config.script = "example-job.rb"
  config.log_path = "/tmp/example.log"
  config.pid_path = "/tmp/example.pid"
  config.workers = 4

  config.before_fork do
    $n = 200
  end
  
  config.after_fork do
    puts $n
  end

end
