# encoding: UTF-8
require 'timeout'
require 'log4r'

module Mauve
  class Person < Struct.new(:username, :password, :holiday_url, :urgent, :normal, :low, :email, :xmpp, :sms)
  
    attr_reader :notification_thresholds, :last_pop3_login
  
    def initialize(*args)
      @notification_thresholds = nil
      @suppressed = false
      #
      # TODO fix up web login so pop3 can be used as a proxy.
      #
      @last_pop3_login = {:from => nil, :at => nil}
      super(*args)
    end
   
    def logger ; @logger ||= Log4r::Logger.new self.class.to_s ; end
 
    def suppressed?
      @suppressed
    end
   
    def notification_thresholds
      #
      # By default send 10 thresholds in a minute maximum
      #
      @notification_thresholds ||= { } 
    end
 
    # This class implements an instance_eval context to execute the blocks
    # for running a notification block for each person.
    # 
    class NotificationCaller

      def initialize(person, alert, other_alerts, base_conditions={})
        @person = person
        @alert = alert
        @other_alerts = other_alerts
        @base_conditions = base_conditions
      end
      
      def logger ; @logger ||= Log4r::Logger.new self.class.to_s ; end

      #
      # This method makes sure things like
      #
      #   xmpp
      #
      #  works
      #
      def method_missing(name, *args)
        #
        # Work out the destination
        #
        if args.first.is_a?(String)
          destination = args.pop
        else 
          destination = @person.__send__(name)
        end

        if args.first.is_a?(Array)
          conditions  = @base_conditions.merge(args[0])
        else
          conditions  = @base_conditions
        end

        notification_method = Configuration.current.notification_methods[name.to_s]

        raise NoMethodError.new("#{name} not defined as a notification method") unless notification_method

        # Methods are expected to return true or false so the user can chain
        # them together with || as fallbacks.  So we have to catch exceptions
        # and turn them into false.
        #
        res = notification_method.send_alert(destination, @alert, @other_alerts, conditions)

        #
        # Log the result
        note =  "#{@alert.update_type.capitalize} #{name} notification to #{@person.username} (#{destination}) " +  (res ? "succeeded" : "failed" )
        logger.info note+" about #{@alert}."
        h = History.new(:alerts => [@alert], :type => "notification", :event => note)
        logger.error "Unable to save history due to #{h.errors.inspect}" if !h.save

        return res
      end

    end 

    #
    #
    # Sends the alert
    #
    def send_alert(level, alert)
      now = Time.now

      was_suppressed = self.suppressed?

      @suppressed = self.notification_thresholds.any? do |period, previous_alert_times|
          #
          # Choose the second one as the first.
          #
          first = previous_alert_times[1]
          last  = previous_alert_times[-1]

          first.is_a?(Time) and (
           (now - first) < period or
           (was_suppressed and (now - last) < period)
          )
      end

        
      logger.info "Starting to send notifications again for #{username}." if was_suppressed and not self.suppressed?
      
      #
      # We only suppress notifications if we were suppressed before we started,
      # and are still suppressed.
      #
      if was_suppressed and self.suppressed?
        note =  "#{alert.update_type.capitalize} notification to #{self.username} suppressed"
        logger.info note + " about #{alert}."
        History.create(:alerts => [alert], :type => "notification", :event => note)
        return true 
      end

    
      # FIXME current_alerts is very slow.  So much so it slows everything
      # down.  A lot.  
      result = NotificationCaller.new(
        self,
        alert,
        [],
        # current_alerts,
        {:is_suppressed  => @suppressed,
         :was_suppressed => was_suppressed, }
      ).instance_eval(&__send__(level))

      if result
        # 
        # Remember that we've sent an alert
        #
        self.notification_thresholds.each do |period, previous_alert_times|
          #
          # Hmm.. not sure how to make this thread-safe.
          #
          self.notification_thresholds[period].push Time.now
          self.notification_thresholds[period].shift
        end

        return true
      end

      return false
    end
    
    # 
    # Returns the subset of current alerts that are relevant to this Person.
    #
    # This is currently very CPU intensive, and slows things down a lot.  So
    # I've commented it out when sending notifications.
    #
    def current_alerts
      Alert.all_raised.select do |alert|
        my_last_update = AlertChanged.first(:person => username, :alert_id => alert.id)
        my_last_update && my_last_update.update_type != "cleared"
      end
    end
    
    protected
    # Whether the person is on holiday or not.
    #
    # @return [Boolean] True if person on holiday, false otherwise.
    def is_on_holiday? ()
      return false if true == holiday_url.nil? or '' == holiday_url
      return CalendarInterface.is_user_on_holiday?(holiday_url, username)
    end

  end

end
