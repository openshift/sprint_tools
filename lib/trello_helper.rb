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

  attr_accessor :boards, :trello_login_to_email, :cards_by_list, :labels_by_card, :list_by_card, :members_by_card, :members_by_id, :checklists_by_card, :lists_by_board, :comments_by_card, :board_id_to_team_map

  DEFAULT_RETRIES = 9
  DEFAULT_RETRY_SLEEP = 2
  DEFAULT_RETRY_INC = 1

  FUTURE_LABEL = 'future'
  FUTURE_TAG = "[#{FUTURE_LABEL}]"

  STAGE1_DEP_LABEL = 'stage1-dep'

  SPRINT_REGEX = /^Sprint (\d+)/
  DONE_REGEX = /^Done: ((\d+)\.(\d+)(.(\d+))?(.(\d+))?)/
  SPRINT_REGEXES = Regexp.union([SPRINT_REGEX, DONE_REGEX])

  RELEASE_LABEL_REGEX = /^(proposed|targeted|committed)-((\w*)-)*((\d+)(.(\d+))?(.(\d+))?(.(\d+))*)/

  STAR_LABEL_REGEX = /^([1-5])star$/

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

  REFERENCE_STATES = {
    'References' => true
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
    @members_by_id = {}
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

  def tag_to_epics(rm_boards=roadmap_boards)
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
          epic_card.name.scan(/\[[^\]]+\]/).each do |tag|
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
        break unless cl.items.select{|i| i.name.strip == item_name && i.complete? == checked }.one?
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
        break if cl.items.select{|i| i.id == item.id }.empty?
        raise if retry_count >= DEFAULT_RETRIES
        retry_sleep retry_count
        retry_count += 1
      end
    end
  end

  def clear_epic_refs(epic_card)
    checklists = list_checklists(epic_card)
    checklists.each do |cl|
      cl.items.each do |item|
        if item.name =~ /\[.*\]\(https?:\/\/trello\.com\/[^\)]+\) \([^\)]+\)/
          begin
            checklist_delete_item(cl, item)
          rescue => e
            $stderr.puts "Error deleting checklist item: #{e.message}"
          end
        end
      end
    end
    create_checklist(epic_card, UNASSIGNED_RELEASE)
    create_checklist(epic_card, FUTURE_RELEASE)
  end

  def clear_checklist(cl)
    cl.items.each do |item|
      checklist_delete_item(cl, item)
    end
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

  def update_roadmaps(team_name, rm_boards, team_boards, releases, roadmap_tag_to_epics, include_accepted=true, include_board_name_in_epic=true)
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
          epic_card.name.scan(/\[[^\]]+\]/).each do |tag|
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
              epic_card.desc = epic_card.desc + "\n\n" + global_epics_to_link.keys.map{ |short_url| "Parent Epic: #{short_url}"}.join("\n")
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

            lists = accepted_lists + complete_lists + in_progress_lists + next_lists + backlog_lists + new_lists

            previous_sprint_lists = previous_sprint_lists.sort_by { |l| [l.name =~ SPRINT_REGEXES ? $1.to_i : 9999999, $3.to_i, $4.to_i, $6.to_i, $8.to_i]}
            lists += previous_sprint_lists
            lists += other_lists
            lists.each do |list|
              accepted = (list.name.match(SPRINT_REGEXES) || ACCEPTED_STATES.include?(list.name)) ? true : false
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
                    elsif releases.include?(label.name) && label.name =~ RELEASE_LABEL_REGEX
                      state = $1
                      product = $3
                      release = $4
                      major = $5.to_i
                      minor = $7.to_i
                      patch = $9.to_i
                      hotfix = $11.to_i

                      card_releases[product] = [] unless card_releases[product]
                      card_releases[product] << [label, state, release, major, minor, patch, hotfix]
                    end
                  end

                  unless card_releases.empty?
                    card_releases.each do |product, product_card_releases|
                      if product_card_releases.length > 1
                        product_card_releases.sort_by!{ |release| [release[3], release[4], release[5], release[6], RELEASE_STATE_ORDER[release[1]]] }
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

                  marker_card_tags = card.name.scan(/\[[^\]]+\]/)
                  marker_card_tags.each{ |tag| tag.downcase! }
                  marker_card_tags.delete_if{ |tag| card_tags.include?("epic-#{tag[1..-2]}") }
                  checklist_name = (marker_card_tags.include?(FUTURE_TAG) || card_labels.map{|l| l.name }.include?(FUTURE_LABEL)) ? FUTURE_RELEASE : UNASSIGNED_RELEASE
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
          tags_without_epics_checklist = create_checklist(none_epic_card, NONE_CHECKLIST_NAME)
          clear_checklist(tags_without_epics_checklist)
          tags_without_epics.keys.each do |tag|
            checklist_add_item(tags_without_epics_checklist, tag, false, 'bottom')
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
          clear_epic_refs(first_epic_story[0])
          puts "\nAdding cards to #{first_epic_story[0].name}:"
          epic_stories.each do |epic_story|
            epic = epic_story[0]
            card = epic_story[1]
            list = epic_story[2]
            board = epic_story[3]
            checklist_name = epic_story[4]
            accepted = epic_story[5]
            next_card_releases = epic_story[6]

            stars = ''
            card_labels = card_labels(card)
            card_labels.each do |label|
              if label.name =~ STAR_LABEL_REGEX
                star_level = $1.to_i
                stars = ' ' + (':star:' * star_level)
                break
              end
            end

            checklist_item_name = nil
            if include_board_name_in_epic
              checklist_item_name = "[#{card.name}](#{card.url}) (#{list.name}) (#{board.name})#{stars}"
            else
              checklist_item_name = "[#{card.name}](#{card.url}) (#{list.name})#{stars}"
            end

            if !next_card_releases.empty?
              next_card_releases.each do |card_release|
                cl = create_checklist(epic, card_release)
                checklist_add_item(cl, checklist_item_name, accepted, 'bottom')
              end
            else
              stories_checklist = checklist(epic, checklist_name)
              if stories_checklist
                puts "Adding #{card.url}"
                checklist_add_item(stories_checklist, checklist_item_name, accepted, 'bottom')
              end
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

  def card_members(card)
    members = @members_by_card[card.id]
    return members if members
    members = card.member_ids.map do |member_id|
      member = @members_by_id[member_id]
      unless member
        trello_do('find_member') do
          member = Trello::Member.find(member_id)
        end
      end
      @members_by_id[member_id] = member
      member
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

  def update_card(card)
    trello_do('update_card') do
      card.save
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
    teams.keys.map{ |team_name| team_name.to_s }.each do |team_name|
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
      board = list_info[1]
      list = list_info[2]
      cards = list_cards(list)
      cards.each_with_index do |card, index|
        labels = card_labels(card)
        label_names = labels.map{ |label| label.name }
        label_names.each do |label_name|
          if label_name =~ RELEASE_LABEL_REGEX
            if product == $3 && release == $4
              state = $1
              release_cards[card.id] = {
                                         :short_url => card.short_url,
                                         :name => card.name,
                                         :team_name => team_name,
                                         :state => state
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

  def dump_board_json(board)
    board = board(board) unless board.respond_to? :id
    board_json_url = "#{board.url}.json"
    # API request to pull down the same content as the export URL, but limited to 100 actions
    alternate_url = "https://trello.com/1/boards/#{board.id}"
    alternate_params = {:fields => 'all',
                        :actions => 'all',
                        :actions_limit => '100',
                        :action_fields => 'all',
                        :cards => 'all',
                        :card_fields => 'all',
                        :card_attachments => 'true',
                        :labels => 'all',
                        :lists => 'all',
                        :list_fields => 'all',
                        :members => 'all',
                        :member_fields => 'all',
                        :checklists => 'all',
                        :checklist_fields => 'all',
                        :organization => 'false'}
    request = Trello::Request.new :get, board_json_url, {}, nil
    response = nil
    i = 0
    while true
      trello_do('dump_board_json') do
        response = Trello::TInternet.execute Trello.auth_policy.authorize(request)
        return response.body if response.code == 200
      end
      err_msg = "Error with dump_board_json backing up board '#{board.name}': " + (response.code.nil? ? "HTTP Timeout?" : "HTTP response code: #{response.code}, response body: #{response.body}")
      if i >= DEFAULT_RETRIES
        raise err_msg
      end
      $stderr.puts err_msg
      if request.uri != alternate_url && response.code.nil?
        $stderr.puts "Retrying with API-based backup URL to work around timeout. *NOTE*: This will only back up the 100 most recent actions, instead of the usual 1,000."
        request = Trello::Request.new :get, alternate_url, alternate_params, nil
      else
        # don't sleep or increment the counter unless we've tried the workaround
        retry_sleep i
        i += 1
      end
    end
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
        retry_sleep i
        i += 1
      end
    end
  end

  def retry_sleep(retry_count)
    sleep DEFAULT_RETRY_SLEEP + (DEFAULT_RETRY_INC * retry_count)
  end
end
