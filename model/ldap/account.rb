require "nrs_ldap"
require "./helper/fsr"
require_relative '../manager'

module TinyCallCenter
  class Account
    attr_reader :user, :uid

    include Innate::Helper::Fsr

    def self.authenticate(creds)
      name, pass = creds.values_at("name", "pass")
      Account.new(name) if name && pass && NrsLdap.authenticate(name, pass)
    rescue => error
      TCC::Log.error(error)
      false
    end

    def registration_server
      self.class.registration_server(extension)
    end

    def self.registration_server(extension)
      case extension
      when /^2[458]00$/
        "192.168.6.240" #moses
      when /^2[458]\d\d$/
        "192.168.6.249" #pip
      when /^10\d\d$/
        "192.168.134.15" #tyler
      else
        "192.168.6.240" #moses
      end
    end

    def self.from_extension(ext)
      ldap_user = NrsLdap.find_user_by_extension(ext)
      return(new(ldap_user.first["uid"].first)) if ldap_user.size == 1
      false
    end

    # only handle extension, which is our equivalent to the sequel id
    # this is used by the ribbon until we find time to get rid of backbone.
    # FIXME: deprecated
    def self.[](criteria)
      id = criteria.fetch(:id)
      self.from_extension(id)
    end

    def self.username(agent)
      s = agent_name(agent)
      s.gsub('_', '') if s
    end

    def self.agent_name(agent)
      agent.split('-',2).last
    end

    def self.extension(agent)
      agent.split('-',2).first
    end

    def self.from_call_center_name(agent)
      new username(agent)
    end

    def self.from_full_name(name)
      new name.gsub("_", '').gsub(/\s/,'') if name
    end

    def self.full_name(agent)
      agent.split('-', 2).last.tr("_", " ") if agent
    end

    def self.all_usernames
      NrsLdap.all_employees.map{|employee| employee['uid'] }.flatten.uniq
    end

    def initialize(user)
      @uid = user
      warn "<<<ERROR>>> No Such User #{user} in #{self.class} #initialize (from #user_raw)" unless @exists = user_raw
    end

    def exists?
      @exists ? true : false
    end

    def user_raw
      @user_raw ||= NrsLdap.find_user(@uid).first
    end

    def to_s
      "TinyCallCenter::Account @uid=%s" % @uid
    end

    def inspect
      "<#%s:%s @uid=\"%s\">" % [self.class, self.object_id, @uid]
    end

    def attributes
      @attr ||= find_user
    end

    def find_user
      return false unless user_raw
      singles = ["nrsAliases"]
      @user ||= Hash[user_raw.map { |k, v|
        if singles.include? k
          [k, v.first]
        else
          [k, v.size > 1 ? v : v.first]
        end
      }]
    end

    def nrs_alias
      attributes["nrsAliases"]
    end

    def full_name
      return nrs_alias.split.map(&:downcase).map(&:capitalize).join(" ") if nrs_alias
      "%s %s" % [first_name, last_name]
    end

    def first_name
      attributes["givenName"].strip
    end

    def last_name
      attributes["sn"].strip
    end

    def extension
      attributes["telephoneNumber"]
    end

    def uid_number
      attributes["uidNumber"]
    end

    def agent
      "%s-%s_%s" % [extension, first_name, last_name]
    end

    # FIXME: deprecated
    def to_json(*args)
      obj = {
        id: extension, first_name: first_name, last_name: last_name,
        extension: extension, registration_server: registration_server
      }
      if args.first.respond_to?(:to_hash)
        obj.to_json
      else
        obj.to_json(*args)
      end
    end

    # FIXME: deprecated
    def update(attributes)
      attributes.each do |key, value|
        case key
        when 'status'
          self.status = value
        when 'state'
          self.state = value
        else
          raise "Unknown attribute: %p => %p" % [key, value]
        end
      end
    end

    def manager
      @_manager ||= (
        TinyCallCenter::Manager.find(username: uid) ||
        TinyCallCenter::Manager.find(username: "#{first_name.downcase.capitalize}#{last_name.downcase.capitalize}")
      )
    end

    def can_view?(extension)
      return false unless manager
      manager.authorized_to_listen?(extension, extension)
    end

    def manager?
      return false unless u = find_user
      return true if manager
      [*u['dn'], *u['groupMembership']].find{|c|
        c =~ %r{manager|executive|technology|fellinger}i
      }
    end

    # FIXME: deprecated
    def status=(new_status)
      Log.debug "set status of #{agent} to #{new_status}"
      FSListener.execute registration_server do |listener|
        listener.callcenter!{|cc| cc.set(agent, :status, new_status) }
      end
    end

    # FIXME: deprecated
    def state=(new_state)
      Log.debug "set state of #{agent} to #{new_state}"
      FSListener.execute registration_server do |listener|
        listener.callcenter!{|cc| cc.set(agent, :state, new_state) }
      end
    end
  end
end
