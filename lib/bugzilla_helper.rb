require 'bugzilla'
require 'base64'

class BugzillaHelper
  # Bugzilla Config
  attr_accessor :username, :password, :products

  attr_accessor :bz

  def initialize(opts)
    opts.each do |k,v|
      send("#{k}=",v)
    end

    xmlrpc = Bugzilla::XMLRPC.new("bugzilla.redhat.com")
    user = Bugzilla::User.new(xmlrpc)

    user.login({'login'=>username, 'password'=>Base64.decode64(password), 'remember'=>true})
    @bz = Bugzilla::Bug.new(xmlrpc)
  end

  def bug_status_by_url(url)
    status = 'NOTFOUND'
    if url =~ /https?:\/\/bugzilla\.redhat\.com\/show_bug\.cgi\?id=(\d+)/
      id = $1
      tries = 1
      while true
        begin
          result = bz.get_bugs([id], ::Bugzilla::Bug::FIELDS_DETAILS)
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

  def rfes
    severity_rank = {
      'urgent' => 0,
      'high' => 1,
      'medium' => 2,
      'low' => 3,
      'unspecified' => 4
    }

    rfes = {}
    ['ASSIGNED', 'NEW', 'MODIFIED', 'POST'].each do |status|
      searchopts = {}
      searchopts[:status] = status
      products.each do |product|
        searchopts[:product] = product
        searchopts[:component] = 'RFE'
        bz.search(searchopts)['bugs'].each do |b|
          #next if b['priority'] == 'low'
          rfes[b['id']] = b
        end
      end
    end
    rfes
  end

end
