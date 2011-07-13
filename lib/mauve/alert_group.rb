# encoding: UTF-8
require 'mauve/alert'
require 'log4r'

module Mauve
  class AlertGroup < Struct.new(:name, :includes, :acknowledgement_time, :level, :notifications)

    # 
    # Define some constants, and the ordering.
    #
    URGENT = :urgent
    NORMAL = :normal
    LOW    = :low
    LEVELS = [LOW, NORMAL, URGENT]
    
    class << self

      def matches(alert)
        grps = all.select { |alert_group| alert_group.matches_alert?(alert) }

        #
        # Make sure we always match the last (and therefore default) group.
        #
        grps << all.last unless grps.include?(all.last)

        grps
      end

      # If there is any significant change to a set of alerts, the Alert
      # class sends the list here so that appropriate action can be taken
      # for each one.  We scan the list of alert groups to find out which
      # alerts match which groups, then send a notification to each group
      # object in turn.
      #
      def notify(alerts)
        alerts.each do |alert|
          groups = matches(alert)
          
          # 
          # Make sure we've got a matching group
          #
          if groups.empty?
            logger.warn "no groups found for #{alert}!" 
            next
          end

          #
          # Notify just the first group 
          #
          this_group = groups.first
          logger.info("notifying group #{this_group} of #{alert}")
          this_group.notify(alert)
        end
      end
 
      def logger
        Log4r::Logger.new self.to_s
      end

      def all
        Configuration.current.alert_groups
      end
      
      # Find all alerts that match 
      #
      # @deprecated Buggy method, use Alert.get_all().
      #
      # This method returns all the alerts in all the alert_groups.  Only
      # the first one should be returned thus making this useless. If you want
      # a list of all the alerts matching a level, use Alert.get_all().
      # 
      def all_alerts_by_level(level)
        Configuration.current.alert_groups.map do |alert_group|
          alert_group.level == level ? alert_group.current_alerts : []
        end.flatten.uniq
      end

    end
    
    def initialize(name)
      self.name = name
      self.level = :normal
      self.includes = Proc.new { true }
    end
    
    def to_s
      "#<AlertGroup:#{name} (level #{level})>"
    end
  
    # The list of current raised alerts in this group.
    #
    def current_alerts
      Alert.all(:cleared_at => nil, :raised_at.not => nil).select { |a| matches_alert?(a) }
    end
    
    # Decides whether a given alert belongs in this group according to its
    # includes { } clause
    #
    # @param [Alert] alert An alert to test for belongness to group.
    # @return [Boolean] Success or failure.
    def matches_alert?(alert)

      unless alert.is_a?(Alert)
        logger.error "Got given a #{alert.class} instead of an Alert!"
      	logger.debug caller.join("\n")
        return false
      end

      result = alert.instance_eval(&self.includes)
      if true == result or
         true == result.instance_of?(MatchData)
        return true
      end
      return false
    end

    def logger ; self.class.logger ; end

    # Signals that a given alert (which is assumed to belong in this group)
    # has undergone a significant change.  We resend this to every notify list.
    #    
    def notify(alert)
      #
      # If there are no notifications defined. 
      #
      if  notifications.nil?
        logger.warn("No notifications found for #{self.inspect}")
        return
      end

      #
      # The notifications are specified in the config file.
      #
      notifications.each do |notification|
        notification.alert_changed(alert)
      end
    end

    #
    # This sorts by priority (urgent first), and then alphabetically, so the
    # first match is the most urgent.
    #
    def <=>(other)
      [LEVELS.index(self.level), self.name]  <=> [LEVELS.index(other.level), other.name]
    end

  end

end
