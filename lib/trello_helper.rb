require 'trello'

class TrelloHelper
  # Trello Config
  attr_accessor :consumer_key, :consumer_secret, :oauth_token, :oauth_token_secret, :teams,
                :documentation_id, :organization_id, :roadmap_board, :roadmap_id,
                :public_roadmap_id, :public_roadmap_board, :documentation_board,
                :documentation_next_list, :docs_planning_id, :organization_name,
                :sprint_length_in_weeks, :sprint_start_day, :sprint_end_day, :logo,
                :docs_new_list_name, :roadmap_board_lists

  attr_accessor :boards, :cards_by_list, :labels_by_card

  DEFAULT_RETRIES = 3
  DEFAULT_RETRY_SLEEP = 10

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
  end

  def board_ids(for_sprint_report=false)
    board_ids = []
    teams.each do |team, team_map|
      team_boards_map = team_boards_map(team_map)
      unless for_sprint_report && team_map[:exclude_from_sprint_report]
        team_boards_map.each do |b_name, b_id|
          board_ids << b_id
        end
      end
    end
    return board_ids
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

  def boards_for_sprint_report
    boards = {}
    org_boards.each do |board|
      if board_ids(true).include?(board.id)
        boards[board.id] = board
      end
    end
    boards
  end

  def documentation_board
    @documentation_board = Trello::Board.find(documentation_id) unless @documentation_board
    @documentation_board
  end

  def docs_planning_board
    unless @docs_planning_board
      if docs_planning_id
        @docs_planning_board = Trello::Board.find(docs_planning_id)
      else
        @docs_planning_board = documentation_board
      end
    end
    @docs_planning_board
  end

  def roadmap_board
    if roadmap_id
      @roadmap_board = Trello::Board.find(roadmap_id) unless @roadmap_board
    end
    @roadmap_board
  end

  def public_roadmap_board
    if public_roadmap_id
      @public_roadmap_board = Trello::Board.find(public_roadmap_id) unless @public_roadmap_board
    end
    @public_roadmap_board
  end

  def roadmap_boards
    rbs = []
    rbs << public_roadmap_board if public_roadmap_board
    rbs << roadmap_board if roadmap_board
    rbs
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
            if tag != '[future]' && !tag_to_epics["epic-#{tag[1..-2]}"]
              tag_to_epics[tag] = [] unless tag_to_epics[tag]
              tag_to_epics[tag] << epic_card
            end
          end
        end
      end
    end
    tag_to_epics
  end

  def board_lists(board, filter={})
    trello_do('lists') do
      lists = board.lists(filter)
      return lists
    end
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

  def clear_checklist_refs(card, checklist_name)
    cl = checklist(card, checklist_name)

    if cl
      cl.items.each do |item|
        if item.name =~ /\[.*\]\(https?:\/\/trello\.com\/[^\)]+\) \([^\)]+\) \([^\)]+\)/
          begin
            trello_do('checklist') do
              cl.delete_checklist_item(item.id)
            end
          rescue => e
            puts "Error deleting checklist: #{e.message}"
          end
        end
      end
    else
      puts "Adding #{checklist_name} to #{card.name}"
      cl = Trello::Checklist.create({:name => checklist_name, :board_id => roadmap_id})
      card.add_checklist(cl)
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
    list = nil
    trello_do('card_list') do
      list = card.list
    end
    list
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

  def list_checklists(card)
    checklists = nil
    trello_do('checklists') do
      checklists = card.checklists
    end
    checklists = target(checklists, 'checklists') if checklists
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

  def print_card(card, num=nil)
    print "     "
    print "#{num}) " if num
    puts "#{card.name} (##{card.short_id})"
    members = card.members
    if !members.empty?
      puts "       Assignee(s): #{members.map{|member| member.full_name}.join(',')}"
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
      card = board.find_card(card_short_id)
    end
    card
  end

  def card_by_url(card_url)
    card = nil
    # https://trello.com/c/6EhPEbM4
    if card_url =~ /^https?:\/\/trello\.com\/c\/([[:alnum:]]+)/
      card_id = $1
      begin
        card = Trello::Card.find(card_id)
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
    target(org.boards)
  end

  def board(board_id)
    boards[board_id]
  end

  def member(member_name)
    Trello::Member.find(member_name)
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
        puts "Error with #{type}: #{e.message}"
        raise if i >= retries
        sleep DEFAULT_RETRY_SLEEP
        i += 1
      end
    end
  end

end
