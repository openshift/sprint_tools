require 'ldap'

class LdapHelper

  ATTRS = ['uid', 'mail', 'cn']
  IMPERFECT_MATCH = '(imperfect match)'

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
      if valid_user_names.has_key?(login) || valid_user_names.has_key?(login + IMPERFECT_MATCH) || invalid_user_names.has_key?(login)
        next
      end
      name = member.full_name
      begin
        email = email(name, login, false)
        if email
          valid_user_names[login] = true
        else
          email = email(name, login, false, true)
          if email
            valid_user_names[login + IMPERFECT_MATCH] = true
          else
            invalid_user_names[login] = true
            puts "  #{login}: #{name}"
          end
        end
      rescue Exception => e
        $stderr.puts "  #{login}: #{name} (Exception: #{e.message})"
      end
    end
    return invalid_user_names
  end

  def valid_users(members)
    valid_users = {}
    members.each do |member|
      login = member.username
      name = member.full_name
      begin
        email = email(name, login)
        if email
          valid_users[login] = email
        end
      rescue Exception => e
        puts "    #{login}: #{name} (Exception: #{e.message})"
      end
    end
    return valid_users
  end

  private

  def email(name, login, verbose=true, allow_multiple=false)
    first_name, middle_name, last_name = split_names(name)
    users = nil
    if last_name
      users = ldap_users_by_name(first_name, last_name, true)
      if users.length != 1 && !(allow_multiple && users.length > 1)
        users = ldap_users_by_name(first_name, last_name)
        if (users.length != 1 && middle_name) && !(allow_multiple && users.length > 1)
          users = ldap_users_by_name(middle_name, last_name)
          if users.length != 1 && !(allow_multiple && users.length > 1)
            users = ldap_users_by_name(first_name, "#{middle_name} #{last_name}")
          end
        end
        if users.length != 1 && !(allow_multiple && users.length > 1) 
          users = ldap_users_by_name(first_name[0..2], last_name)
          if users.length != 1 && !(allow_multiple && users.length > 1)
            last_name_users = ldap_users_by_last_name(last_name)
            users = last_name_users if last_name_users.length == 1
          end
        end
      end
    else
      puts "No last name: #{login}: #{name}" if verbose
    end
    email = nil
    if users
      if users.length == 1 || (allow_multiple && users.length > 1)
        email = users.first['mail'].first
      else
        puts "Not found or multiple matches: #{login}: #{name}" if verbose
      end
    end
    return email
  end

  def split_names(name)
    first_name = nil
    last_name = nil
    middle_name = nil
    if name
      ['(', '['].each do |c|
        if name.index(c)
          name = name[0..name.index(c) - 1]
        end
      end
      names = name.strip.split(' ')
      first_name = I18n.transliterate(names.first)
      if first_name.end_with? '.'
        first_name = first_name[0..-2]
      end
      if names.length > 1
        last_name = I18n.transliterate(names.last)
        if names.length > 2
          middle_name = I18n.transliterate(names[1])
        end
      end
    end
    return [first_name, middle_name, last_name]
  end

  def ldap_connect
    ldap = LDAP::Conn.new(host, LDAP::LDAP_PORT.to_i)
    ldap.set_option(LDAP::LDAP_OPT_PROTOCOL_VERSION, 3)
    ldap
  end

end
