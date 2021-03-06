require 'mauve/source_list'
require 'mauve/people_list'
require 'mauve/mauve_time'

module Mauve

  # Configuration object for Mauve.  This is used as the context in
  # Mauve::ConfigurationBuilder.
  #
  class Configuration

    class << self
      # The current configuration
      # @param  [Mauve::Configuration]
      # @return [Mauve::Configuration]
      attr_accessor :current
    end

    # The Server instance
    # @return [Mauve::Server]
    attr_accessor :server

    # Notification methods
    # @return [Hash]
    attr_reader   :notification_methods

    # People
    # @return [Hash]
    attr_reader   :people

    # Alert groups
    # @return [Array]
    attr_reader   :alert_groups

    # The source lists
    # @return [Hash]
    attr_reader   :source_lists

    # Various further configuration items
    #
    attr_reader   :bytemark_auth_url, :bytemark_calendar_url, :remote_http_timeout, :remote_https_verify_mode, :failed_login_delay
    attr_reader   :max_acknowledgement_time, :working_hours, :dead_zone, :daytime_hours
    attr_reader   :minimal_dns_lookups


    #
    # Set up a base config.
    #
    def initialize
      @server = nil
      @notification_methods = {}
      @people = {}
      @source_lists = Hash.new{|h,k| h[k] = Mauve::SourceList.new(k)}
      @alert_groups = []

      #
      # Set the auth/calendar URLs
      #
      @bytemark_auth_url     = nil
      @bytemark_calendar_url = nil

      #
      # Set a couple of params for remote HTTP requests.
      #
      self.remote_http_timeout = 5
      self.remote_https_verify_mode = "peer"

      #
      # Rate limit login attempts to limit the success of brute-forcing.
      #
      self.failed_login_delay = 1

      #
      # Reduce the amount of DNS lookups when matching alerts to groups.
      #
      self.minimal_dns_lookups = false

      #
      # Maximum amount of time to acknowledge for
      #
      self.max_acknowledgement_time = 15.days

      #
      # Working hours
      #
      self.dead_zone     = 3.0...7.0
      self.daytime_hours = 8.0...22.0
      self.working_hours = 9.5...17.5
    end

    # Set the calendar URL.
    #
    # @param [String] arg
    # @return [URI]
    def bytemark_calendar_url=(arg)
      raise ArgumentError, "bytemark_calendar_url must be a string" unless arg.is_a?(String)

      @bytemark_calendar_url = URI.parse(arg)

      #
      # Make sure we get an HTTP URL.
      #
      raise ArgumentError, "bytemark_calendar_url must be an HTTP(S) URL." unless %w(http https).include?(@bytemark_calendar_url.scheme)

      #
      # Set a default request path, if none was given
      #
      @bytemark_calendar_url.normalize!

      @bytemark_calendar_url
    end

    # Set the Bytemark Authentication URL
    #
    # @param [String] arg
    # @return [URI]
    def bytemark_auth_url=(arg)
      raise ArgumentError, "bytemark_auth_url must be a string" unless arg.is_a?(String)

      @bytemark_auth_url = URI.parse(arg)
      #
      # Make sure we get an HTTP URL.
      #
      raise ArgumentError, "bytemark_auth_url must be an HTTP(S) URL." unless %w(http https).include?(@bytemark_auth_url.scheme)

      #
      # Set a default request path, if none was given
      #
      @bytemark_auth_url.normalize!

      @bytemark_auth_url
    end

    # Sets the timeout when making remote HTTP requests
    #
    # @param [Integer] arg
    # @return [Integer]
    def remote_http_timeout=(arg)
      raise ArgumentError, "remote_http_timeout must be an integer" unless arg.is_a?(Integer)
      @remote_http_timeout = arg
    end

    # Sets the SSL verification mode when makeing remote HTTPS requests
    #
    # @param [String] arg must be one of "none" or "peer"
    # @return [Constant]
    def remote_https_verify_mode=(arg)
      @remote_https_verify_mode = case arg
      when "peer"
        OpenSSL::SSL::VERIFY_PEER
      when "none"
        OpenSSL::SSL::VERIFY_NONE
      else
        raise ArgumentError, "remote_https_verify_mode must be either 'peer' or 'none'"
      end
    end

    # Set the delay added following a failed login attempt.
    #
    # @param [Numeric] arg Number of seconds to delay following a failed login attempt
    # @return [Numeric]
    #
    def failed_login_delay=(arg)
      raise ArgumentError, "failed_login_delay must be numeric" unless arg.is_a?(Numeric)
      @failed_login_delay = arg
    end

    # Set the maximum amount of time alerts can be ack'd for
    #
    #
    def max_acknowledgement_time=(arg)
      raise ArgumentError, "max_acknowledgement_time must be numeric" unless arg.is_a?(Numeric)
      @max_acknowledgement_time = arg
    end

    def calendar=(x)
      lambda{|at| CalendarInterface.get_attendees(x,at)}
    end

    def working_hours=(arg)
      @working_hours = self.class.parse_range(arg)
    end

    def daytime_hours=(arg)
      @daytime_hours = self.class.parse_range(arg)
    end

    def dead_zone=(arg)
      @dead_zone = self.class.parse_range(arg)
    end

    # This method takes a range, and wraps it within the specs defined by
    # allowed_range.
    # 
    # It can take an array of Numerics, Strings, Ranges etc
    #
    # @param 
    #
    def self.parse_range(arg, allowed_range = (0...24))
      args = [arg].flatten

      #
      # Tidy up our allowed ranges
      #
      min = allowed_range.first
      max = allowed_range.last

      #
      # If we've been given a numeric range, make sure they're all floats.
      #
      min = min.to_f if min.is_a?(Numeric)
      max = max.to_f if max.is_a?(Numeric)
      
      ranges = []

      args.each do |arg|
        case arg
          when Range
            from = arg.first
            to = arg.last
            exclude_end = arg.exclude_end?
          else
            from = arg
            to = arg
        end

        from = min unless allowed_range.include?(from)

        #
        # In the case of integers, we want to match up until, but not including
        # the next integer.
        #
        if to.is_a?(Integer)
          to = (exclude_end ? to : to.succ)
          exclude_end = true
        end

        to = max unless allowed_range.include?(to)

        from = from.to_f if from.is_a?(Numeric)
        to   = to.to_f   if to.is_a?(Numeric)

        if from > to or (from >= to and exclude_end)
          ranges << Range.new(from, max, allowed_range.exclude_end?)
          ranges << Range.new(min, to, exclude_end)
        else
          ranges << Range.new(from, to, exclude_end)
        end

      end

      ranges
    end


    def minimal_dns_lookups=(bool)
      if bool.is_a?(TrueClass) or bool.to_s.strip =~ /^(1|y(es)?|t(rue))/
        @minimal_dns_lookups = true
      else
        @minimal_dns_lookups = false
      end
    end

  end


end
