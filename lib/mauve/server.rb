# encoding: UTF-8
require 'yaml'
require 'socket'
# require 'mauve/datamapper'
require 'mauve/proto'
require 'mauve/alert'
require 'mauve/mauve_thread'
require 'mauve/mauve_time'
require 'mauve/timer'
require 'mauve/udp_server'
require 'mauve/processor'
require 'mauve/http_server'
require 'log4r'

module Mauve

  class Server 

    DEFAULT_CONFIGURATION = {
      :ip => "127.0.0.1",
      :port => 32741,
      :database => "sqlite3:///./mauvealert.db",
      :log_file => "stdout",
      :log_level => 1,
      :transmission_cache_expire_time => 600
    }


    #
    # This is the order in which the threads should be started.
    #
    THREAD_CLASSES = [UDPServer, HTTPServer, Processor, Notifier, Timer]

    attr_accessor :web_interface
    attr_reader   :stopped_at, :started_at, :initial_sleep

    include Singleton

    def initialize
      # Set the logger up
      @logger = Log4r::Logger.new(self.class.to_s)

      # Sleep time between pooling the @buffer buffer.
      @sleep = 1

      @freeze     = false
      @stop       = false

      @stopped_at = MauveTime.now
      @started_at = MauveTime.now
      @initial_sleep = 300

      @config = DEFAULT_CONFIGURATION
    end

    def configure(config_spec = nil)
      #
      # Update the configuration
      #
      if config_spec.nil?
        # Do nothing
      elsif config_spec.kind_of?(String) and File.exists?(config_spec)
        @config.update(YAML.load_file(config_spec))
      elsif config_spec.kind_of?(Hash)
        @config.update(config_spec)
      else
        raise ArgumentError.new("Unknown configuration spec "+config_spec.inspect)
      end

      #
      DataMapper.setup(:default, @config[:database])
      # DataObjects::Sqlite3.logger = Log4r::Logger.new("Mauve::DataMapper") 

      #
      # Update any tables.
      #
      Alert.auto_upgrade!
      AlertChanged.auto_upgrade!
      Mauve::AlertEarliestDate.create_view!

      #
      # Work out when the server was last stopped
      #
      # topped_at = self.last_heartbeat 
    end
   
    def last_heartbeat
      #
      # Work out when the last update was
      #
      [ Alert.last(:order => :updated_at.asc), 
        AlertChanged.last(:order => :updated_at.asc) ].
        reject{|a| a.nil? or a.updated_at.nil? }.
        collect{|a| a.updated_at.to_time}.
        sort.
        last
    end

    def freeze
      @frozen = true
    end

    def thaw
      @thaw = true
    end

    def stop
      @stop = true

      thread_list = Thread.list 

      thread_list.delete(Thread.current)

      THREAD_CLASSES.reverse.each do |klass|
        thread_list.delete(klass.instance)
        klass.instance.stop unless klass.instance.nil?
      end

      thread_list.each do |t|
        t.exit
      end      

      @logger.info("All threads stopped")
    end

    def run
      loop do
        thread_list = Thread.list 

        thread_list.delete(Thread.current)

        THREAD_CLASSES.each do |klass|
          thread_list.delete(klass.instance)

          next if @frozen or @stop

          unless klass.instance.alive?
            # ugh something has died.
            #
            begin
              klass.instance.join
            rescue StandardError => ex
              @logger.warn "Caught #{ex.to_s} whilst checking #{klass} thread"
              @logger.debug ex.backtrace.join("\n")
            end
            #
            # Start the stuff.
            klass.instance.start unless @stop
          end

        end

        thread_list.each do |t|
          next unless t.alive?
          begin
            t.join
          rescue StandardError => ex
            @logger.fatal "Caught #{ex.to_s} whilst checking threads"
            @logger.debug ex.backtrace.join("\n")
            self.stop
            break
          end
        end

        break if @stop

        sleep 1
      end
      logger.debug("Thread stopped")
    end

    alias start run

  end

end
