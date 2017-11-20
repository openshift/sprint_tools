require 'trello'
require 'json'

class TrelloJsonLoader
  # attr_accessor :trello
  attr_accessor :organizations_by_id, :boards_by_id, :cards_by_id, :checklists_by_id, :checklist_id_to_card_id, :labels_by_id, :lists_by_id, :members_by_id, :type_to_map, :organization_members

  TYPES = ["organizations", "boards", "labels", "members", "cards", "checklists", "lists"]
  TYPE_TO_CLASS = {
    'organizations' => Trello::Organization,
    'boards' => Trello::Board,
    'labels' => Trello::Label,
    'members' => Trello::Member,
    'cards' => Trello::Card,
    'checklists' => Trello::Checklist,
    'lists' => Trello::List
  }

  def initialize
    @organizations_by_id = {}
    @boards_by_id = {}
    @labels_by_id = {}
    @members_by_id = {}
    @organization_members = []
    @cards_by_id = {}
    @checklists_by_id = {}
    @checklist_id_to_card_id = {}
    @lists_by_id = {}
    @type_to_map = {
      'organizations' => @organizations_by_id,
      'boards' =>        @boards_by_id,
      'labels' =>        @labels_by_id,
      'members' =>       @members_by_id,
      'cards' =>         @cards_by_id,
      'checklists' =>    @checklists_by_id,
      'lists' =>         @lists_by_id
    }
  end

  # Class methods section

  def load_from_file(filespec, type)
    File.open(filespec, 'r') do |json_file|
      data = JSON.load(json_file)
      load_any(data, type)
    end
  end

  # Special case this since these are backed up as an Array of Hashes
  def load_org_members_from_file(filespec)
    File.open(filespec, 'r') do |json_file|
      data = JSON.load(json_file)
      data.each do |member_data|
        @organization_members << load_any(member_data, 'members', false)
      end
    end
  end

  def load_any(data, type, nested=true)
    dataobj = nil
    if nested
      TYPES.each do |nested_type|
        if data[nested_type]
          data[nested_type].each_with_object(@type_to_map[nested_type]) do |nested_obj, type_map|
            load_any(nested_obj, nested_type)
          end
        end
      end
    end
    begin
      dataobj = TYPE_TO_CLASS[type].new(data)
      type_to_map[type][dataobj.id] ||= dataobj
      # Handle ruby-trello 1.3.0
      if type == 'checklists' and data['idCard']
        @checklist_id_to_card_id[dataobj.id] ||= data['idCard']
      end
    rescue Exception => e
      $stderr.puts "Error while loading data of type #{type} with data: #{data.to_s[0..200]}"
      raise
    end
    dataobj
  end

  def load_board(data)
    load_any(data, 'boards')
  end

  def load_label(data)
    load_any(data, 'labels')
  end

  def load_member(data)
    load_any(data, 'members')
  end

  def load_card(data)
    load_any(data, 'cards')
  end

  def load_checklist(data)
    load_any(data, 'checklists')
  end

  def load_list(data)
    load_any(data, 'lists')
  end
end

