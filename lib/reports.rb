require 'sprint'

module SprintReport
  attr_accessor :title, :headings, :bug_headings, :function, :columns, :data, :day, :days_before_code_freeze, :sort_key, :secondary_sort_key, :friendly, :type
  attr_accessor :sprint
  def initialize(opts)
    opts.each do |k, v|
      send("#{k}=", v)
    end

    if type == :bug
      @columns = bug_headings.map { |heading| Column.new(heading, self) }
    else
      @columns = headings.map { |heading| Column.new(heading, self) }
    end
    @data = []
  end

  def send_attr(x, attr)
    if attr == 'bug_owner'
      x['assigned_to']
    elsif attr == 'team_name'
      sprint.trello.team_name(x)
    elsif attr == 'list_name'
      list_name = sprint.trello.card_list(x).name
      TrelloHelper::LIST_POSITION_ADJUSTMENT[list_name] ? TrelloHelper::LIST_POSITION_ADJUSTMENT[list_name] : list_name.hash.abs
    else
      sprint.trello.trello_do('send_attr') do
        return x.send(attr)
      end
    end
  end

  def data
    if @data.empty? && sprint && function
      @data = sprint.send(function)
    end
    sort_keys = []
    sort_keys << sort_key.to_s if sort_key
    sort_keys << secondary_sort_key.to_s if secondary_sort_key && type != :bug
    unless sort_keys.empty?
      @data.sort_by! { |x| sort_keys.map { |key| send_attr(x, key) } }
    end
    @data
  end

  def offenders
    data.map { |card| sprint.trello.member_emails(members(card)) }.flatten.uniq
  end

  def rows(user = nil)
    _data = data
    if user
      _data = data.select { |card| sprint.trello.member_emails(members(card)).include?(user) }
    end
    _data.map do |x|
      # Get data for each column
      columns.map do |col|
        col.process(x)
      end
    end
  end

  def print_title
    "%s %s" % [title, (!sprint.nil? && first_day?) ? "(to be completed by end of day today)" : '']
  end

  def required?
    if days_before_code_freeze && sprint.code_freeze
      ((sprint.code_freeze.to_time - Time.new) / (60 * 60 * 24)).ceil <= days_before_code_freeze
    elsif day.nil?
      true
    else
      Date.today >= due_date
    end
  end

  def first_day?
    if day.nil?
      false
    else
      Date.today == due_date
    end
  end

  def due_date
    day ? sprint.start + day.days : sprint.code_freeze
  end

  def members(card)
    sprint.trello.card_members(card)
  end

  class Column
    attr_accessor :header, :attr, :fmt, :sub_attr, :report, :max_length
    def initialize(opts, report)
      opts.each do |k, v|
        send("#{k}=", v)
      end
      @report = report
    end

    def send_attr(x, attr)
      if attr == 'bug_url'
        "https://bugzilla.redhat.com/show_bug.cgi?id=#{x['id']}"
      elsif attr == 'bug_summary'
        x['summary']
      elsif attr == 'bug_owner'
        x['assigned_to']
      elsif x.is_a? Hash
        x[attr.to_sym]
      elsif attr == 'members'
        report.members(x)
      elsif attr == 'list'
        report.sprint.trello.card_list(x)
      elsif attr == 'team_name'
        report.sprint.trello.team_name(x)
      else
        report.sprint.trello.trello_do('send_attr') do
          return x.send(attr)
        end
      end
    end

    def process(row)
      value = send_attr(row, attr)
      if value.is_a?(Array)
        value = value.map { |v| process_sub_attr(v) }
      else
        value = process_sub_attr(value)
      end
      format(value)
    end

    def process_sub_attr(value)
      value = sub_attr ? send_attr(value, sub_attr) : value
      value
    end

    # If no attr is specified, just use the heading name
    def attr
      @attr || header.downcase
    end

    def format(value)
      if value.is_a? Array
        format_str(value.join(', '))
      else
        format_str(value)
      end
    end

    # Format a string if needed (like for URLs)
    def format_str(value)
      value ||= '<none>'
      value = fmt ? (fmt % [value]) : value
      if max_length && (value.is_a? String) && value.length > max_length
        value = value[0..(max_length - 4)]
        value += ('.' * (max_length - value.length))
      end
      value
    end
  end
end

class UserStoryReport
  include SprintReport
  def initialize(opts)
    _opts = {
      headings: [
        { header: 'url', attr: 'short_url' },
        { header: 'Team', attr: 'team_name', max_length: 15 },
        { header: 'List', sub_attr: 'name', max_length: 15 },
        { header: 'Name', max_length: 30 },
        { header: 'Members', sub_attr: 'full_name', max_length: 25 }
      ],
      bug_headings: [
        { header: 'bug_url', attr: 'bug_url' },
        { header: 'bug_owner', attr: 'bug_owner', max_length: 20 },
        { header: 'bug_summary', attr: 'bug_summary', max_length: 35 }
      ],
      secondary_sort_key: :list_name
    }
    super(_opts.merge(opts))
  end
end

class StatsReport
  include SprintReport

  def initialize
    super({
      title: "Sprint Stats",
      function: :stats,
      headings: [
        { header: "Count" },
        { header: "Name" },
      ],
    })
  end
end

class DeadlinesReport
  include SprintReport

  def initialize
    super({
      title: "Deadlines",
      function: :upcoming,
      headings: [
        { header: "Date" },
        { header: "Title" }
      ],
    })
  end
end

class EnvironmentsReport
  include SprintReport

  def initialize
    super({
      title: "Environment Pushes",
      function: :upcoming,
      headings: [
        { header: "Date" },
        { header: "Title" }
      ],
    })
  end
end
