require 'trello'

class TrelloHelper
  # Trello Config
  attr_accessor :consumer_key, :consumer_secret, :oauth_token, :oauth_token_secret, :teams,
                :documentation_id, :organization_id, :roadmap_board, :roadmap_id,
                :public_roadmap_id, :public_roadmap_board, :documentation_board,
                :documentation_next_list, :docs_planning_id, :organization_name,
                :sprint_length_in_weeks, :sprint_start_day, :sprint_end_day, :logo,
                :docs_new_list_name

  attr_accessor :boards

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
  end

  def board_ids
    board_ids = []
    teams.each do |team, team_boards_map|
      team_boards_map.each do |b_name, b_id|
        board_ids << b_id
      end
    end
    return board_ids
  end

  def team_boards(team_name)
    team_boards_map = teams[team_name.to_sym]
    team_boards = []
    team_boards_map.each do |board_name, board_id|
      team_boards << boards[board_id]
    end
    team_boards
  end

  def team_board(board_name)
    board_name = board_name.to_sym
    teams.each do |team_name, team_boards_map|
      team_boards_map.each do |b_name, b_id|
        return boards[b_id] if b_name == board_name
      end
    end
  end

  def boards
    return @boards if @boards
    @boards = {}
    org.boards.target.each do |board|
      if board_ids.include?(board.id)
        @boards[board.id] = board
      end
    end
    @boards
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
    if public_roadmap_board
      rbs << public_roadmap_board
    else
      rbs << roadmap_board
    end
    rbs
  end

  def tag_to_epics
    tag_to_epics = {}
    roadmap_boards.each do |roadmap_board|
      epic_list = epic_list(roadmap_board)
      epic_list.cards.each do |epic_card|
        epic_card.name.scan(/\[[^\]]+\]/).each do |tag|
          if tag != '[future]'
            tag_to_epics[tag] = [] unless tag_to_epics[tag]
            tag_to_epics[tag] << epic_card
          end
        end
      end
    end
    tag_to_epics
  end

  def epic_list(board)
    list = nil
    board.lists.each do |l|
      if l.name == 'Epic Backlog'
        list = l
        break
      end
    end
    list
  end

  def documentation_next_list
    unless @documentation_next_list
      new_list_name = docs_new_list_name || 'Next Sprint'
      docs_planning_board.lists.each do |l|
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

  def clear_checklist_refs(card, checklist_name, tags)
    cl = checklist(card, checklist_name)

    if cl
      cl.items.each do |item|
        tags.each do |tag|
          if item.name.include?(tag) || item.name =~ /\[.*\]\(https?:\/\/trello\.com\/[^\)]+\) \([^\)]+\) \([^\)]+\)/
            (1..3).each do |i|
              begin
                cl.delete_checklist_item(item.id)
                break
              rescue => e
                puts "Error deleting checklist: #{e.message}"
                # Ignore
              end
            end
            break
          end
        end
      end
    end
    unless cl
      puts "Adding #{checklist_name} to #{card.name}"
      cl = Trello::Checklist.create({:name => checklist_name, :board_id => roadmap_id})
      card.add_checklist(cl)
    end
  end

  def list_checklists(card)
    (1..3).each do |i|
      begin
        checklists = card.checklists.target
        return checklists
      rescue => e
        puts "Error getting checklists: #{e.message}"
        raise if i == 3
      end
    end
  end

  def list_cards(list)
    (1..3).each do |i|
      begin
        cards = list.cards.target
        return cards
      rescue => e
        puts "Error getting list cards: #{e.message}"
        raise if i == 3
      end
    end
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

  def org
    @org ||= Trello::Organization.find(organization_id)
  end

  def org_boards
    org.boards.target
  end

  def board(board_id)
    boards[board_id]
  end

  def member(member_name)
    Trello::Member.find(member_name)
  end

end
