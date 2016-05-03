require 'trello'
require 'kramdown'

class TrelloHelper
  # Trello Config
  attr_accessor :consumer_key, :consumer_secret, :oauth_token, :oauth_token_secret, :teams,
                :documentation_id, :organization_id, :roadmap_board, :roadmap_id,
                :public_roadmap_id, :public_roadmap_board, :documentation_board,
                :documentation_next_list, :docs_planning_id, :organization_name,
                :sprint_length_in_weeks, :sprint_start_day, :sprint_end_day, :logo,
                :docs_new_list_name, :roadmap_board_lists, :max_lists_per_board,
                :current_release_labels, :default_product, :other_products,
                :sprint_card

  attr_accessor :boards, :trello_login_to_email, :cards_by_list, :labels_by_card, :list_by_card, :members_by_card, :checklists_by_card, :lists_by_board, :comments_by_card, :board_id_to_team_map

  DEFAULT_RETRIES = 3
  DEFAULT_RETRY_SLEEP = 10

  FUTURE_TAG = '[future]'
  FUTURE_LABEL = 'future'

  STAGE1_DEP_LABEL = 'stage1-dep'

  SPRINT_REGEX = /^Sprint (\d+)/
  DONE_REGEX = /^Done: ((\d+)\.(\d+)(.(\d+))?(.(\d+))?)/
  SPRINT_REGEXES = Regexp.union([SPRINT_REGEX, DONE_REGEX])

  ACCEPTED_STATES = {
    'Accepted' => true,
    'Done' => true
  }

  COMPLETE_STATES = {
    'Complete' => true
  }

  IN_PROGRESS_STATES = {
    'In Progress' => true,
    'Design' => true,
    'Pending Upstream' => true,
    'Pending Merge' => true
  }

  NEXT_STATES = {
    'Stalled' => true,
    'Next' => true
  }

  BACKLOG_STATES = {
    'Backlog' => true
  }

  NEW_STATES = {
    'New' => true
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

  def initialize(opts)
    opts.each do |k,v|
      send("#{k}=",v)
    end

    Trello.configure do |config|
      config.consumer_key = @consumer_key
      config.consumer_secret = @consumer_secret
      config.oauth_token = @oauth_token
      config.oauth_token_secret = @oauth_token_secret
    end

    @cards_by_list = {}
    @labels_by_card = {}
    @list_by_card = {}
    @members_by_card = {}
    @checklists_by_card = {}
    @lists_by_board = {}
    @comments_by_card = {}
  end

  def board_ids
    board_ids = []
    teams.each do |team, team_map|
      team_boards_map = team_boards_map(team_map)
      team_boards_map.each do |b_name, b_id|
        board_ids << b_id
      end
    end
    return board_ids
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
    return "#{board_name}_#{card.short_id}"
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
    return team_boards_map
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

  def documentation_board
    @documentation_board = find_board(documentation_id) unless @documentation_board
    @documentation_board
  end

  def docs_planning_board
    unless @docs_planning_board
      if docs_planning_id
        @docs_planning_board = find_board(docs_planning_id)
      else
        @docs_planning_board = documentation_board
      end
    end
    @docs_planning_board
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

  def find_card(card_id)
    trello_do('find_card') do
      return Trello::Card.find(card_id)
    end
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

  def tag_to_epics
    tag_to_epics = {}
    roadmap_boards.each do |roadmap_board|
      epic_lists = epic_lists(roadmap_board)
      epic_lists.each do |epic_list|
        list_cards(epic_list).each do |epic_card|
          card_labels(epic_card).each do |label|
            if label.name.start_with? 'epic-'
              tag_to_epics[label.name] = [] unless tag_to_epics[label.name]
              tag_to_epics[label.name] << epic_card
            end
          end
          epic_card.name.scan(/\[[^\]]+\]/).each do |tag|
            if tag != FUTURE_TAG && !tag_to_epics["epic-#{tag[1..-2]}"]
              tag_to_epics[tag] = [] unless tag_to_epics[tag]
              tag_to_epics[tag] << epic_card
            end
          end
        end
      end
    end
    tag_to_epics
  end

  def board_lists(board, list_limit=max_lists_per_board)
    lists = nil
    lists = @lists_by_board[board.id] if max_lists_per_board.nil? || (list_limit && list_limit <= max_lists_per_board)
    unless lists
      trello_do('lists') do
        lists = board.lists(:filter => [:all])
        lists = lists.delete_if{ |list| list.name !~ TrelloHelper::SPRINT_REGEXES && list.closed? }
        lists.sort_by!{ |list| [list.name =~ TrelloHelper::SPRINT_REGEXES ? ($1.to_i) : 9999999, $3.to_i, $4.to_i, $6.to_i, $8.to_i]}
        lists.reverse!
      end
    end
    @lists_by_board[board.id] = lists if ((list_limit && max_lists_per_board && (list_limit >= max_lists_per_board)) || list_limit.nil?) && !@lists_by_board[board.id]
    lists = lists.first(list_limit) if list_limit
    return lists
  end

  def epic_lists(board)
    lists = []
    target_boards = roadmap_board_lists || ['Epic Backlog']
    board_lists(board).each do |l|
      if target_boards.include?(l.name)
        lists.push(l)
      end
    end
    lists
  end

  def documentation_next_list
    unless @documentation_next_list
      new_list_name = docs_new_list_name || 'Next Sprint'
      board_lists(docs_planning_board).each do |l|
        if l.name == new_list_name
          @documentation_next_list = l
          break
        end
      end
    end
    @documentation_next_list
  end

  def checklist(card, checklist_name)
    checklists = list_checklists(card)
    checklists.each do |checklist|
      if checklist.name == checklist_name
        return checklist
      end
    end
    return nil
  end

  def clear_epic_refs(epic_card)
    checklists = list_checklists(epic_card)
    checklists.each do |cl|
      cl.items.each do |item|
        if item.name =~ /\[.*\]\(https?:\/\/trello\.com\/[^\)]+\) \([^\)]+\) \([^\)]+\)/
          begin
            trello_do('checklist', 2) do
              cl.delete_checklist_item(item.id)
            end
          rescue => e
            $stderr.puts "Error deleting checklist item: #{e.message}"
          end
        end
      end
    end
    create_checklist(epic_card, UNASSIGNED_RELEASE)
    create_checklist(epic_card, FUTURE_RELEASE)
  end

  def create_checklist(card, checklist_name)
    retry_count = 0
    cl = checklist(card, checklist_name)
    puts "Adding #{checklist_name} to #{card.name}" if cl.nil?
    while cl.nil?
      begin
        cl = Trello::Checklist.create({:name => checklist_name, :board_id => card.board_id, :card_id => card.id})
        @checklists_by_card.delete(card.id)
        break
      rescue Exception => e
        $stderr.puts "Error in create_checklist: #{e.message}"
        @checklists_by_card.delete(card.id)
        cl = checklist(card, checklist_name)
        break unless cl.nil?
        raise if retry_count >= DEFAULT_RETRIES
        sleep DEFAULT_RETRY_SLEEP
        retry_count += 1
      end
    end
    cl
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
      next if [UNASSIGNED_RELEASE, FUTURE_RELEASE].include? cl.name
      if cl.items.empty?
        begin
          trello_do('checklist') do
            cl.delete
            @checklists_by_card.delete(epic_card.id)
          end
        rescue => e
          $stderr.puts "Error deleting checklist: #{e.message}"
        end
      end
    end
  end

  def target(ref, name='target')
    trello_do(name) do
      t = ref.target
      return t
    end
  end

  def card_labels(card)
    labels = @labels_by_card[card.id]
    return labels if labels
    trello_do('card_labels') do
      labels = card.labels
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

  def card_members(card)
    members = @members_by_card[card.id]
    return members if members
    trello_do('card_members') do
      members = card.members
    end
    @members_by_card[card.id] = members if members
    members
  end

  def board_labels(board)
    labels = nil
    label_limit = 1000
    trello_do('board_labels') do
      labels = board.labels(:limit => label_limit)
    end
    raise "Reached label API limit of 1000 entries" if labels.length >= label_limit
    labels
  end

  def create_label(name, color, board_id)
    Trello::Label.create(:name => name, :color => color, :board_id => board_id)
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
      @cards_by_list[list.id] = cards
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

  def print_card(card, num=nil)
    print "     "
    print "#{num}) " if num
    puts "#{card.name} (##{card.short_id})"
    members = card_members(card)
    if !members.empty?
      puts "       Assignee(s): #{members.map{|member| member.full_name}.join(', ')}"
    end
    puts "\nActions:\n\n"
    list_actions(card).each do |action|

      if action.type == 'updateCard'
        field = action.data['old'].keys.first
        if ['desc', 'pos', 'name'].include?(field)
          list_name = action.data['list']['name']
          puts "#{action.member_creator.username} (#{list_name}):"
          puts "    New #{field}: #{action.data['card'][field]}"
          puts "    Old #{field}: #{action.data['old'][field]}"
          puts "===============================================\n\n"
        end
      elsif action.type == 'createCard'
          list_name = action.data['list']['name']
          puts "#{action.member_creator.username} added to #{list_name}"
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
        print_card(card, index+1)
      end
    end
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
      begin
        card = find_card(card_id)
      rescue
      end
    end
    card
  end

  def org
    trello_do('org') do
      @org ||= Trello::Organization.find(organization_id)
      return @org
    end
  end

  def org_boards
    trello_do('org_boards') do
      return target(org.boards)
    end
  end

  def board(board_id)
    boards[board_id]
  end

  def member(member_name)
    Trello::Member.find(member_name)
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

  def trello_do(type, retries=DEFAULT_RETRIES)
    i = 0
    while true
      begin
        yield
        break
      rescue Exception => e
        $stderr.puts "Error with #{type}: #{e.message}"
        raise if i >= retries
        sleep DEFAULT_RETRY_SLEEP
        i += 1
      end
    end
  end

end
