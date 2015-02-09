require 'mono_logger'

module Rbg
  class Config

    attr_accessor :name
    attr_accessor :root
    attr_accessor :script
    attr_accessor :log_path
    attr_accessor :pid_path
    attr_accessor :workers
    attr_accessor :respawn
    attr_accessor :respawn_limits
    attr_accessor :memory_limit
    attr_accessor :logger

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

    def respawn
      @respawn || false
    end

    def respawn_limits
      @respawn_limits || [5, 30]
    end

    def memory_limit
      @memory_limit || nil
    end

    def before_fork(&block)
      block_given? ? @before_fork = block : @before_fork
    end

    def after_fork(&block)
      block_given? ? @after_fork = block : @after_fork
    end

    def logger
      @logger ||= MonoLogger.new(self.log_path)
    end

  end
end
