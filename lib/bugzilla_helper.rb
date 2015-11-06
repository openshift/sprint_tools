require 'bugzilla'
require 'base64'

class BugzillaHelper
  # Bugzilla Config
  attr_accessor :username, :password, :product

  attr_accessor :bug

  def initialize(opts)
    opts.each do |k,v|
      send("#{k}=",v)
    end

    xmlrpc = Bugzilla::XMLRPC.new("bugzilla.redhat.com")
    user = Bugzilla::User.new(xmlrpc)

    user.login({'login'=>username, 'password'=>Base64.decode64(password), 'remember'=>true})
    @bug = Bugzilla::Bug.new(xmlrpc)
  end

  def bug_status_by_url(url)
    status = 'NOTFOUND'
    if url =~ /https?:\/\/bugzilla\.redhat\.com\/show_bug\.cgi\?id=(\d+)/
      id = $1
      tries = 1
      while true
        begin
          result = bug.get_bugs([id], ::Bugzilla::Bug::FIELDS_DETAILS)
          if !result.empty?
            status = result.first['status']
          end
          break
        rescue
          if tries == 3
            $stderr.puts "Error getting: #{url}"
            raise
          end
          tries += 1
        end
      end
    end
    return status
  end

end
