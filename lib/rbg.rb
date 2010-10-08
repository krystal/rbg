require 'rbg/config'

module Rbg
  class Error < StandardError; end
  
  class << self
    
    ## An array of worker PIDs which have been spawnred
    attr_accessor :worker_pids
    
    ## The script path which was executed
    attr_accessor :zero
    
    ## Return a configration object for this backgroundable application.
    def config
      @config ||= Rbg::Config.new
    end
    
    def start(config_file, options = {})
      options[:background]  ||= false
      options[:environment] ||= "development"
      
      unless File.exist?(config_file.to_s)
        raise Error, "Configuration file not found at '#{config_file}'"
      end
      
      require config_file
      puts config.inspect
      ## run the code
    end
    
  end
end
