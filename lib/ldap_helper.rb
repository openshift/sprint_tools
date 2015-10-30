require 'ldap'

class LdapHelper

  ATTRS = ['uid', 'mail', 'cn']

  attr_accessor :host, :base_dn

  def initialize(opts)
    opts.each do |k,v|
      send("#{k}=",v)
    end
  end

  def ldap_user_by_uid(uid)
    user = nil
    ldap = ldap_connect
    ldap.bind do
      ldap.search(base_dn, LDAP::LDAP_SCOPE_SUBTREE, "(uid=#{uid})", ATTRS) do |entry|
        #email = entry.vals('mail')[0]
        user = entry
      end
    end
    user
  end

  def ldap_user_by_email(email)
    user = nil
    ldap = ldap_connect
    ldap.bind do
      ldap.search(base_dn, LDAP::LDAP_SCOPE_SUBTREE, "(mail=#{email})", ATTRS) do |entry|
        user = entry
      end
    end
    user
  end

  def ldap_users_by_name(givenName, sn, perfect_match=false)
    users = []
    ldap = ldap_connect
    ldap.bind do
      ldap.search(base_dn, LDAP::LDAP_SCOPE_SUBTREE, "(|(&(givenName=#{givenName}#{perfect_match ? '' : '*'})(sn=#{sn}))(cn=#{givenName}#{perfect_match ? ' ' : '*'}#{sn}))", ATTRS) do |entry|
        users << entry
      end
    end
    users
  end

  def ldap_users_by_last_name(sn)
    users = []
    ldap = ldap_connect
    ldap.bind do
      ldap.search(base_dn, LDAP::LDAP_SCOPE_SUBTREE, "(sn=#{sn})", ATTRS) do |entry|
        users << entry
      end
    end
    users
  end

  def print_invalid_members(members, valid_user_names, invalid_user_names=nil)
    invalid_user_names = {} unless invalid_user_names
    members.each do |member|
      login = member.username
      if valid_user_names.has_key?(login) || valid_user_names.has_key?(login + '(imperfect match)') || invalid_user_names.has_key?(login)
        next
      end
      name = member.full_name
      begin
        ['(', '['].each do |c|
          if name.index(c)
            name = name[0..name.index(c) - 1]
          end
        end
        names = name.strip.split(' ')
        first_name = I18n.transliterate(names.first)
        last_name = nil
        if first_name.end_with? '.'
          first_name = first_name[0..-2]
        end
        if names.length > 1
          last_name = I18n.transliterate(names.last)
        end
        if last_name && !ldap_users_by_name(first_name, last_name, true).empty?
          valid_user_names[login] = true
          next
        elsif last_name && !ldap_users_by_name(first_name, last_name).empty?
          valid_user_names[login + '(imperfect match)'] = true
          next
        else
          if last_name && names.length > 2
            middle_name = I18n.transliterate(names[1])
            if !ldap_users_by_name(middle_name, last_name).empty?
              valid_user_names[login + '(imperfect match)'] = true
              next
            elsif !ldap_users_by_name(first_name, "#{middle_name} #{last_name}").empty?
              valid_github_user_names[login + '(imperfect match)'] = true
              next
            end
          end
          invalid_user_names[login] = true
          puts "  #{login}: #{name}"
        end
      rescue Exception => e
        $stderr.puts "  #{login}: #{name} (Exception: #{e.message})"
      end
    end
    return invalid_user_names
  end

  private

  def ldap_connect
    ldap = LDAP::Conn.new(host, LDAP::LDAP_PORT.to_i)
    ldap.set_option(LDAP::LDAP_OPT_PROTOCOL_VERSION, 3)
    ldap
  end

end
