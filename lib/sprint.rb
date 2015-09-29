require 'trello_helper'
require 'queries'
require 'core_ext/date'

class Sprint
  # Calendar related attributes
  attr_accessor :start, :finish, :sprint_card, :prod, :stg, :int
  # Trello related attributes
  attr_accessor :trello
  # UserStory related attributes
  attr_accessor :stories, :processed, :results

  attr_accessor :debug

  def initialize(opts)
    opts.each do |k,v|
      send("#{k}=",v)
    end
    get_stories
  end

  def day
    $date ||= Date.today # Allow overriding for testing
    ($date - start + 1).to_i
  end

  def show_days(report)
    puts "%s - Starts on %s" % [report.title,report.day]
    puts
    (start..send(:end)).each do |x|
      $date = x
      req = case
            when report.first_day?
              "Start"
            when report.required?
              "  |  "
            else
              ''
            end
      puts "%s (%2d) - %s" % [x,day,req]
    end
    $date ||= Date.today
  end

  def sprint_card
    return @sprint_card if @sprint_card
    board = trello.board(trello.board_ids.first)
    trello.board_lists(board).each do |list|
      if list.name == 'In Progress'
        @sprint_card = list.cards.sort_by { |card| card.pos }.first
        return @sprint_card
      end
    end
    nil
  end

  def sprint_card_date(str)
    sc = sprint_card
    if sc
      sc.desc.each_line do |line|
        if line =~ /(\d*-\d*-\d*).*-.*#{str}/i
          return Date.parse($1)
          break
        end
      end
    end
    nil
  end

  def finish
    return @finish if @finish
    sc = sprint_card
    if sc
      @finish = sc.due.to_date
    end
  end

  def start
    return @start if @start
    @start = sprint_card_date("Start of Sprint")
    unless @start
      @start = finish
      trello.sprint_length_in_weeks.times{@start = @start.previous(trello.sprint_start_day.to_sym)}
    end
    @start
  end

  def prod
    return @prod if @prod
    @prod = sprint_card_date("Push to PROD")
    @prod
  end

  def stg
    return @stg if @stg
    @stg = sprint_card_date("Push to STG")
    @stg
  end

  def int
    return @int if @int
    @int = sprint_card_date("First Push to INT")
    @int
  end

  def title(short = false)
    str = "Report for Current Sprint: Day %d" % [day]
    str << " (%s - %s)" % [start, self.finish] unless short
    str
  end

  def get_stories
    # Reset processed status
    @processed = {}
    @results = {}

    @stories = []
    trello.boards(true).each do |board_id, board|
      lists = trello.target(trello.board_lists(board))
      lists.each do |list|
        if list.name == 'In Progress' || list.name == 'Complete' || list.name == 'Accepted'
          cards = trello.list_cards(list)
          cards = cards.delete_if {|card| card.name =~ /^Sprint \d+/ && !card.due.nil?}
          @stories += cards
        end
      end
    end
    @stories
  end

  def find(name, match = true)
    query = queries[name]
    where = stories
    if parent = query[:parent]
      where = send(parent)
    end

    unless !debug && processed[name]
      retval = where.partition do |x|
        query[:function].call(x)
      end

      results[name] = {
        true  => retval[0],
        false => retval[1]
      }
    end

    results[name][match]
  ensure
    processed[name] = true
  end

  private
  def method_missing(method,*args,&block)
    begin
      case method.to_s
      when *(queries.keys.map(&:to_s))
        find(method,*args)
      when /^not_/
        meth = method.to_s.scan(/not_(.*)/).flatten.first.to_sym
        send(meth,false)
      else
        super
      end
    rescue ArgumentError
      super
    end
  end

end
