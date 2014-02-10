module Rbg
  class Config
    
    attr_accessor :name
    attr_accessor :root
    attr_accessor :script
    attr_accessor :log_path
    attr_accessor :pid_path
    attr_accessor :workers
    
    def root
      @root || File.expand_path('./')
    end
    
    def log_path
      @log_path || File.join(root, 'log', "#{name}.log")
    end

    def pid_path
      @pid_path || File.join(root, 'log', "#{name}.pid")
    end
    
    def script(&block)
      block_given? ? @script = block : @script
    end
    
    def before_fork(&block)
      block_given? ? @before_fork = block : @before_fork
    end
    
    def after_fork(&block)
      block_given? ? @after_fork = block : @after_fork
    end
    
  end
end
