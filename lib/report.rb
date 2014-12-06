require 'kramdown'
require 'ostruct'
require 'mailer'

class Report
  attr_accessor :options

  def initialize(opts)
    self.options = opts
  end

  def reports
    @reports ||= (
    # Map passed in names to global report_types
      options.reports.map do |name|
        $report_types[name]
      end.each do |r|
        # Set the sprint for each report
        r.sprint = $sprint
      end
    )
  end

  def options=(new_opts)
    @options ||= OpenStruct.new()
    old_opts = @options.marshal_dump
    @options.marshal_load(old_opts.merge(new_opts))
  end

  def required_reports
    reports.select{|r| r.required? }
  end

  def offenders
    required_reports.map{|r| r.offenders}.flatten.compact.uniq
  end

  def process(user = nil)
    stats = StatsReport.new

    data = required_reports.map do |r|
      rows = r.rows(user)
      hash = {
        :report => r,
        :data => {
          :title => r.title,
          :headings => r.columns.map{|col| col.header},
          :rows => rows
        }
      }
      stats.data << {:name => hash[:data][:title], :count => rows.count} if rows.count > 0
      hash
    end.compact

    data.delete_if{|d| d[:data][:rows].length == 0}

    unless data.empty? || user
      deadlines = DeadlinesReport.new

      #TODO: This should probably be moved to the sprint itself
      deadlines.data = reports.select{|x| !(x.required? || x.first_day?) }.map{|x| {:date => x.due_date, :title => x.friendly || x.title} }
      deadlines.data << {:date => $sprint.finish, :title => "Last Day of Sprint" }
      deadlines.data = deadlines.data.sort_by{|x| x[:date] }
      data.unshift({
        :report => deadlines,
        :data => {
          :title => deadlines.title,
          :headings => deadlines.columns.map{|col| col.header},
          :rows => deadlines.rows
        }
      })

      environments = EnvironmentsReport.new
      environments.data = []
      environments.data << {:date => $sprint.int,  :title => "First Push to INT" } if $sprint.int
      environments.data << {:date => $sprint.prod,  :title => "Push to PROD" } if $sprint.prod
      environments.data << {:date => $sprint.stg,  :title => "Push to STG" } if $sprint.stg
      data = data.sort_by{|x| x[:date] }
      data.unshift({
        :report => environments,
        :data => {
          :title => environments.title,
          :headings => environments.columns.map{|col| col.header},
          :rows => environments.rows
        }
      })

      stats.data.unshift({
        :name => 'Total Stories',
        :count => $sprint.stories.length
      })

      data.unshift({
        :report => stats,
        :data => {
          :title => stats.title,
          :headings => stats.columns.map{|col| col.header},
          :rows => stats.rows
        }
      })
    end

    data
  end

  def to_kramdown(data, user=nil)
    str = []
    str << "## %s" % user ? "Incomplete User Stories for #{user}" : $sprint.title
    data.each do |t|
      r = t[:report]
      d = t[:data]
      str << ''
      str << "### #{r.print_title}"
      str << ''
      str << "|---"
      str << "| %s" % d[:headings].join(" | ")
      str << "| %s :--|" % (":--:|" * (d[:headings].length-1) )

      d[:rows].each do |row|
        str << "| %s" % row.join(' | ')
      end
      str << "{: border='1px solid black'}"
    end
    Kramdown::Document.new(str.join("\n"))
  end

  def to_ascii(data, user = nil)
    return capture_stdout do
      title = user ? "Incomplete User Stories for #{user}" : $sprint.title
      heading title do
        data.each do |t|
          _table(t[:report].print_title, t[:data][:rows])
        end
      end
    end.string
  end

  def send_email
    data = process

    if data.empty?
      say "No reports to send"
      return
    end

    emails = [make_mail(options.to, $sprint.title(true), data)]

    ascii = to_ascii(data)

    unless options.nag == false
      offenders.each do |user|
        data = process(user)
        emails << make_mail(user, "Incomplete User Story #{$sprint.title(true)}", data)
      end
    end

    if options.send_email
      heading "Sending Emails" do
        emails.each do |email|
          _progress email.mail.to do
            email.deliver!
          end
        end
      end
    end

    puts ascii
  end

  def make_mail(to,subject,data)
    Status::Email.new(
      :to => to,
      :subject => subject,
      :body => to_ascii(data)
      #TODO: Removing the HTML mail for now, it's kinda clunky looking
      #:html_body => to_kramdown(data).to_html
    )
  end
end
