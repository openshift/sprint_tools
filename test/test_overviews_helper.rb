require 'helper'
require 'overviews_helper'

require 'csv'

class TestOverviewsHelper < SprintTools::TestCase
  def setup
    super
    @config = load_std_config
    @trello = load_conf(TrelloHelper, @config.trello, true)
    init_card_data
    init_test_card
    init_trello_mocker
  end

  def init_card_data
    @card_data_no_products = { id: "a9abcdef0123456789abcdef",
                               title: "Test card title - no products",
                               card_size: "3",
                               card_url: "https://trello.com/c/12AB34CD/",
                               team_name: "team1",
                               board_name: "team1_board1",
                               board_url: "https://trello.com/b/98Bc76JF/team1-board1",
                               list: "Accepted",
                               status: "Complete",
                               members: [ "Joe Example (jojo1)",
                                          "James Doe (jamesdoe)"
                                        ],
                               products: {},
                               epics: [ "epic-example-first", "epic-example-second" ]
                             }

    @card_csv_row_array_no_products = [ "",
                                        "",
                                        "",
                                        "Test card title - no products",
                                        "https://trello.com/c/12AB34CD/",
                                        "team1",
                                        "team1_board1",
                                        "https://trello.com/b/98Bc76JF/team1-board1",
                                        "Accepted",
                                        "Complete",
                                        "epic-example-first|epic-example-second",
                                        "3",
                                        "Joe Example (jojo1)|James Doe (jamesdoe)",
                                        "a9abcdef0123456789abcdef"
                                      ]
  end

  def init_test_card
    test_card_fields = { "name" => "(3) Test card title - no products",
                         "id" => "a9abcdef0123456789abcdef",
                         "idList" => "000000000000000000000000",
                         "idShort" => "12AB34CD",
                         "desc" => "",
                         "idMembers" => nil,
                         "labels" => nil,
                         "due" => nil,
                         "pos" => nil,
                         "shortUrl" => "https://trello.com/c/12AB34CD/"
                       }
    @test_card = Trello::Card.new(test_card_fields)
  end

  def init_trello_mocker
    mock_member1 = Minitest::Mock.new
    mock_member1.expect :full_name, "Joe Example"
    mock_member1.expect :username, "jojo1"

    mock_member2 = Minitest::Mock.new
    mock_member2.expect :full_name, "James Doe"
    mock_member2.expect :username, "jamesdoe"

    mock_labels = [ "epic-example-first", "epic-example-second" ].map do |lname|
      mock_label = Minitest::Mock.new
      mock_label.expect :name, lname
      mock_label
    end

    mock_list = Minitest::Mock.new
    mock_list.expect :name, "Accepted"
    mock_list.expect :name, "Accepted"

    mock_board = Minitest::Mock.new
    mock_board.expect :name, "team1_board1"
    mock_board.expect :url, "https://trello.com/b/98Bc76JF/team1-board1"

    @mock_trello = Minitest::Mock.new(@trello)
    @mock_trello.expect :card_members, [ mock_member1, mock_member2 ], [@test_card]
    @mock_trello.expect :card_labels, mock_labels, [@test_card]

    @mock_trello.expect :other_products, nil
    @mock_trello.expect :default_product, nil

    @mock_trello.expect :teams, [['team1', {}]]
    @mock_trello.expect :team_boards, [mock_board], ['team1']
    @mock_trello.expect :board_lists, [mock_list], [mock_board]
    @mock_trello.expect :list_cards, [@test_card], [mock_list]
  end

  # Validate output of csv prep function
  #
  def test_card_data_to_csv_row_array
    overviews_helper = OverviewsHelper.new()
    assert_equal(@card_csv_row_array_no_products, overviews_helper.card_data_to_csv_row_array(@card_data_no_products))
  end

  def test_card_data_from_card
    mock_board = Minitest::Mock.new
    mock_board.expect :name, "team1_board1"
    mock_board.expect :url, "https://trello.com/b/98Bc76JF/team1-board1"

    mock_list = Minitest::Mock.new
    mock_list.expect :name, "Accepted"

    overviews_helper = OverviewsHelper.new(trello: @mock_trello)

    card_data = overviews_helper.card_data_from_card(@test_card, "team1", mock_board, mock_list, "Complete")

    assert_equal(@card_data_no_products, card_data)
  end

  def test_create_raw_overview_data
    csv_array = []
    overviews_helper = OverviewsHelper.new(trello: @mock_trello)
    copen = lambda { |fname, mode|
      assert_equal 'test', fname
      assert_equal 'wb', mode
    }
    CSV.stub(:open, copen, csv_array) do
      overviews_helper.create_raw_overview_data("test")
    end

    assert_equal(csv_array, [OverviewsHelper::CSV_HEADER, @card_csv_row_array_no_products])
  end
end
