require 'trello_helper'
require 'queries'
require 'bugzilla_helper'
require 'core_ext/date'

class Sprint
  # Calendar related attributes
  attr_accessor :start, :finish, :prod, :stg, :int, :code_freeze, :feature_complete, :stage_one_dep_complete
  # Trello related attributes
  attr_accessor :trello
  # UserStory related attributes
  attr_accessor :sprint_stories, :not_accepted_stories, :accepted_and_after_stories, :all_stories, :rfes, :processed, :results

  attr_accessor :debug

  def initialize(opts)
    opts.each do |k,v|
      send("#{k}=",v)
    end
    init_stories
    init_rfes
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

  def sprint_card_date(str)
    sc = trello.sprint_card
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
    sc = trello.sprint_card
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

  def code_freeze
    return @code_freeze if @code_freeze
    @code_freeze = sprint_card_date("Release Code Freeze")
    @code_freeze
  end

  def feature_complete
    return @feature_complete if @feature_complete
    @feature_complete = sprint_card_date("Feature Complete")
    unless @feature_complete
      @feature_complete = code_freeze
      trello.sprint_length_in_weeks.times do
        @feature_complete = @feature_complete.previous(trello.sprint_end_day.to_sym)
      end if @feature_complete
    end
    @feature_complete
  end

  def stage_one_dep_complete
    return @stage_one_dep_complete if @stage_one_dep_complete
    @stage_one_dep_complete = sprint_card_date("Stage 1 Dep Complete")
    unless @stage_one_dep_complete
      @stage_one_dep_complete = code_freeze
      ((trello.sprint_length_in_weeks * 2) + 2).times do
        @stage_one_dep_complete = @stage_one_dep_complete.previous(trello.sprint_end_day.to_sym)
      end if @stage_one_dep_complete
    end
    @stage_one_dep_complete
  end

  def title(short = false)
    sprint_name = 'Current Sprint'
    if trello.sprint_card.name =~ TrelloHelper::SPRINT_REGEX
      sprint_name = "Sprint #{$1}"
    end
    str = "Report for #{sprint_name}: Day %d" % [day]
    str << " (%s - %s)" % [start, self.finish] unless short
    str
  end

  def init_stories
    # Reset processed status
    @processed = {}
    @results = {}

    @sprint_stories = []
    @not_accepted_stories = []
    @accepted_and_after_stories = []
    @all_stories = []

    trello.boards.each do |board_id, board|
      team_map = trello.board_id_to_team_map[board_id]
      lists = trello.board_lists(board, trello.max_lists_per_board + 10)
      lists.each do |list|
        if TrelloHelper::CURRENT_SPRINT_STATES.include?(list.name)
          cards = trello.list_cards(list)
          cards = cards.clone.delete_if {|card| card.name =~ TrelloHelper::SPRINT_REGEX && !card.due.nil?}
          @sprint_stories += cards unless team_map[:exclude_from_sprint_report]
          if TrelloHelper::ACCEPTED_STATES.include?(list.name)
            @accepted_and_after_stories += cards
          else
            @not_accepted_stories += cards unless team_map[:exclude_from_sprint_report]
          end
          @all_stories += cards
        elsif !list.closed? && list.name !~ TrelloHelper::SPRINT_REGEXES
          cards = trello.list_cards(list)
          @not_accepted_stories += cards unless team_map[:exclude_from_sprint_report]
          @all_stories += cards
        elsif list.name =~ TrelloHelper::SPRINT_REGEXES
          cards = trello.list_cards(list)
          @accepted_and_after_stories += cards
          @all_stories += cards
        end
      end
    end
  end

  def init_rfes
    return @rfes if @rfes
    bugzilla = load_conf(BugzillaHelper, CONFIG.bugzilla, true)
    @rfes = bugzilla.rfes
    @rfes
  end

  def query_stories(query)
    if query[:include_backlog]
      not_accepted_stories
    else
      sprint_stories
    end
  end

  def find(name, match = true)
    query = queries[name]
    where = nil
    if parent = query[:parent]
      where = send(parent)
    elsif query[:type] == 'rfes'
      where = rfes.values
    else
      where = query_stories(query)
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
