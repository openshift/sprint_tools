require 'csv'
require 'trello_helper'

class OverviewsHelper

  attr_accessor :trello, :bugzilla

  CSV_HEADER = [ "Product(s)",
               "Product:Release",
               "Product:State",
               "Card Title",
               "URL",
               "Team",
               "Board",
               "Board URL",
               "List",
               "Status",
               "Epics",
               "Sizing",
               "Members",
               "Card ID" ]

  def initialize(opts = nil)
    if opts
      opts.each do |k,v|
        send("#{k}=",v)
      end
    end
  end

  def card_data_to_csv_row_array(card_data)
    products = card_data[:products].keys.join("|")
    prod_rel = card_data[:products].map { |product, data| "#{product}:#{data[0]}" }.join("|")
    prod_state = card_data[:products].map { |product, data| "#{product}:#{data[1]}" }.join("|")
    card_epics = card_data[:epics].join("|")
    card_members = card_data[:members].join("|")
    return [ products,
             prod_rel,
             prod_state,
             card_data[:title],
             card_data[:card_url],
             card_data[:team_name],
             card_data[:board_name],
             card_data[:board_url],
             card_data[:list],
             card_data[:status],
             card_epics,
             card_data[:card_size],
             card_members,
             card_data[:id] ]
  end

  def card_data_from_card(card, team_name, board, list, status)
    card_name = card.name
    card_size = 0
    TrelloHelper::CARD_NAME_REGEX.match(card.name) do |card_fields|
      card_name = card_fields[3].strip
      card_size = (card_fields[2] || "").strip
    end
    card_members = trello.card_members(card).map { |m| "#{m.full_name} (#{m.username})" }
    card_data = { id: card.id,
                  title: card_name,
                  card_size: card_size,
                  card_url: card.short_url,
                  team_name: team_name,
                  board_name: board.name,
                  board_url: board.url,
                  list: list.name,
                  status: status,
                  members: card_members }
    card_data[:products] = {}
    card_data[:epics] = []
    labels = trello.card_labels(card)
    label_names = labels.map{ |label| label.name }
    label_names.each do |label_name|
      if label_name.start_with?('epic-')
        card_data[:epics] << label_name
      else
        TrelloHelper::RELEASE_LABEL_REGEX.match(label_name) do |fields|
          if trello.valid_products.include?(fields[2])
            product = fields[2]
            state = fields[1]
            release = fields[3]
            if status == 'Complete'
              state = 'committed'
            end
            card_data[:products][product] = [release, state]
          end
        end
      end
    end
    card_data
  end

  def create_raw_overview_data(out)
    cards_data = []
    lists_for_team_boards  = []
    # Leave this for ease of testing
    # ["clusterlifecycle","continuousinfra","customersuccess"].each do |team|
    trello.teams.each do |team_name, team|
      if !team[:exclude_from_releases_overview]
        trello.team_boards(team_name).each do |board|
          trello.board_lists(board).each do |list|
            lists_for_team_boards << [team_name.to_s, board, list]
          end
        end
      end
    end
    lists_for_team_boards.each do |team_name, board, list|
      if trello.list_for_completed_work?(list.name)
        status = 'Complete'
      elsif trello.list_for_in_progress_work?(list.name)
        status = 'In Progress'
      end
      trello.list_cards(list).each do |card|
        cards_data << card_data_from_card(card, team_name, board, list, status)
      end
    end
    CSV.open(out, "wb") do |csv|
      csv << CSV_HEADER
      cards_data.each do |card_data|
        csv << card_data_to_csv_row_array(card_data)
      end
    end
  end

  def create_releases_overview(out)
    extname = File.extname out
    filename = File.basename out, extname
    dirname = File.dirname out

    ((trello.other_products ? trello.other_products : []) + [nil]).each do |product|
      erb = ERB.new(File.open('templates/releases_overview.erb', "rb").read)
      file = nil
      if product
        file = File.join(dirname, "#{filename}_#{product}#{extname}")
      else
        file = out
      end
      File.open(file, 'w') {|f| f.write(erb.result(binding)) }
    end
  end

  def create_teams_overview(out)
    extname = File.extname out
    filename = File.basename out, extname
    dirname = File.dirname out

    (trello.teams.keys + [nil]).each do |team|
      erb = ERB.new(File.open('templates/teams_overview.erb', "rb").read)
      file = nil
      if team
        file = File.join(dirname, "#{filename}_#{team}#{extname}")
      else
        file = out
      end
      File.open(file, 'w') {|f| f.write(erb.result(binding)) }
    end
  end

  def create_developers_overview(out)
    extname = File.extname out
    filename = File.basename out, extname
    dirname = File.dirname out

    (trello.teams.keys + [nil]).each do |team|
      erb = ERB.new(File.open('templates/developers_overview.erb', "rb").read)
      file = nil
      if team
        file = File.join(dirname, "#{filename}_#{team}#{extname}")
      else
        file = out
      end
      File.open(file, 'w') {|f| f.write(erb.result(binding)) }
    end
  end

  def create_labels_overview(out)
    erb = ERB.new(File.open('templates/labels_overview.erb', "rb").read)
    File.open(out, 'w') {|f| f.write(erb.result(binding)) }
  end

  def create_roadmap_overview(out)
    erb = ERB.new(File.open('templates/roadmap_overview.erb', "rb").read)
    File.open(out, 'w') {|f| f.write(erb.result(binding)) }
  end


end
