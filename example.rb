Rbg.config.tap do |config|
  config.name = "key-server"
  config.script = "/blah/blah/blah.rb"
  config.log_path = "/tmp/keyserver.rb"
  config.pid_path = "/tmp/keyserver.pid"
  config.workers = 4

  config.before_fork do
    require 'rails'
  end
  
  config.after_fork do
    ActiveRecord::Base.establish_connection
  end
end
