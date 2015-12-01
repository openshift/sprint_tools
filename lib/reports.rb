require 'sprint'

module SprintReport
  attr_accessor :title, :headings, :function, :columns, :data, :day, :days_before_release, :sort_key, :secondary_sort_key, :friendly
  attr_accessor :sprint
  def initialize(opts)
    opts.each do |k,v|
      send("#{k}=",v)
    end

    @columns = headings.map{|heading| Column.new(heading, self)}
    @data = []
  end

  def send_attr(card, attr)
    if attr == 'team_name'
      return sprint.trello.team_name(card)
    elsif attr == 'list_name'
      list_name = sprint.trello.card_list(card).name
      return TrelloHelper::LIST_POSITION_ADJUSTMENT[list_name] ? TrelloHelper::LIST_POSITION_ADJUSTMENT[list_name] : list_name.hash.abs
    else
      sprint.trello.trello_do('send_attr') do
        return card.send(attr)
      end
    end
  end

  def data
    if @data.empty? && sprint && function
      @data = sprint.send(function)
    end
    if secondary_sort_key && !sort_key
      sort_key = secondary_sort_key
      secondary_sort_key = nil
    end
    if sort_key
      if secondary_sort_key
        @data.sort_by!{|card| [send_attr(card, sort_key.to_s), send_attr(card, secondary_sort_key.to_s)]}
      else
        @data.sort_by!{|card| send_attr(card, sort_key.to_s)}
      end
    end
    @data
  end

  def offenders
    data.map{|card| sprint.trello.member_emails(members(card))}.flatten.uniq
  end

  def rows(user = nil)
    _data = data
    if user
      _data = data.select{|card| sprint.trello.member_emails(members(card)).include?(user)}
    end
    _data.map do |card|
      # Get data for each column
      columns.map do |col|
        col.process(card)
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
    attr_accessor :header, :attr, :fmt, :sub_attr, :report, :max_length
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
      elsif attr == 'team_name'
        return report.sprint.trello.team_name(card)
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
      if max_length && (value.is_a? String) && value.length > max_length
        value = value[0..(max_length-4)]
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
      :headings => [
        { :header => 'url', :attr => 'short_url' },
        { :header => 'Team', :attr => 'team_name', :max_length => 15 },
        { :header => 'List', :sub_attr => 'name', :max_length => 15 },
        { :header => 'Name', :max_length => 30 },
        { :header => 'Members', :sub_attr => 'full_name', :max_length => 25 }
      ],
      :secondary_sort_key => :list_name
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
