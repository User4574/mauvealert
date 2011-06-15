# encoding: UTF-8
require 'mauve/datamapper'
require 'log4r'

module Mauve
  class AlertChanged
    include DataMapper::Resource
    
    # so .first always returns the most recent update
    default_scope(:default).update(:order => [:at.desc, :id.desc])
    
    property :id, Serial
    property :alert_id, Integer, :required  => true
    property :person, String, :required  => true
    property :at, DateTime, :required  => true
    property :was_relevant, Boolean, :required => true, :default => true
    property :level, String, :required  => true
    property :update_type, String, :required  => true
    property :remind_at, DateTime
    property :updated_at, DateTime

    
    def to_s
      "#<AlertChanged:#{id} of #{alert_id} for #{person} update_type #{update_type}>"
    end
    
    belongs_to :alert
    
    # There is a bug there.  You could have two reminders for the same 
    # person if that person has two different notify clauses.  
    #
    # See the test cases test_Bug_reminders_get_trashed() in ./test/
    after :create do
      old_changed = AlertChanged.first(
        :alert_id => alert_id,
        :person => person,
        :id.not => id,
        :remind_at.not => nil
      )
      if old_changed
        if !old_changed.update(:remind_at => nil)
          logger.error "Couldn't save #{old_changed}, will get duplicate reminders"
        end
      end
    end
    
    def was_relevant=(value)
      attribute_set(:was_relevant, value)
    end

    def logger
     Log4r::Logger.new self.class.to_s
    end

    ## Checks to see if a raise was send to the person.
    #
    # @TODO: Recurence is broken in ruby, change this so that it does not 
    #        use it.
    #
    # @author Matthew Bloch
    # @return [Boolean] true if it was relevant, false otherwise.
    def was_relevant_when_raised?
      if :acknowledged == update_type.to_sym and true == was_relevant
        return true 
      end
      return was_relevant if update_type.to_sym == :raised
      previous = AlertChanged.first(:id.lt => id, 
                                    :alert_id => alert_id,
                                    :person => person)
      if previous
        previous.was_relevant_when_raised?
      else
        # a bug, but hardly inconceivable :)
        logger.warn("Could not see that #{alert} was raised with #{person} "+
                     "but further updates exist (e.g. #{self}) "+
                     "- you may see spurious notifications as a result")
        true
      end
    end
    
    # Sends a reminder about this alert state change, or forget about it if
    # the alert has been acknowledged
    #
    def remind
      logger.debug "Reminding someone about #{self.inspect}"
      
      alert_group = AlertGroup.matches(alert)[0]
      
      if !alert_group || alert.acknowledged?
        logger.debug((alert_group ? 
          "Alert already acknowledged" : 
          "No alert group matches any more"
          ) + ", no reminder due"
        )
        self.remind_at = nil
        save
      else
        saved = false

        unless alert_group.notifications.nil?

          alert_group.notifications.each do |notification|
            notification.people.each do |person|
              # Not interested in nil people.
              next if person.nil?
  
              if person.username == self.person
                person.remind(alert, level)
                self.remind_at = notification.remind_at_next(alert)
                save
                saved = true
              end
            end
          end
        end
        
        if !saved
          logger.warn("#{self.inspect} did not match any people, maybe configuration has changed but I'm going to delete this and not try to remind anyone again")
          destroy!
        end
      end
    end
    
    def due_at # mimic interface from Alert
      remind_at ? remind_at.to_time : nil
    end
    
    def poll # mimic interface from Alert
      remind if remind_at.to_time <= MauveTime.now
    end
    
    class << self
      def next_reminder
        first(:remind_at.not => nil, :order => [:remind_at])
      end
      
      def find_next_with_event # mimic interface from Alert
        next_reminder
      end

      def all_overdue(at = MauveTime.now)
        all(:remind_at.not => nil, :remind_at.lt => at, :order => [:remind_at]).to_a
      end
    end
  end
end
