require 'trello'
require 'kramdown'
require 'rest_client'

class TrelloHelper
  # Trello Config
  attr_accessor :consumer_key, :consumer_secret, :oauth_token, :teams,
                :organization_id, :roadmap_id,
                :public_roadmap_id,
                :organization_name,
                :sprint_length_in_weeks, :sprint_start_day, :sprint_end_day, :logo,
                :roadmap_board_lists, :max_lists_per_board,
                :current_release_labels, :next_release_labels, :default_product,
                :other_products, :product_order, :archive_path, :dependent_work_boards

  attr_accessor :trello_login_to_email, :cards_by_list, :labels_by_card, :list_by_card, :members_by_card, :checklists_by_card, :sprint_lists_by_board, :comments_by_card,
                :all_lists_by_board

  DEFAULT_RETRIES = 14
  DEFAULT_RETRY_SLEEP = 5
  DEFAULT_RETRY_INC = 1

  FUTURE_LABEL = 'future'
  FUTURE_TAG = "[#{FUTURE_LABEL}]"

  STAGE1_DEP_LABEL = 'stage1-dep'

  SPRINT_REGEX = /^Sprint (\d+)$/
  DONE_REGEX = /^Done: ((\d+)(.(\d+))?(.(\d+))?)/
  RELEASE_COMPLETE_REGEX = /^Complete ((\d+)\.(\d+)(.(\d+))?(.(\d+))?)/
  SPRINT_REGEXES = Regexp.union([SPRINT_REGEX, DONE_REGEX, RELEASE_COMPLETE_REGEX])

  RELEASE_LABEL_REGEX = /^(proposed|targeted|committed)-(?:(.+)-)?((?:\D*(\d+))\.(?:\D*(\d+))(?:\.(?:\D*(\d+)))?(?:\.(?:\D*(\d+)))?)/
  # .match ->  [0,      1,|                              2,|    3,|    4,|     (+3)  5,|        (+3)  6,|           (+3)  7|     |]
  #             |         |                                |      |.-----|-------------|----------------|------------------|-----'
  #        [original_str, state,                    product/nil, release,major,        minor,           patch,             hotfix]
  STAR_LABEL_REGEX = /^([1-5])star$/

  CARD_NAME_REGEX = /^(\((\d+|\?)\))?(.*)/

  EPIC_REF_REGEX = /\[.*\]\(https?:\/\/trello\.com\/.+\) \([^\)]+\)/

  EPIC_TAG_REGEX = /\[[^\]]+\]/

  ACCEPTED_STATES = {
    'Accepted' => 1,
    'Done' => 2
  }

  COMPLETE_STATES = {
    'Complete Upstream' => 1,
    'Complete' => 2
  }

  IN_PROGRESS_STATES = {
    'Design' => 1,
    'In Progress' => 2,
    'Pending Upstream' => 3,
    'Pending Merge' => 4
  }

  NEXT_STATES = {
    'Stalled' => 1,
    'Next' => 2
  }

  BACKLOG_STATES = {
    'Backlog' => 1
  }

  NEW_STATES = {
    'New' => 1
  }

  REFERENCE_STATES = {
    'References' => 1
  }

  CURRENT_SPRINT_NOT_ACCEPTED_STATES = IN_PROGRESS_STATES.merge(COMPLETE_STATES)

  CURRENT_SPRINT_NOT_IN_PROGRESS_STATES = COMPLETE_STATES.merge(ACCEPTED_STATES)

  CURRENT_SPRINT_STATES = IN_PROGRESS_STATES.merge(CURRENT_SPRINT_NOT_IN_PROGRESS_STATES)

  BUGZILLA_REGEX = /(https?:\/\/bugzilla\.redhat\.com\/[^\?]+\?id=(\d+))/

  RELEASE_STATE_ORDER = {
    'committed' => 0,
    'targeted' => 1,
    'proposed' => 2
  }

  RELEASE_STATES = ['committed', 'targeted', 'proposed']

  RELEASE_STATE_DISPLAY_NAME = {
    'committed' => 'Complete or Committed',
    'targeted' => 'Targeted',
    'proposed' => 'Proposed'
  }

  LIST_POSITION_ADJUSTMENT = {
    'Done' => 10,
    'Accepted' => 50,
    'Complete' => 100,
    'In Progress' => 200,
    'Design' => 250,
    'Next' => 300,
    'Stalled' => 350,
    'Backlog' => 400,
    'New' => 800
  }

  MAX_LIST_POSITION_ADJUSTMENT = 1000

  UNASSIGNED_RELEASE = "Unassigned Release"
  FUTURE_RELEASE = "Future Release"

  NONE_CHECKLIST_NAME = 'Tags without Epics'

  ROADMAP = 'roadmap'

  TRELLO_CARD_INCREMENT = 16384.0

  ORG_BACKUP_PREFIX = 'org_'
  ORG_MEMBERS_BACKUP_PREFIX = 'org_members_'

  SortableCard = Struct.new(:card, :new_pos, :state, :product, :release)

  def initialize(opts)
    opts.each do |k, v|
      send("#{k}=", v)
    end

    Trello.configure do |config|
      config.consumer_key = @consumer_key
      config.consumer_secret = @consumer_secret
      config.oauth_token = @oauth_token
    end

    @members_by_id = {}
    @board_members = {}
    @cards_by_list = {}
    @labels_by_card = {}
    @label_by_id = {}
    @list_by_card = {}
    @members_by_card = {}
    @comment_actions_by_card = {}
    @checklists_by_card = {}
    @sprint_lists_by_board = {}
    @all_lists_by_board = {}
    @comments_by_card = {}
    @sortable_card_labels = {}
    @dependent_work_board = {}
    @next_dependent_work_list = {}
  end

  def board_ids
    board_ids = []
    teams.each do |team, team_map|
      team_boards_map = team_boards_map(team_map)
      team_boards_map.each do |b_name, b_id|
        board_ids << b_id
      end
    end
    board_ids
  end

  # Associate sortable metadata to one trello card
  def sortable_card(card)
    sortable_card_labels = card_labels(card).map { |label| sortable_card_label(label) }.select { |label| !label.nil? }
    if !sortable_card_labels.empty?
      label_data = sortable_card_labels.first
      sortable_card_labels[1..-1].each do |label|
        if labels_in_order(label_data, label)
          label_data = label
        end
      end
    end
    label_data = label_data ? label_data.dup : SortableCard.new
    label_data.card = card
    label_data.new_pos = card.pos
    label_data
  end

  # generate a list of SortableCard objects from a list of cards
  def sortable_cards(list)
    sortable_cards = []
    needs_sorting = false
    last_card = nil
    list_cards(list).sort_by { |card| card.pos }.each do |card|
      card = sortable_card(card)
      if card.release
        if last_card
          if !cards_in_order(last_card, card) && !cards_equal(last_card, card)
            needs_sorting = true
          end
        end
        last_card = card
      end
      sortable_cards << card
    end
    needs_sorting ? sortable_cards : nil
  end


  # O(n log n) implementation cribbed shamelessly from
  # https://en.wikipedia.org/wiki/Longest_increasing_subsequence
  def longest_increasing_sequence(a)
    pile = []
    middle_vals = []
    longest = 0
    a.each_index do |i|
      lo = 1
      hi = longest
      while lo <= hi
        mid = Float((lo + hi) / 2).ceil
        if a[middle_vals[mid]] < a[i]
          lo = mid + 1
        else
          hi = mid - 1
        end
      end
      pile[i] = middle_vals[lo - 1]
      middle_vals[lo] = i
      if lo > longest
        longest = lo
      end
    end
    longest_sequence = []
    k = middle_vals[longest]
    (0..(longest - 1)).reverse_each do |i|
      longest_sequence[i] = a[k]
      k = pile[k]
    end
    longest_sequence
  end

  # For each card which needs to be updated, find the ids of cards
  # before and after it which should be used in calculating its new
  # position. Handle edge cases where the card is at going to be at
  # the start or end of the list
  #
  # The end of the run is always selected as the "after" card, since
  # in the caller, we calculate the new position as halfway between
  # the "before" card position and the "after" card position.
  # Selecting the end of the run makes sure that the calculated
  # position is strictly increasing, even if Trello renumbers the
  # cards
  def bounding_card_ids_by_id(cards)
    lis = longest_increasing_sequence(cards.map { |c| c.card.pos })
    run_start = -1
    run_end = -1
    cards_between_bounding = {}
    # Iterate over the cards to find contiguous runs of cards which need
    # their position attribute updated
    cards.each_with_index do |card, index|
      if !lis.include? card.card.pos
        if run_start == -1
          run_start = index
        end
        run_end = index
      end
      # Check if we're in a run of cards that need updating
      if run_start != -1
        # Check if we've reached the end of the run
        if (lis.include? card.card.pos) || (index == (cards.length - 1))
          # Find the position of the in-order card preceding the run,
          # use that to determine the lower bound for the run of cards
          # needing updates.
          #
          # Determine before and after card ids. After_index will
          # always be the same - we want the card to be between the
          # previous card and the end of the run, so it's always
          # properly ordered regardless how trello renumbers the list.
          after_index = (run_end == (cards.length - 1)) ? nil : cards[run_end + 1].card.id
          (run_start..run_end).each do |run_index|
            bounding_card_ids = {}
            bounding_card_ids[:before] = (run_index == 0) ? nil : cards[run_index - 1].card.id
            bounding_card_ids[:after] = after_index
            cards_between_bounding[cards[run_index].card.id] = bounding_card_ids
          end
          run_start = -1
          run_end = -1
        end
      end
    end
    cards_between_bounding
  end

  def product_to_order
    @product_to_order ||= Hash[product_order.map.with_index { |v, i| [v, i] }]
  end

  # Return true if the product labels for SortableCard objects card1
  # and card2 are in order
  def labels_in_order(card1, card2)
    product_to_order[card1.product] < product_to_order[card2.product]
  end

  # Return true if the SortableCard objects card1 and card2 are in
  # order
  def cards_in_order(card1, card2)
    if card1.release < card2.release
      return true
    elsif card1.release == card2.release
      if RELEASE_STATE_ORDER[card1.state] < RELEASE_STATE_ORDER[card2.state]
        return true
      end
    end
    if card1.product != card2.product
      return true
    end
    false
  end

  # Return true if the SortableCard objects card1 and card2 are equal
  def cards_equal(card1, card2)
    ((RELEASE_STATE_ORDER[card1.state] == RELEASE_STATE_ORDER[card2.state]) &&
     (card1.release == card2.release))
  end

  # Return a list of valid product names - based on the configuration
  # in trello.yml - to match against
  def valid_products
    @valid_products ||= initialize_valid_products
  end

  def initialize_valid_products
    valid_prod ||= other_products || []
    valid_prod << default_product if default_product
    valid_prod
  end

  def board_id_to_team_map
    return @board_id_to_team_map if @board_id_to_team_map
    @board_id_to_team_map = {}
    teams.each do |team, team_map|
      team_boards_map = team_boards_map(team_map)
      team_boards_map.each do |b_name, b_id|
        @board_id_to_team_map[b_id] = team_map
      end
    end
    @board_id_to_team_map
  end

  def card_ref(card)
    board_name = nil
    teams.each do |team_name, team_map|
      team_boards_map = team_boards_map(team_map)
      team_boards_map.each do |b_name, b_id|
        if b_id == card.board_id
          board_name = b_name
          break
        end
      end
    end
    "#{board_name}_#{card.short_id}"
  end

  def team_boards(team_name)
    team_map = teams[team_name.to_sym]
    team_boards = []
    team_boards_map = team_boards_map(team_map)
    team_boards_map.each do |board_name, board_id|
      team_boards << boards[board_id]
    end
    team_boards
  end

  def team_boards_map(team_map)
    team_boards_map = nil
    if team_map.has_key?(:boards)
      team_boards_map = team_map[:boards]
    else
      team_boards_map = team_map
    end
    team_boards_map
  end

  def team_board(board_name)
    board_name = board_name.to_sym
    teams.each do |team_name, team_map|
      team_boards_map = team_boards_map(team_map)
      team_boards_map.each do |b_name, b_id|
        return boards[b_id] if b_name == board_name
      end
    end
  end

  def team_name(card)
    teams.each do |team_name, team_map|
      team_boards_map = team_boards_map(team_map)
      team_boards_map.each do |b_name, b_id|
        if b_id == card.board_id
          return team_name.to_s
        end
      end
    end
  end

  def sprint_length_in_days
    @sprint_length_in_days ||= (@sprint_length_in_weeks * 7)
  end

  ##
  # Hits the Trello API directly to get the Members from a
  # +Trello::Card+ without having to hit the /members API endpoint
  #
  # +card+ is a +Trello::Card+ object
  #
  # modifies +@board_members+ via +add_member+
  #
  # returns +members+, an +Array+ of +Trello::Member+ objects
  def get_card_members(card)
    raw_members = ""
    trello_do('get_card_members') do
      raw_members = Trello.client.get("/cards/#{card.id}/members")
    end
    json_members = JSON.parse(raw_members)
    members = []
    json_members.each do |m|
      member = Trello::Member.new(m)
      members << member
      add_member(member)
    end
    members
  end

  ##
  # Adds a +Trello::Board+ object to the instance caching collections
  #
  # +board+ is a +Trello::Board+ object
  #
  # modifies +@boards+, +@public_roadmap_board+ and +@roadmap_board+
  #
  def add_board(board)
    @boards ||= {}
    if board_ids.include?(board.id)
      @boards[board.id] = board
    elsif public_roadmap_id == board.id
      @public_roadmap_board = board
    elsif roadmap_id == board.id
      @roadmap_board = board
    end
  end

  ##
  # Tries to find a cached label for +label_id+.
  #
  # +label+ is a label object in Hash format, as returned by
  # Trello::Card#card_labels. If +label+ is provided and +label_id+
  # doesn't match a cached label, +label+ is used to create a
  # +Trello::Label+ object which is then cached for that id
  def label_by_id(label_id, label=nil)
    if @label_by_id.include?(label_id)
      @label_by_id[label_id]
    elsif label
      return (@label_by_id[label_id] = Trello::Label.new(label))
    else
      trello_do('label_by_id') do
        @label_by_id[label_id] = Trello::Label.find(label_id)
        return @label_by_id[label_id]
      end
    end
  end

  ##
  # Adds a +Trello::Label+ object to the instance caching collections
  #
  # +label+ is a +Trello::Label+ object
  #
  # modifies +@label_by_id+
  #
  def add_label(label)
    @label_by_id[label.id] = label if !@label_by_id.include?(label.id)
  end

  ##
  # Adds a +Trello::Member+ object to the instance caching collections
  #
  # +member+ is a +Trello::Member+ object
  # +board+ is a +Trello::Board+ object that is associated with +member+
  #
  # modifies +@board_members+, +@members_by_id+
  #
  def add_member(member, board=nil)
    if board && board.respond_to?(:id)
      members = @board_members[board.id] || []
      # Add member to @board_members if no entry matching member.id exists
      members << member if !members.map { |m| m.respond_to?(:id) ? m.id : [] }.include?(member.id)
      @board_members[board.id] = members
    end
    members_by_id[member.id] = member
  end

  ##
  # Adds a +Trello::Card+ object to the instance caching collections
  #
  # +card+ is a +Trello::Card+ object
  #
  # modifies +@labels_by_card+, +@cards_by_list+, and +@members_by_card+
  #
  def add_card(card)
    if !card.closed
      @labels_by_card[card.id] ||= card.card_labels.map do |label|
        label_by_id(label['id'], label)
      end
      (@cards_by_list[card.list_id] ||= []) << card
    end
    if !@members_by_card.include?(card.id) || @members_by_card[card.id].size < card.member_ids.size
      missing_member_ids = card.member_ids.select { |m_id| !members_by_id.include?(m_id) }
      if !missing_member_ids.empty?
        members = get_card_members(card)
        members.each do |m|
          if missing_member_ids.include?(m.id)
            add_member(m)
          end
        end
      end
      @members_by_card[card.id] = card.member_ids.map { |m_id| members_by_id[m_id] } #members_by_id.select { |m_id, _| card.member_ids.include?(m_id) }
    end
  end

  ##
  # Adds a +Trello::Checklist+ object to the instance caching collections
  #
  # +checklist+ is a +Trello::Checklist+ object
  #
  # modifies +@checklists_by_card+
  #
  def add_checklist(checklist, checklist_id_to_card_id)
    begin
      @checklists_by_card[checklist.card_id] ||= checklist
    rescue NoMethodError # ruby-trello 1.3.0 doesn't add the checklist.card_id attr
      @checklists_by_card[checklist_id_to_card_id[checklist.id]] ||= checklist
    end
  end

  ##
  # Adds a +Trello::List+ object to the instance caching collections
  #
  # +list+ is a +Trello::List+ object
  #
  # modifies +@cards_by_list+, +@list_by_card+, and +@sprint_lists_by_board+
  #
  def add_list(list)
    (@cards_by_list[list.id] ||= []).each do |card|
      @list_by_card[card.id] = list
    end
    if @all_lists_by_board.include?(list.board_id)
      @all_lists_by_board[list.board_id] << list if !@all_lists_by_board[list.board_id].map { |l| l.board_id }.include?(list)
    else
      @all_lists_by_board[list.board_id] = [list]
    end
  end

  ##
  # Adds +Trello+ API objects that have been parsed and loaded into a
  # +TrelloJsonLoader+ object
  #
  # +json_loader+ is a +TrelloJsonLoader+ that has been populated with
  # +Trello+ API objects
  def add_json_loader_content(json_loader)
    # We only have one org, so load it if it's there
    @org = json_loader.organizations_by_id.values.select { |o| o.name == organization_id }.first
    # org members are a special case, since they're loaded as an array
    @org_members = json_loader.organization_members

    json_loader.boards_by_id.values().each { |d| add_board(d) }
    json_loader.labels_by_id.values().each { |d| add_label(d) }
    json_loader.members_by_id.values().each { |d| add_member(d) }
    json_loader.cards_by_id.values().each { |d| add_card(d) }
    json_loader.checklists_by_id.values().each { |d|
      add_checklist(d, json_loader.checklist_id_to_card_id)
    }
    json_loader.lists_by_id.values().each { |d| add_list(d) }
  end

  def boards
    return @boards if @boards
    @boards = {}
    org_boards.each do |board|
      if board_ids.include?(board.id)
        @boards[board.id] = board
      end
    end
    @boards
  end

  def sprint_card
    return @sprint_card if @sprint_card
    board = board(board_ids.last)
    board_lists(board).each do |list|
      if IN_PROGRESS_STATES.include?(list.name)
        @sprint_card = list_cards(list).sort_by { |card| card.pos }.first
        return @sprint_card
      end
    end
    nil
  end

  def dependent_work_board(board_id = dependent_work_board_id)
    @dependent_work_board[board_id] = find_board(board_id) unless @dependent_work_board[board_id]
    @dependent_work_board[board_id]
  end

  def roadmap_board
    if roadmap_id
      @roadmap_board = find_board(roadmap_id) unless @roadmap_board
    end
    @roadmap_board
  end

  def public_roadmap_board
    if public_roadmap_id
      @public_roadmap_board = find_board(public_roadmap_id) unless @public_roadmap_board
    end
    @public_roadmap_board
  end

  def find_board(board_id)
    trello_do('find_board') do
      return Trello::Board.find(board_id)
    end
  end

  def find_card_by_short_id(board, card_id)
    trello_do('find_card_by_short_id') do
      return board.find_card(card_id)
    end
  end

  def find_card(card_id, retry_on_error = true)
    card = nil
    begin
      if retry_on_error
        trello_do('find_card') do
          card = Trello::Card.find(card_id)
        end
      else
        card = Trello::Card.find(card_id)
      end
    rescue
    end
    card
  end

  def roadmap_boards
    rbs = []
    rbs << public_roadmap_board if public_roadmap_board
    rbs << roadmap_board if roadmap_board
    rbs
  end

  def roadmap_label_colors_by_name
    roadmap_labels = board_labels(roadmap_board)
    roadmap_label_colors_by_name = {}
    roadmap_labels.each do |label|
      roadmap_label_colors_by_name[label.name] = label.color
    end
    roadmap_label_colors_by_name
  end

  def tag_to_epics(rm_boards = roadmap_boards)
    tag_to_epics = {}
    rm_boards.each do |roadmap_board|
      epic_lists = epic_lists(roadmap_board)
      epic_lists.each do |epic_list|
        list_cards(epic_list).each do |epic_card|
          card_labels(epic_card).each do |label|
            if label.name.start_with? 'epic-'
              tag_to_epics[label.name] = [] unless tag_to_epics[label.name]
              tag_to_epics[label.name] << epic_card
            end
          end
          epic_card.name.scan(EPIC_TAG_REGEX).each do |tag|
            tag.downcase!
            if tag != FUTURE_TAG
              tag_to_epics[tag] = [] unless tag_to_epics[tag]
              tag_to_epics[tag] << epic_card
            end
          end
        end
      end
    end
    tag_to_epics
  end

  def board_lists(board, list_limit = max_lists_per_board)
    lists = nil
    lists = @sprint_lists_by_board[board.id] if max_lists_per_board.nil? || (list_limit && list_limit <= max_lists_per_board)
    if !lists
      trello_do('lists') do
        lists = @all_lists_by_board[board.id] ||= board.lists(filter: [:all])
        lists = lists.delete_if { |list| list.name !~ TrelloHelper::SPRINT_REGEXES && list.closed? }
        lists.sort_by! { |list| [list.name =~ TrelloHelper::SPRINT_REGEXES ? ($1.to_i) : 9999999, $3 ? $3.to_i : $9.to_i, $5 ? $5.to_i : $10.to_i, $7 ? $7.to_i : $12.to_i, $14.to_i] }
        lists.reverse!
      end
    end
    @sprint_lists_by_board[board.id] = lists if ((list_limit && max_lists_per_board && (list_limit >= max_lists_per_board)) || list_limit.nil?) && !@sprint_lists_by_board[board.id]
    lists = lists.first(list_limit) if list_limit
    lists
  end

  def board_members(board)
    if @board_members.include?(board.id)
      @board_members[board.id]
    else
      trello_do('board_members') do
        members = target(board.members)
        members.each do |member|
          add_member(member, board)
        end
        return members
      end
    end
  end

  def epic_list_names
    roadmap_board_lists || ['Epic Backlog', 'Card Groups']
  end

  def epic_lists(board)
    lists = []
    target_boards = epic_list_names
    board_lists(board).each do |l|
      if target_boards.include?(l.name)
        lists.push(l)
      end
    end
    lists
  end

  def dependent_work_board_ids
    @dependent_work_board_ids ||= if !dependent_work_boards
      [] # can't iterate over nil
    else
      dependent_work_boards.keys + teams.select { |k, v| v.include? :dependent_work_boards }.map { |t, v| v[:dependent_work_boards].keys }.flatten
    end
  end

  def next_dependent_work_list(board_id = dependent_work_board.id, new_list_name = 'New')
    unless @next_dependent_work_list[board_id]
      board_lists(boards[board_id]).each do |l|
        if l.name == new_list_name
          @next_dependent_work_list[board_id] = l
          break
        end
      end
    end
    @next_dependent_work_list[board_id]
  end

  def checklist(card, checklist_name)
    checklists = list_checklists(card)
    checklists.each do |checklist|
      if checklist.name == checklist_name
        return checklist
      end
    end
    nil
  end

  def checklist_add_item(cl, item_name, checked, position)
    retry_count = 0
    item_updated = false
    while not item_updated
      begin
        cl.add_item(item_name, checked, position)
        item_updated = true
      rescue Exception => e
        $stderr.puts "Error in checklist_add_item: #{e.message}"
        trello_do('checklist_add_item') do
          cl = Trello::Checklist.find(cl.id)
        end
        break unless cl.items.select { |i| i.name.strip == item_name && i.complete? == checked }.one?
        raise if retry_count >= DEFAULT_RETRIES
        retry_sleep retry_count
        retry_count += 1
      end
    end
  end

  def checklist_delete_item(cl, item)
    retry_count = 0
    item_updated = false
    while not item_updated
      begin
        cl.delete_checklist_item(item.id)
        item_updated = true
      rescue Exception => e
        $stderr.puts "Error in checklist_delete_item: #{e.message}"
        trello_do('checklist_delete_item') do
          cl = Trello::Checklist.find(cl.id)
        end
        break if cl.items.select { |i| i.id == item.id }.empty?
        raise if retry_count >= DEFAULT_RETRIES
        retry_sleep retry_count
        retry_count += 1
      end
    end
  end

  def clear_epic_refs(epic_card)
    checklists = list_checklists(epic_card)
    checklists.each do |cl|
      clear_checklist_epic_refs(cl)
    end
  end

  def clear_checklist_epic_refs(cl)
    cl.items.each do |item|
      if item.name =~ EPIC_REF_REGEX
        begin
          checklist_delete_item(cl, item)
        rescue => e
          $stderr.puts "Error deleting checklist item: #{e.message}"
        end
      end
    end
  end

  def checklist_to_checklist_item_names(epic_card)
    checklist_to_cins = {}
    checklists = list_checklists(epic_card)
    checklists.each do |cl|
      cl.items.each do |item|
        if item.name =~ EPIC_REF_REGEX
          checklist_to_cins[cl.name] = [] unless checklist_to_cins[cl.name]
          checklist_to_cins[cl.name] << [item.name, item.complete?]
        end
      end
    end
    checklist_to_cins
  end

  def checklist_item_names(cl)
    cins = []
    if cl
      cl.items.each do |item|
        cins << item.name
      end
    end
    cins
  end

  def clear_checklist(cl)
    cl.items.each do |item|
      checklist_delete_item(cl, item)
    end
  end

  def create_checklist(card, checklist_name)
    retry_count = 0
    cl = checklist(card, checklist_name)
    puts "Adding #{checklist_name} to #{card.name} (#{card.id})" if cl.nil?
    while cl.nil?
      begin
        cl = Trello::Checklist.create(name: checklist_name, board_id: card.board_id, card_id: card.id)
        @checklists_by_card.delete(card.id)
        break
      rescue Exception => e
        $stderr.puts "Error in create_checklist: #{e.message}"
        @checklists_by_card.delete(card.id)
        cl = checklist(card, checklist_name)
        break unless cl.nil?
        raise if retry_count >= DEFAULT_RETRIES
        retry_sleep retry_count
        retry_count += 1
      end
    end
    cl
  end

  def update_roadmap
    releases = []
    roadmap_label_colors_by_name.each_key do |label_name|
      if label_name =~ RELEASE_LABEL_REGEX
        releases << label_name
      end
    end
    roadmap_tag_to_epics = tag_to_epics
    update_roadmaps(ROADMAP, roadmap_boards, boards, releases, roadmap_tag_to_epics)
    teams.each do |team, team_map|
      team_boards_map = team_boards_map(team_map)
      team_boards = {}
      team_boards_map.each do |b_name, b_id|
        team_boards[b_id] = boards[b_id]
      end
      update_roadmaps(team, team_boards.values, team_boards, releases, roadmap_tag_to_epics, false, false)
    end
  end

  def update_roadmaps(team_name, rm_boards, team_boards, releases, roadmap_tag_to_epics, include_accepted = true, include_board_name_in_epic = true)
    t_to_epics = tag_to_epics(rm_boards)
    tags_without_epics = {}
    rm_boards.each do |roadmap_board|
      epic_lists = epic_lists(roadmap_board)
      tag_to_epic = {}
      epic_lists.each do |epic_list|
        list_cards(epic_list).each do |epic_card|
          #rename_checklist(epic_card, "Scenarios", UNASSIGNED_RELEASE)
          #rename_checklist(epic_card, "Future Scenarios", FUTURE_RELEASE)
          epic_tags = {}
          card_labels(epic_card).each do |label|
            if label.name.start_with? 'epic-'
              tag_to_epic[label.name] = epic_card
              epic_tags[label.name] = true
            end
          end
          epic_card.name.scan(EPIC_TAG_REGEX).each do |tag|
            tag.downcase!
            if tag != FUTURE_TAG
              tag_to_epic[tag] = epic_card
              epic_tags[tag] = true
            end
          end
          unless team_name == ROADMAP
            global_epics_to_link = {}
            epic_tags.each_key do |tag|
              global_epic_cards = roadmap_tag_to_epics[tag]
              if global_epic_cards
                global_epic_cards.each do |global_epic_card|
                  global_roadmap_board = board(global_epic_card.board_id)
                  if roadmap_board.prefs['permissionLevel'] == 'org' || global_roadmap_board.prefs['permissionLevel'] == 'public'
                    global_epics_to_link[global_epic_card.short_url] = true unless epic_card.desc.include?(global_epic_card.short_url)
                  end
                end
              end
            end
            unless global_epics_to_link.empty?
              epic_card.desc = epic_card.desc + "\n\n" + global_epics_to_link.keys.map { |short_url| "Parent Epic: #{short_url}" }.join("\n")
              puts "Adding parent epic(s) to local epic: #{epic_card.short_url}"
              update_card(epic_card)
            end
          end
        end
      end
      puts 'Tags:'
      puts tag_to_epic.keys.pretty_inspect
      epic_stories_by_epic = {}
      (1..2).each do |accepted_pass|
        break if accepted_pass == 2 && !include_accepted
        team_boards.each do |board_id, board|
          if roadmap_board.prefs['permissionLevel'] == 'org' || (roadmap_board.prefs['permissionLevel'] == board.prefs['permissionLevel'])
            puts "\nBoard Name: #{board.name}"
            all_lists = board_lists(board)
            new_lists = []
            backlog_lists = []
            next_lists = []
            in_progress_lists = []
            complete_lists = []
            accepted_lists = []
            previous_sprint_lists = []
            other_lists = []
            all_lists.each do |l|
              if NEW_STATES.include?(l.name)
                new_lists << l
              elsif BACKLOG_STATES.include?(l.name)
                backlog_lists << l
              elsif NEXT_STATES.include?(l.name)
                next_lists << l
              elsif IN_PROGRESS_STATES.include?(l.name)
                in_progress_lists << l
              elsif COMPLETE_STATES.include?(l.name)
                complete_lists << l
              elsif ACCEPTED_STATES.include?(l.name)
                accepted_lists << l
              elsif l.name =~ SPRINT_REGEXES
                previous_sprint_lists << l
              elsif !epic_list_names.include?(l.name)
                other_lists << l
              end
            end

            accepted_lists.sort_by! { |l| ACCEPTED_STATES[l.name] }
            accepted_lists.reverse!
            complete_lists.sort_by! { |l| COMPLETE_STATES[l.name] }
            complete_lists.reverse!
            in_progress_lists.sort_by! { |l| IN_PROGRESS_STATES[l.name] }
            in_progress_lists.reverse!
            next_lists.sort_by! { |l| NEXT_STATES[l.name] }
            next_lists.reverse!
            backlog_lists.sort_by! { |l| BACKLOG_STATES[l.name] }
            backlog_lists.reverse!
            new_lists.sort_by! { |l| NEW_STATES[l.name] }
            new_lists.reverse!
            other_lists.sort_by! { |l| l.name }

            lists = accepted_lists + complete_lists + in_progress_lists + next_lists + backlog_lists + new_lists

            previous_sprint_lists = previous_sprint_lists.sort_by { |l| [l.name =~ SPRINT_REGEXES ? $1.to_i : 9999999, $3 ? $3.to_i : $9.to_i, $5 ? $5.to_i : $10.to_i, $7 ? $7.to_i : $12.to_i, $14.to_i] }
            lists += previous_sprint_lists
            lists += other_lists
            lists.each do |list|
              accepted = list_for_completed_work?(list.name)
              next if (accepted && accepted_pass == 1) || (!accepted && accepted_pass == 2)
              cards = list_cards(list)
              if !cards.empty?
                puts "\n  List: #{list.name}  (#cards: #{cards.length})"
                cards.each_with_index do |card, index|
                  card_tags = []
                  card_labels = card_labels(card)
                  next_card_releases = []
                  card_releases = {}
                  card_labels.each do |label|
                    if label.name.start_with? 'epic-'
                      card_tags << label.name
                    elsif releases.include?(label.name)
                      RELEASE_LABEL_REGEX.match(label.name) do |fields|
                        state = fields[1]
                        product = fields[2]
                        release = fields[3]
                        major = fields[4].to_i
                        minor = fields[5].to_i
                        patch = fields[6].to_i
                        hotfix = fields[7].to_i

                        card_releases[product] = [] unless card_releases[product]
                        card_releases[product] << [label, state, release, major, minor, patch, hotfix]
                      end
                    end
                  end

                  unless card_releases.empty?
                    card_releases.each do |product, product_card_releases|
                      if product_card_releases.length > 1
                        product_card_releases.sort_by! { |release| [release[3], release[4], release[5], release[6], RELEASE_STATE_ORDER[release[1]]] }
                        first_release = product_card_releases.first
                        previous_release = first_release[2]
                        lowest_state_order = RELEASE_STATE_ORDER[first_release[1]]
                        product_card_releases[1..-1].each do |release|
                          state_order = RELEASE_STATE_ORDER[release[1]]
                          if previous_release == release[2] || lowest_state_order <= state_order
                            label = release[0]
                            puts "Removing lower priority release #{label.name} from #{card.name} (#{card.url})"
                            card.remove_label(label)
                          end
                          lowest_state_order = state_order if state_order < lowest_state_order
                          previous_release = release[2]
                        end
                      end
                      next_card_releases << product_card_releases.first[0].name
                    end
                  end

                  marker_card_tags = card.name.scan(EPIC_TAG_REGEX)
                  marker_card_tags.each { |tag| tag.downcase! }
                  marker_card_tags.delete_if { |tag| card_tags.include?("epic-#{tag[1..-2]}") }
                  checklist_name = (marker_card_tags.include?(FUTURE_TAG) || card_labels.map { |l| l.name }.include?(FUTURE_LABEL)) ? FUTURE_RELEASE : UNASSIGNED_RELEASE
                  card_tags += marker_card_tags

                  card_tags << '[none]' if card_tags.empty?

                  card_tags.each do |card_tag|
                    epic = tag_to_epic[card_tag]
                    if epic
                      if (roadmap_board.prefs['permissionLevel'] == 'org' && t_to_epics[card_tag].length == 1) || (roadmap_board.prefs['permissionLevel'] == board.prefs['permissionLevel'])
                        epic_stories_by_epic[epic.id] = [] unless epic_stories_by_epic[epic.id]
                        epic_stories_by_epic[epic.id] << [epic, card, list, board, checklist_name, accepted, next_card_releases]
                      end
                    else
                      tags_without_epics[card_tag] = true unless roadmap_tag_to_epics[card_tag] || team_name == ROADMAP
                    end
                  end
                end
              end
            end
          end
        end
        puts "\n#{team_name.upcase} tags without a corresponding epic: #{tags_without_epics.keys.join(', ')}" unless team_name == ROADMAP
        none_epic_card = tag_to_epic['[none]']
        if none_epic_card
          tags_without_epics_checklist = nil
          if tags_without_epics.empty?
            tags_without_epics_checklist = checklist(none_epic_card, NONE_CHECKLIST_NAME)
          else
            tags_without_epics_checklist = create_checklist(none_epic_card, NONE_CHECKLIST_NAME)
          end

          tags_without_epics_keys = tags_without_epics.keys
          tags_without_epics_keys.sort_by! { |tag| tag }

          if checklist_item_names(tags_without_epics_checklist) != tags_without_epics_keys
            clear_checklist(tags_without_epics_checklist)
            tags_without_epics_keys.each do |tag|
              checklist_add_item(tags_without_epics_checklist, tag, false, 'bottom')
            end
          end
        end
      end

      epic_lists.each do |epic_list|
        list_cards(epic_list).each do |epic_card|
          unless epic_stories_by_epic[epic_card.id]
            clear_epic_refs(epic_card)
          end
        end
      end
      epic_stories_by_epic.each_value do |epic_stories|
        first_epic_story = epic_stories.first
        if first_epic_story
          epic_card = first_epic_story[0]
          checklist_to_cins = {}
          epic_stories.each do |epic_story|
            card = epic_story[1]
            list = epic_story[2]
            board = epic_story[3]
            checklist_name = epic_story[4]
            accepted = epic_story[5]
            next_card_releases = epic_story[6]

            cin = checklist_item_name(card, list, board, include_board_name_in_epic)

            if !next_card_releases.empty?
              next_card_releases.each do |card_release|
                checklist_to_cins[card_release] = [] unless checklist_to_cins[card_release]
                checklist_to_cins[card_release] << [cin, accepted]
              end
            else
              checklist_to_cins[checklist_name] = [] unless checklist_to_cins[checklist_name]
              checklist_to_cins[checklist_name] << [cin, accepted]
            end
          end

          puts "\nAdding cards to #{epic_card.name}:"

          existing_checklist_to_cins = checklist_to_checklist_item_names(epic_card)
          existing_checklist_to_cins.each do |checklist_name, cins|
            if cins == checklist_to_cins[checklist_name]
              puts "#{checklist_name} is unchanged"
              checklist_to_cins.delete(checklist_name)
            elsif checklist_to_cins[checklist_name]
              puts "#{checklist_name} is changed"
            else
              puts "#{checklist_name} has no valid epic refs"
              clear_checklist_epic_refs(checklist(epic_card, checklist_name))
            end
          end

          checklist_to_cins.each do |checklist_name, cins|
            cl = create_checklist(epic_card, checklist_name)
            clear_checklist_epic_refs(cl)
            cins.each do |cin_info|
              cin = cin_info[0]
              accepted = cin_info[1]
              puts "Adding #{cin} to #{checklist_name}"
              checklist_add_item(cl, cin, accepted, 'bottom')
            end
          end
        end
      end

      # Delete empty epic checklists
      epic_lists.each do |epic_list|
        list_cards(epic_list).each do |epic_card|
          delete_empty_epic_checklists(epic_card)
        end
      end
    end
  end

  def rename_checklist(card, old_checklist_name, new_checklist_name)
    cl = checklist(card, old_checklist_name)
    if cl
      puts "Renaming #{old_checklist_name} on #{new_checklist_name}"
      cl.name = new_checklist_name
      cl.save
    end
    cl
  end

  def delete_empty_epic_checklists(epic_card)
    checklists = list_checklists(epic_card)
    checklists.each do |cl|
      if cl.items.empty?
        delete_checklist(cl, epic_card)
      end
    end
  end

  def delete_checklist(cl, card)
    begin
      trello_do('checklist') do
        cl.delete
        @checklists_by_card.delete(card.id)
      end
    rescue => e
      $stderr.puts "Error deleting checklist: #{e.message}"
    end
  end

  def target(ref, name = 'target')
    trello_do(name) do
      t = ref.target
      return t
    end
  end

  def card_labels(card)
    labels = @labels_by_card[card.id]
    return labels if labels
    labels = card.card_labels.map do |label|
      Trello::Label.new(label)
    end
    @labels_by_card[card.id] = labels if labels
    labels
  end

  def card_list(card)
    list = @list_by_card[card.id]
    return list if list
    trello_do('card_list') do
      list = card.list
    end
    @list_by_card[card.id] = list if list
    list
  end

  def card_comment_actions(card)
    if @comment_actions_by_card.include?(card.id)
      actions = @comment_actions_by_card[card.id]
    else
      trello_do('card.actions(commentCard)') do
        actions = card.actions(options={filter: 'commentCard'})
      end
      @comment_actions_by_card[card.id] = actions
    end
    actions
  end

  def card_members(card)
    members = @members_by_card[card.id]
    # If the list we get doesn't match the card, refresh
    if members.size != card.member_ids.size
      add_card(card)
      members = @members_by_card[card.id]
    end
    members
  end

  def create_missing_member(member_id)
    Trello::Member.new({'id' => member_id, 'username' => 'deleted_account', 'fullName' => 'deleted account'})
  end

  def action_member_creator(action)
    member = nil
    if !(member = members_by_id[action.member_creator_id])
      trello_do("action.member_creator") do
        begin
          member = action.member_creator
        rescue Trello::Error => e
          if e.message =~ /The requested resource was not found/ # 404
            member = create_missing_member(action.member_creator_id)
          end
        end
      end
    end
    add_member(member)
  end

  def board_labels(board)
    labels = nil
    label_limit = 1000
    trello_do('board_labels') do
      labels = board.labels(limit: label_limit)
    end
    raise "Reached label API limit of 1000 entries" if labels.length >= label_limit
    labels
  end

  def create_label(name, color, board_id)
    Trello::Label.create(name: name, color: color, board_id: board_id)
  end

  def update_label(label)
    trello_do('update_label') do
      label.save
    end
  end

  def delete_label(label)
    trello_do('delete_label') do
      label.delete
    end
  end

  def add_label_to_card(card, label, retry_on_error = true)
    begin
      trello_do('add_label_to_card', retry_on_error ? 2 : 0) do
        card.add_label(label)
      end
    rescue
    end
  end

  def remove_label_from_card(card, label, retry_on_error = true)
    begin
      trello_do('remove_label_from_card', retry_on_error ? 2 : 0) do
        card.remove_label(label)
      end
    rescue
    end
  end

  def update_card(card)
    trello_do('update_card') do
      card.save
    end
  end

  def list_for_completed_work?(list_name)
    # !! ensures boolean value for feeding to API
    !!(ACCEPTED_STATES.include?(list_name) || list_name =~ SPRINT_REGEXES)
  end

  def list_for_in_progress_work?(list_name)
    # !! ensures boolean value for feeding to API
    !!CURRENT_SPRINT_NOT_ACCEPTED_STATES.include?(list_name)
  end

  def list_checklists(card)
    checklists = @checklists_by_card[card.id]
    return checklists if checklists
    trello_do('checklists') do
      checklists = card.checklists
    end
    if checklists
      checklists = target(checklists, 'checklists')
      @checklists_by_card[card.id] = checklists
    end
    checklists
  end

  def list_cards(list)
    cards = @cards_by_list[list.id]
    return cards if cards
    trello_do('cards') do
      cards = list.cards
    end
    if cards
      cards = target(cards, 'cards')
      cards.each { |card| add_card(card) }
    end
    cards
  end

  def list_actions(card)
    actions = nil
    trello_do('actions') do
      actions = card.actions
    end
    if actions
      actions = target(actions, 'actions')
    end
    actions
  end

  def list_comments(card)
    comments = @comments_by_card[card.id]
    return comments if comments
    actions = list_actions(card)
    comments = []
    actions.each do |action|
      if action.type == 'commentCard'
        comments << action.data['text']
      end
    end
    @comments_by_card[card.id] = comments
    comments
  end

  def print_card(card, num = nil)
    print "     "
    print "#{num}) " if num
    puts "#{card.name} (##{card.short_id})"
    members = card_members(card)
    if !members.empty?
      puts "       Assignee(s): #{members.map { |member| member.full_name }.join(', ')}"
    end
    puts "\nActions:\n\n"
    list_actions(card).each do |action|

      if action.type == 'updateCard'
        field = action.data['old'].keys.first
        if ['desc', 'pos', 'name'].include?(field)
          list_name = action.data['list']['name']
          puts "#{action_member_creator(action).username} (#{list_name}):"
          puts "    New #{field}: #{action.data['card'][field]}"
          puts "    Old #{field}: #{action.data['old'][field]}"
          puts "===============================================\n\n"
        end
      elsif action.type == 'createCard'
        list_name = action.data['list']['name']
        puts "#{action_member_creator(action).username} added to #{list_name}"
        puts "    Name: #{action.data['card']['name']}"
      end
    end
  end

  def print_list(list)
    cards = list_cards(list)
    if !cards.empty?
      puts "\n  List: #{list.name}  (#cards #{cards.length})"
      puts "    Cards:"
      cards.each_with_index do |card, index|
        print_card(card, index + 1)
      end
    end
  end

  def print_labels(board = roadmap_board)
    label_names = board_labels(board).map { |l| l.name }
    puts "\n  Board: #{board.name}  (#labels #{label_names.length})"
    puts "    Labels:"
    label_names.sort.each { |n| puts "      #{n}" }
  end

  def card_by_ref(card_ref)
    card = nil
    if card_ref =~ /^(\w+)_(\d+)/i
      board_name = $1
      card_short_id = $2
      board = team_board(board_name)
      card = find_card_by_short_id(board, card_short_id)
    end
    card
  end

  def card_by_url(card_url)
    card = nil
    # https://trello.com/c/6EhPEbM4
    if card_url =~ /^https?:\/\/trello\.com\/c\/([[:alnum:]]+)/
      card_id = $1
      card = find_card(card_id)
    end
    card
  end

  def org
    @org || trello_do('org') do
      @org = Trello::Organization.find(organization_id)
      return @org
    end
  end

  def org_boards
    @org_boards || trello_do('org_boards') do
      @org_boards = target(org.boards)
      return @org_boards
    end
  end

  def org_members
    @org_members || trello_do('org_members') do
      @org_members = target(org.members)
      @org_members.each { |member| add_member(member) }
      return @org_members
    end
  end

  def members_by_id
    org_members if !@org_members # Make sure at least the organization
                                 # members are populated
    @members_by_id
  end

  def board(board_id)
    b = boards[board_id]
    unless b
      if board_id == public_roadmap_id
        b = public_roadmap_board
      elsif board_id == roadmap_id
        b = roadmap_board
      end
    end
    b
  end

  def release_cards(product, release)
    release_cards = {}
    search_list_info = []
    teams.each do |team_name, team_map|
      team_name = team_name.to_s
      team_boards(team_name).each do |board|
        board_lists(board).each do |list|
          search_list_info << [team_name, board, list]
        end
      end
    end

    roadmap_boards.each do |board|
      board_lists(board).each do |list|
        if NEW_STATES.include?(list.name)
          search_list_info << [ROADMAP, board, list]
          break
        end
      end
    end

    search_list_info.each do |list_info|
      team_name = list_info[0]
      list = list_info[2]
      cards = list_cards(list)
      cards.each_with_index do |card, index|
        labels = card_labels(card)
        label_names = labels.map { |label| label.name }
        label_names.each do |label_name|
          RELEASE_LABEL_REGEX.match(label_name) do |fields|
            if product == fields[2] && release == fields[3]
              state = fields[1]
              release_cards[card.id] = {
                short_url: card.short_url,
                name: card.name,
                team_name: team_name,
                state: state
              }
            end
          end
        end
      end
    end
    release_cards
  end

  def release_cards_history(product, release)
    release_cards_history_file = File.join('config', 'releases', "#{product ? product + '-' : '' }#{release}.json")
    release_cards_history = nil
    release_cards_history = JSON.parse(File.read(release_cards_history_file)) if File.exist?(release_cards_history_file)
    release_cards_history
  end

  def state_title(state, product, release)
    title = nil
    product_release = ((product.nil? || product.empty?) ? '' : "#{product}-") + release
    if state == 'committed'
      title = "Committed in plan to be delivered (i.e. label=committed-#{product_release}) and/or already complete (i.e. card is in an Accepted list or after on a team board, even if card was originally targeted or proposed)"
    elsif state == 'targeted'
      title = "Targeted to be delivered (i.e. label=targeted-#{product_release}) but not yet complete (i.e. card hasn't made it to the Accepted list or after on a team board)"
    else
      title = "Proposed to be delivered (i.e. label=proposed-#{product_release}) and awaiting approval"
    end
    title
  end

  ##
  # Do the same thing as Trello::Net.execute_core, but with adjustable
  # timeout
  #
  # * +request+ A Trello::Request object. This should probably be
  #   passed through Trello.auth_policy.authorize first.
  # * +timeout+ Time to wait for response in seconds. Passed to
  #   RestClient::Request.execute
  #
  def long_request_execute(request, timeout=30)
    RestClient.proxy = ENV['HTTP_PROXY'] if ENV['HTTP_PROXY']
    result = RestClient::Request.execute(
      method: request.verb,
      url: request.uri.to_s,
      headers: request.headers,
      payload: request.body,
      timeout: timeout
    )
    return Trello::Response.new(200, {}, result)
  end


  ##
  # Return the JSON backup of the Trello org
  def dump_org_members_json()
    $stderr.puts("Backing up Organization Members for #{org.display_name} (#{org.name})...")
    api_call_uri = Addressable::URI.parse("https://trello.com/1/organizations/#{organization_id}/members")
    api_call_uri.query_values = { fields: 'all' }

    i = 0
    request_timeout = 30
    while true
      request = Trello::Request.new :get, api_call_uri, {}, nil
      begin
        response = long_request_execute(Trello.auth_policy.authorize(request), request_timeout)
        return response.body if response.code == 200
      rescue RestClient::RequestTimeout => e
        err_msg = "Error with dump_org_json backing up org '#{org.name}' using API call: " + (e.http_code.nil? ? "HTTP Timeout?" : "HTTP response code: #{e.http_code}, response body: #{e.http_body}")
      end
      if i >= DEFAULT_RETRIES
        raise err_msg
      end
      $stderr.puts err_msg
      retry_sleep i
      request_timeout += 15
      i += 1
    end
  end


  ##
  # Return the JSON backup of the Trello org
  def dump_org_json()
    $stderr.puts("Backing up Organization content for #{org.display_name} (#{org.name})...")
    api_call_uri = Addressable::URI.parse("https://trello.com/1/organizations/#{organization_id}")
    api_call_uri.query_values = { fields: 'all' }

    i = 0
    request_timeout = 30
    while true
      request = Trello::Request.new :get, api_call_uri, {}, nil
      begin
        response = long_request_execute(Trello.auth_policy.authorize(request), request_timeout)
        return response.body if response.code == 200
      rescue RestClient::RequestTimeout => e
        err_msg = "Error with dump_org_json backing up org '#{org.name}' using API call: " + (e.http_code.nil? ? "HTTP Timeout?" : "HTTP response code: #{e.http_code}, response body: #{e.http_body}")
      end
      if i >= DEFAULT_RETRIES
        raise err_msg
      end
      $stderr.puts err_msg
      retry_sleep i
      request_timeout += 15
      i += 1
    end
  end


  ##
  # Return the JSON backup of +board+
  def dump_board_json(board)
    $stderr.puts("Backing up board #{board.name}...")

    # This can take a Trello::Board or a board ID
    board = board(board) unless board.respond_to? :id

    # Yes, we have to try two different URL schemes because one works
    # for some boards, one works for others, and then we STILL get to
    # fall back to the API call if neither work. :/
    board_json_url = board.url.gsub(/\/[^\/]+$/, '.json')
    board_json_other_url = "#{board.url}.json"

    # API request to pull down the same content as the export URL, but limited to 100 actions
    api_call_uri = Addressable::URI.parse("https://trello.com/1/boards/#{board.id}")
    api_call_uri.query_values = { fields: 'all',
                                  actions: 'all',
                                  actions_limit: '1000',
                                  action_fields: 'all',
                                  cards: 'all',
                                  card_fields: 'all',
                                  card_attachments: 'true',
                                  labels: 'all',
                                  lists: 'all',
                                  list_fields: 'all',
                                  members: 'all',
                                  member_fields: 'all',
                                  checklists: 'all',
                                  checklist_fields: 'all',
                                  organization: 'false' }
    i = 0
    request_timeout = 30
    while true
      request = Trello::Request.new :get, board_json_url, {}, nil
      response = nil
      begin
        response = long_request_execute(Trello.auth_policy.authorize(request), request_timeout)
        return response.body if response.code == 200
      rescue RestClient::RequestTimeout => e
        err_msg = "Error with dump_board_json backing up board '#{board.name}' at URL #{request.uri}: " + (e.http_code.nil? ? "HTTP Timeout?" : "HTTP response code: #{e.http_code}, response body: #{e.http_body}")
        $stderr.puts err_msg
      end
      request = Trello::Request.new :get, board_json_other_url, {}, nil
      begin
        response = long_request_execute(Trello.auth_policy.authorize(request), request_timeout)
        return response.body if response.code == 200
      rescue RestClient::RequestTimeout => e
        err_msg = "Error with dump_board_json backing up board '#{board.name}' at alternate URL #{request.uri}: " + (e.http_code.nil? ? "HTTP Timeout?" : "HTTP response code: #{e.http_code}, response body: #{e.http_body}")
        $stderr.puts err_msg
      end
      $stderr.puts "Retrying with API-based backup URL to work around failed request."
      request = Trello::Request.new :get, api_call_uri, {}, nil
      begin
        response = long_request_execute(Trello.auth_policy.authorize(request), request_timeout)
        return response.body if response.code == 200
      rescue RestClient::RequestTimeout => e
        err_msg = "Error with dump_board_json backing up board '#{board.name}' using all URL endpoints and API call: " + (e.http_code.nil? ? "HTTP Timeout?" : "HTTP response code: #{e.http_code}, response body: #{e.http_body}")
      end
      if i >= DEFAULT_RETRIES
        raise err_msg
      end
      $stderr.puts err_msg
      retry_sleep i
      request_timeout += 15
      i += 1
    end
  end

  def member(member_name)
    this_member = nil
    trello_do('member') do
      this_member = Trello::Member.find(member_name)
    end
    @members_by_id[this_member.id] = this_member
    this_member
  end

  def member_emails(members)
    unless @trello_login_to_email
      @trello_login_to_email = {}
      trello_login_to_email_json = File.expand_path('~/trello_login_to_email.json')
      if File.exist? trello_login_to_email_json
        @trello_login_to_email = JSON.parse(File.read(trello_login_to_email_json))
      end
    end
    member_emails = []
    members.each do |member|
      email = @trello_login_to_email[member.username]
      if email
        member_emails << email
      end
    end
    member_emails
  end

  def markdown_to_html(text)
    Kramdown::Document.new(text).to_html
  end

  def dependent_cards_by_board_id()
    return @dependent_cards_by_board_id if @dependent_cards_by_board_id
    @dependent_cards_by_board_id = {}
    dependent_work_board_ids.each do |board_id|
      dependent_cards = []
      lists = board_lists(dependent_work_board(board_id))
      lists.each do |list|
        cards = list_cards(list)
        if !cards.empty?
          puts "\n  List: #{list.name}  (#cards #{cards.length})"
          cards.each_with_index do |card, index|
            if !(card.name =~ SPRINT_REGEX && !card.due.nil?)
              dependent_cards << card
            end
          end
        end
      end
      @dependent_cards_by_board_id[board_id] = dependent_cards
    end
    @dependent_cards_by_board_id
  end

  def dependent_work_board_labels_by_name()
    return @dependent_work_board_labels_by_name if @dependent_work_board_labels_by_name
    @dependent_work_board_labels_by_name = {}
    dependent_work_board_ids.each do |dependent_work_board_id|
      dependent_work_board_labels = target(board_labels(boards[dependent_work_board_id]))
      @dependent_work_board_labels_by_name[dependent_work_board_id] = {}
      dependent_work_board_labels.each do |board_label|
        @dependent_work_board_labels_by_name[dependent_work_board_id][board_label.name] = board_label
      end
    end
    @dependent_work_board_labels_by_name
  end

  def add_dependent_cards(card, dependent_work_board_id, params, label_names, team_map)
    if label_names.include?(params[:label]) && dependent_cards_by_board_id.include?(dependent_work_board_id) && !team_map[:exclude_from_dependent_work_board]
      dependent_card = nil
      dependent_cards_by_board_id[dependent_work_board_id].each do |d_card|
        if d_card.desc.include?(card.short_url)
          dependent_card = d_card
          break
        end
      end
      unless dependent_card
        name = card.name
        if card.name =~ CARD_NAME_REGEX
          name = $3.strip
        end
        # Update the next list on the appropriate dependent work board
        dependent_card = Trello::Card.create(name: "#{params[:card_name_prefix]}: #{name}", desc: "#{params[:card_desc_prefix]}: #{card.short_url}", list_id: next_dependent_work_list(dependent_work_board_id, params[:new_list_name]).id)
      end
      # Sync release labels from the dev card to the dependent work card
      # TODO Make this configurable?
      release_labels = []
      label_names.each do |label_name|
        if label_name =~ RELEASE_LABEL_REGEX
          release_labels << label_name
        end
      end
      dependent_card_labels = card_labels(dependent_card)
      dependent_card_label_names = dependent_card_labels.map { |l| l.name }
      dependent_card_release_labels = []
      dependent_card_label_names.each do |dependent_card_label_name|
        if dependent_card_label_name =~ RELEASE_LABEL_REGEX
          dependent_card_release_labels << dependent_card_label_name
        end
      end
      labels_to_remove = dependent_card_release_labels - release_labels
      labels_to_add = release_labels - dependent_card_release_labels
      labels_to_remove.each do |label_name|
        label = dependent_work_board_labels_by_name[dependent_work_board_id][label_name]
        if label
          puts "Removing #{label_name} from #{dependent_card.name} (#{dependent_card.url})"
          remove_label_from_card(dependent_card, label, false)
        end
      end
      labels_to_add.each do |label_name|
        label = dependent_work_board_labels_by_name[dependent_work_board_id][label_name]
        if label
          puts "Adding #{label_name} to #{dependent_card.name} (#{dependent_card.url})"
          add_label_to_card(dependent_card, label, false)
        end
      end
    end
  end

  def update_bug_tasks(card, bugzilla)
    ['Bugs', 'Tasks'].each do |cl|
      bugs_checklist = checklist(card, cl)
      if bugs_checklist
        bugs_checklist.items.each do |item|
          item_name = item.name.strip
          if item_name =~ BUGZILLA_REGEX
            bug_url = $1
            status = bugzilla.bug_status_by_url(bug_url)
            if status == 'VERIFIED' || status == 'CLOSED'
              if !item.complete?
                puts "Marking complete: #{item_name}"
                checklist_add_item(bugs_checklist, item_name, true, 'bottom')
                checklist_delete_item(bugs_checklist, item)
              end
            else
              if item.complete?
                puts "Marking incomplete: #{item_name}"
                checklist_add_item(bugs_checklist, item_name, false, 'top')
                checklist_delete_item(bugs_checklist, item)
              end
            end
          end
        end
      end
    end
  end

  def add_dependent_tasks_reminder(card, reminder, label)
    if card_labels(card).map { |l| l.name }.include?(label)
      tasks_checklist = checklist(card, 'Tasks')
      if tasks_checklist
        found = false
        tasks_checklist.items.each do |item|
          if item.name.include? reminder
            found = true
            break
          end
        end
        unless found
          puts "Adding dependent work reminder: #{card.name}"
          checklist_add_item(tasks_checklist, reminder, false, 'bottom')
        end
      end
    end
  end

  def update_card_checklists(card, label_names, add_task_checklists = false, add_bug_checklists = false)
    checklists = []
    checklists << 'Tasks' if add_task_checklists
    checklists << 'Bugs' if add_bug_checklists && !label_names.include?('no-qe')

    list_checklists(card).each do |checklist|
      checklists.delete(checklist.name)
      break if checklists.empty?
    end if !checklists.empty?

    if checklists.any?
      puts "Adding #{checklists.pretty_inspect.chomp} to #{card.name}"
      checklists.each do |checklist_name|
        create_checklist(card, checklist_name)
      end
    end
  end

  def trello_do(type, retries = DEFAULT_RETRIES)
    i = 0
    while true
      begin
        yield
        break
      rescue Exception => e
        $stderr.puts "Error with #{type}: #{e.message}"
        raise if i >= retries
        retry_sleep i
        i += 1
      end
    end
  end

  def retry_sleep(retry_count)
    sleep DEFAULT_RETRY_SLEEP + (DEFAULT_RETRY_INC * retry_count)
  end

  private

  def checklist_item_name(card, list, board, include_board_name_in_epic)
    cin = nil
    stars = ''
    card_labels = card_labels(card)
    card_labels.each do |label|
      if label.name =~ STAR_LABEL_REGEX
        star_level = $1.to_i
        stars = ' ' + (':star:' * star_level)
        break
      end
    end
    if include_board_name_in_epic
      cin = "[#{card.name}](#{card.url}) (#{list.name}) (#{board.name})#{stars}"
    else
      cin = "[#{card.name}](#{card.url}) (#{list.name})#{stars}"
    end
    cin
  end

  # Parse out sortable/prioritizable metadata from card label
  def sortable_card_label(label)
    label_data = @sortable_card_labels[label.name]
    if label_data.nil?
      TrelloHelper::RELEASE_LABEL_REGEX.match(label.name) do |fields|
        label_data = SortableCard.new()
        label_data.state = fields[1] if fields[1]
        label_data.product = fields[2] ? fields[2] : 'ocp'
        if fields[3]
          version = fields[3]
          version.gsub!(/^\D+/, "0.") # Normalize exotic versions
          version = version.scan(/\d+/).join('.') # Normalize exotic versions
          label_data.release = Gem::Version.new(version)
        end
        @sortable_card_labels[label.name] = label_data
      end
    end
    label_data
  end
end
