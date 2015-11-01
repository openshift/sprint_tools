require 'sprint'

module SprintReport
  attr_accessor :title, :headings, :function, :columns, :data, :day, :days_before_release, :sort_key, :friendly
  attr_accessor :sprint
  def initialize(opts)
    opts.each do |k,v|
      send("#{k}=",v)
    end

    @columns = headings.map{|x| Column.new(x, self)}
    @data = []
  end

  def data
    if @data.empty? && sprint && function
      @data = sprint.send(function)
    end
    if sort_key
      @data = @data.sort_by{|x| x.send(sort_key)}
    end
    @data
  end

  def offenders
    data.map{|x| sprint.trello.member_emails(members(x))}.flatten.uniq
  end

  def rows(user = nil)
    _data = data
    if user
      _data = data.select{|x| sprint.trello.member_emails(members(x)).include?(user)}
    end
    _data.map do |row|
      # Get data for each column
      columns.map do |col|
        col.process(row)
      end
    end
  end

  def print_title
    "%s %s" % [title, (!sprint.nil? && first_day?) ? "(to be completed by end of day today)" : '']
  end

  def required?
    if days_before_release && sprint.next_major_release
      return (sprint.next_major_release.to_time - Time.new).to_i / (60*60*24) <= days_before_release
    elsif day.nil?
      return true
    else
      return Date.today >= due_date
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
    day ? sprint.start + day.days : sprint.next_major_release
  end

  def members(card)
    sprint.trello.card_members(card)
  end

  class Column
    attr_accessor :header, :attr, :fmt, :sub_attr, :report
    def initialize(opts, report)
      opts.each do |k,v|
        send("#{k}=",v)
      end
      @report = report
    end

    def send_attr(card, attr)
      if attr == 'members'
        return report.members(card)
      elsif attr == 'list'
        return report.sprint.trello.card_list(card)
      else
        report.sprint.trello.trello_do('send_attr') do
          return card.send(attr)
        end
      end
    end

    def process(row)
      value = row.is_a?(Hash) ? row[attr.to_sym] : send_attr(row, attr)
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
      if (value.is_a? String) && value.length > 30
        value = value[0..26]
        value += ('.' * (30 - value.length))
      end
      value
    end
  end
end

class UserStoryReport
  include SprintReport
  def initialize(opts)
    _opts = {
      :headings => [
        { :header => 'name', :attr => 'short_url' },
        { :header => 'members', :sub_attr => 'full_name' },
        { :header => 'list', :sub_attr => 'name' },
        { :header => 'Name' },
      ],
      :sort_key => :member_ids
    }
    super(_opts.merge(opts))
  end
end

class StatsReport
  include SprintReport

  def initialize
    super({
      :title => "Sprint Stats",
      :function => :stats,
      :headings => [
        {:header => "Count"},
        {:header => "Name"},
      ],
    })
  end
end

class DeadlinesReport
  include SprintReport

  def initialize
    super({
      :title => "Upcoming Deadlines",
      :function => :upcoming,
      :headings => [
        {:header => "Date"},
        {:header => "Title"}
      ],
    })
  end
end

class EnvironmentsReport
  include SprintReport

  def initialize
    super({
      :title => "Environment Pushes",
      :function => :upcoming,
      :headings => [
        {:header => "Date"},
        {:header => "Title"}
      ],
    })
  end
end
