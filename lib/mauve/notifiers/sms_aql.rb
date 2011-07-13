require 'mauve/notifiers/debug'
require 'cgi'

module Mauve
  module Notifiers
    module Sms
      
      require 'net/https'
      class AQL
        GATEWAY = "https://gw1.aql.com/sms/sms_gw.php"

        attr :username, true
        attr :password, true
        attr :from, true
        attr :max_messages_per_alert, true
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def send_alert(destination, alert, all_alerts, conditions = nil)
          uri = URI.parse(GATEWAY)
                  
          opts_string = {
            :username => @username,
            :password => @password,
            :destination => normalize_number(destination),
            :message => prepare_message(destination, alert, all_alerts, conditions),
            :originator => @from,
            :flash => @flash ? 1 : 0
          }.map { |k,v| "#{k}=#{CGI::escape(v.to_s)}" }.join("&")
          
          http = Net::HTTP.new(uri.host, uri.port)
          if uri.port == 443
            http.use_ssl = true
            http.verify_mode = OpenSSL::SSL::VERIFY_NONE
          end
          response, data = http.post(uri.path, opts_string, {
            'Content-Type' => 'application/x-www-form-urlencoded',
            'Content-Length' => opts_string.length.to_s
          })
          
          if response.kind_of?(Net::HTTPSuccess)
            #
            # Woo -- return true!
            #
            true
          else
            false
          end
        end
        
        protected
        def prepare_message(destination, alert, all_alerts, conditions=nil)
          if conditions
            @suppressed_changed = conditions[:suppressed_changed]
          end
          
          txt = case @suppressed_changed
            when true then "TOO MUCH NOISE!  Last notification: "
            when false then "BACK TO NORMAL: "
            else 
              ""
          end
          
          template_file = File.join(File.dirname(__FILE__),"templates","sms.txt.erb")

          txt += if File.exists?(template_file)
            ERB.new(File.read(template_file)).result(binding).chomp
          else
            logger.error("Could not find sms.txt.erb template")
            alert.to_s
          end

          others = all_alerts-[alert]
          if !others.empty?
            txt += (1 == others.length)? 
              "and a lone other." : 
              "and #{others.length} others."
            #txt += "and #{others.length} others: "
            #txt += others.map { |alert| alert.summary_one_line }.join(", ")
          end

          txt += "link: https://alert.bytemark.co.uk/alerts"

          ## @TODO:  Add a link to acknowledge the alert in the text?
          #txt += "Acknoweledge alert: "+
          #       "https://alert.bytemark.co.uk/alert/acknowledge/"+
          #       "#{alert.id}/#{alert.get_default_acknowledge_time}

          txt
        end
        
        def normalize_number(n)
          n.split("").select { |s| (?0..?9).include?(s[0]) }.join.gsub(/^0/, "44")
        end
        include Debug
      end
    end
  end
end

