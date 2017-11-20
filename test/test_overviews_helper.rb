require 'helper'
require 'overviews_helper'

require 'csv'

class TestOverviewsHelper < SprintTools::TestCase
  def setup
    super
    @config = load_std_config
    @trello = load_conf(TrelloHelper, @config.trello, true)
    init_card_data
    init_test_cards
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

    @card_data_with_product_in_progress = { id: "aaabcdef0123456789abcdef",
                                  title: "Test card 2 - with products [test_tag]",
                                  card_size: "5",
                                  card_url: "https://trello.com/c/12AB34CE/",
                                  team_name: "team1",
                                  board_name: "team1_board1",
                                  board_url: "https://trello.com/b/98Bc76JF/team1-board1",
                                  list: "In Progress",
                                  status: "In Progress",
                                  members: [ "James Doe (jamesdoe)" ],
                                  products: { "product1" => ['5.1.2', 'proposed'] },
                                  epics: [ "epic-example-second" ]
                                }
    @card_csv_row_array_with_product_in_progress = [ "product1",
                                           "product1:5.1.2",
                                           "product1:proposed",
                                           "Test card 2 - with products [test_tag]",
                                           "https://trello.com/c/12AB34CE/",
                                           "team1",
                                           "team1_board1",
                                           "https://trello.com/b/98Bc76JF/team1-board1",
                                           "In Progress",
                                           "In Progress",
                                           "epic-example-second",
                                           "5",
                                           "James Doe (jamesdoe)",
                                           "aaabcdef0123456789abcdef"
                                                   ]

    @card_data_with_product_complete = { id: "ababcdef0123456789abcdef",
                                         title: "Test card 3 - with complete product [test_tag]",
                                         card_size: "8",
                                         card_url: "https://trello.com/c/12AB34CF/",
                                         team_name: "team1",
                                         board_name: "team1_board1",
                                         board_url: "https://trello.com/b/98Bc76JF/team1-board1",
                                         list: "Accepted",
                                         status: "Complete",
                                         members: [ "Joe Example (jojo1)" ],
                                         products: { "product1" => ['5.1.2', 'committed'] },
                                         epics: [ "epic-example-second", "epic-example-third" ]
                                       }
    @card_csv_row_array_with_product_complete = [ "product1",
                                                  "product1:5.1.2",
                                                  "product1:committed",
                                                  "Test card 3 - with complete product [test_tag]",
                                                  "https://trello.com/c/12AB34CF/",
                                                  "team1",
                                                  "team1_board1",
                                                  "https://trello.com/b/98Bc76JF/team1-board1",
                                                  "Accepted",
                                                  "Complete",
                                                  "epic-example-second|epic-example-third",
                                                  "8",
                                                  "Joe Example (jojo1)",
                                                  "ababcdef0123456789abcdef"
                                                ]
  end

  def init_test_cards
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
    @test_card_no_products = Trello::Card.new(test_card_fields)
    test_card_fields = { "name" => "(5) Test card 2 - with products [test_tag]",
                         "id" => "aaabcdef0123456789abcdef",
                         "idList" => "000000000000000000000000",
                         "idShort" => "12AB34CE",
                         "desc" => "",
                         "idMembers" => nil,
                         "labels" => nil,
                         "due" => nil,
                         "pos" => nil,
                         "shortUrl" => "https://trello.com/c/12AB34CE/"
                       }
    @test_card_product_in_progress = Trello::Card.new(test_card_fields)
    test_card_fields = { "name" => "(8) Test card 3 - with complete product [test_tag]",
                         "id" => "ababcdef0123456789abcdef",
                         "idList" => "000000000000000000000000",
                         "idShort" => "12AB34CF",
                         "desc" => "",
                         "idMembers" => nil,
                         "labels" => nil,
                         "due" => nil,
                         "pos" => nil,
                         "shortUrl" => "https://trello.com/c/12AB34CF/"
                       }
    @test_card_product_complete = Trello::Card.new(test_card_fields)
  end

  def init_trello_mocker
    mock_member1 = Minitest::Mock.new
    mock_member1.expect :full_name, "Joe Example"
    mock_member1.expect :username, "jojo1"
    mock_member1.expect :full_name, "Joe Example"
    mock_member1.expect :username, "jojo1"

    mock_member2 = Minitest::Mock.new
    mock_member2.expect :full_name, "James Doe"
    mock_member2.expect :username, "jamesdoe"
    mock_member2.expect :full_name, "James Doe"
    mock_member2.expect :username, "jamesdoe"

    mock_labels_no_products = [ "epic-example-first", "epic-example-second" ].map do |lname|
      mock_label = Minitest::Mock.new
      mock_label.expect :name, lname
      mock_label
    end

    mock_labels_product_in_progress = [ "epic-example-second", "proposed-product1-5.1.2" ].map do |lname|
      mock_label = Minitest::Mock.new
      mock_label.expect :name, lname
      mock_label
    end

    mock_labels_product_complete = [ "epic-example-second", "epic-example-third", "committed-product1-5.1.2" ].map do |lname|
      mock_label = Minitest::Mock.new
      mock_label.expect :name, lname
      mock_label
    end

    mock_list_no_products = Minitest::Mock.new
    mock_list_no_products.expect :name, "Accepted"
    mock_list_no_products.expect :name, "Accepted"
    mock_list_product_in_progress = Minitest::Mock.new
    mock_list_product_in_progress.expect :name, "In Progress"
    mock_list_product_in_progress.expect :name, "In Progress"
    mock_list_product_in_progress.expect :name, "In Progress"
    mock_list_product_complete = Minitest::Mock.new
    mock_list_product_complete.expect :name, "Accepted"
    mock_list_product_complete.expect :name, "Accepted"

    mock_board = Minitest::Mock.new
    mock_board.expect :name, "team1_board1"
    mock_board.expect :url, "https://trello.com/b/98Bc76JF/team1-board1"
    mock_board.expect :name, "team1_board1"
    mock_board.expect :url, "https://trello.com/b/98Bc76JF/team1-board1"
    mock_board.expect :name, "team1_board1"
    mock_board.expect :url, "https://trello.com/b/98Bc76JF/team1-board1"

    @mock_trello = Minitest::Mock.new(@trello)
    @mock_trello.expect :card_members, [ mock_member1, mock_member2 ], [@test_card_no_products]
    @mock_trello.expect :card_labels, mock_labels_no_products, [@test_card_no_products]
    @mock_trello.expect :card_members, [ mock_member2 ], [@test_card_product_in_progress]
    @mock_trello.expect :card_labels, mock_labels_product_in_progress, [@test_card_product_in_progress]
    @mock_trello.expect :card_members, [ mock_member1 ], [@test_card_product_complete]
    @mock_trello.expect :card_labels, mock_labels_product_complete, [@test_card_product_complete]

    @mock_trello.expect :other_products, nil
    @mock_trello.expect :default_product, nil

    @mock_trello.expect :teams, [['team1', {}]]
    @mock_trello.expect :team_boards, [mock_board], ['team1']
    @mock_trello.expect :board_lists, [mock_list_no_products, mock_list_product_in_progress, mock_list_product_complete], [mock_board]
    @mock_trello.expect :list_cards, [@test_card_no_products], [mock_list_no_products]
    @mock_trello.expect :list_cards, [@test_card_product_in_progress], [mock_list_product_in_progress]
    @mock_trello.expect :list_cards, [@test_card_product_complete], [mock_list_product_complete]
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
    mock_board.expect :name, "team1_board1"
    mock_board.expect :url, "https://trello.com/b/98Bc76JF/team1-board1"
    mock_board.expect :name, "team1_board1"
    mock_board.expect :url, "https://trello.com/b/98Bc76JF/team1-board1"

    mock_list = Minitest::Mock.new
    mock_list.expect :name, "Accepted"
    mock_list.expect :name, "In Progress"
    mock_list.expect :name, "Accepted"

    overviews_helper = OverviewsHelper.new(trello: @mock_trello)

    card_data = overviews_helper.card_data_from_card(@test_card_no_products, "team1", mock_board, mock_list, "Complete")
    assert_equal(@card_data_no_products, card_data)

    card_data = overviews_helper.card_data_from_card(@test_card_product_in_progress, "team1", mock_board, mock_list, "In Progress")
    assert_equal(@card_data_with_product_in_progress, card_data)

    card_data = overviews_helper.card_data_from_card(@test_card_product_complete, "team1", mock_board, mock_list, "Complete")
    assert_equal(@card_data_with_product_complete, card_data)
  end

  def test_create_raw_overview_data
    csv_array = []
    overviews_helper = OverviewsHelper.new(trello: @mock_trello)
    CSV.stub(:open, nil, csv_array) do
      overviews_helper.create_raw_overview_data("test")
    end

    assert_equal([OverviewsHelper::CSV_HEADER, @card_csv_row_array_no_products, @card_csv_row_array_with_product_in_progress, @card_csv_row_array_with_product_complete], csv_array)
  end
end
