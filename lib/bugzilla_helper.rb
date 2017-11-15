require 'bugzilla'
require 'base64'

class BugzillaHelper
  DEFAULT_RETRIES = 5
  DEFAULT_RETRY_SLEEP = 2
  DEFAULT_RETRY_INC = 1

  # Bugzilla Config
  attr_accessor :username, :password, :products

  attr_accessor :bz

  def initialize(opts)
    opts.each do |k, v|
      send("#{k}=", v)
    end

    xmlrpc = Bugzilla::XMLRPC.new("bugzilla.redhat.com")
    user = Bugzilla::User.new(xmlrpc)

    user.login('login' => username, 'password' => Base64.decode64(password), 'remember' => true)
    @bz = Bugzilla::Bug.new(xmlrpc)
    @bug_status_by_url = {}
  end

  def retry_sleep(retry_count)
    sleep DEFAULT_RETRY_SLEEP + (DEFAULT_RETRY_INC * retry_count)
  end

  def retry_on_exception(retries = DEFAULT_RETRIES)
    i = 0
    while true
      begin
        yield
        break
      rescue => e
        $stderr.puts "#Exception {e.class} with bugzilla search: #{e.message}"
        raise if i >= retries
        retry_sleep i
        i += 1
      end
    end
  end

  def bug_status_by_url(url)
    @bug_status_by_url[url] ||= begin
      status = 'NOTFOUND'
      if url =~ /https?:\/\/bugzilla\.redhat\.com\/show_bug\.cgi\?id=(\d+)/
        id = $1
        tries = 1
        result = nil
        retry_on_exception do
          result = bz.get_bugs([id], ::Bugzilla::Bug::FIELDS_DETAILS)
          if !result.empty?
            status = result.first['status']
          end
        end
      end
      status
    end
  end

  def rfes
    if !@rfes
      @rfes = {}
      #['ASSIGNED', 'NEW', 'MODIFIED', 'POST'].each do |status|
      searchopts = {}
      searchopts[:status] = ['ASSIGNED', 'NEW', 'MODIFIED', 'POST']
      searchopts[:product] = products
      searchopts[:component] = 'RFE'
      bugs = nil
      retry_on_exception do
        bugs = bz.search(searchopts)["bugs"]
      end
      bugs.each do |b|
        #next if b['priority'] == 'low'
        @rfes[b['id']] = b
      end
    end
    @rfes
  end
end
