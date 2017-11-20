require 'helper'
require 'trello_helper'

class TestTrelloHelperAddMethods < SprintTools::TestCase
  def setup
    super
    @config = load_std_config
  end

  # Check that new boards are placed in the correct caching objects
  # and all expected side effects occur
  def test_add_board
    trello = load_conf(TrelloHelper, @config.trello, true)

    mock_team_board = Minitest::Mock.new
    mock_team_board.expect :name, "team1_board1"
    mock_team_board.expect :url, "https://trello.com/b/98Bc76JF/team1-board1"
    mock_team_board.expect :id, "1abcdef1234567890abcdef1"
    mock_team_board.expect :id, "1abcdef1234567890abcdef1"

    mock_public_roadmap_board = Minitest::Mock.new
    mock_public_roadmap_board.expect :name, "Roadmap"
    mock_public_roadmap_board.expect :url, "https://trello.com/b/aaaabbbb/roadmap"
    mock_public_roadmap_board.expect :id, "5abcdef1234567890abcdef1"
    mock_public_roadmap_board.expect :id, "5abcdef1234567890abcdef1"
    mock_public_roadmap_board.expect :id, "5abcdef1234567890abcdef1"
    mock_public_roadmap_board.expect :id, "5abcdef1234567890abcdef1"

    mock_private_roadmap_board = Minitest::Mock.new
    mock_private_roadmap_board.expect :name, "Private Roadmap"
    mock_private_roadmap_board.expect :url, "https://trello.com/b/aaaabbbc/roadmap"
    mock_private_roadmap_board.expect :id, "4abcdef1234567890abcdef1"
    mock_private_roadmap_board.expect :id, "4abcdef1234567890abcdef1"
    mock_private_roadmap_board.expect :id, "4abcdef1234567890abcdef1"
    mock_private_roadmap_board.expect :id, "4abcdef1234567890abcdef1"

    trello.add_board(mock_team_board)
    # Should appear as a team board
    assert_equal({"1abcdef1234567890abcdef1" => mock_team_board}, trello.boards)

    trello.add_board(mock_public_roadmap_board)
    # Public roadmap should not appear as a team board
    refute_equal( { "5abcdef1234567890abcdef1" => mock_team_board }, trello.boards)
    # Public roadmap should match trello.public_roadmap_board
    assert_equal("5abcdef1234567890abcdef1", trello.public_roadmap_board.id)

    trello.add_board(mock_private_roadmap_board)
    # Private roadmap should also not appear as a team board.
    refute_equal( { "4abcdef1234567890abcdef1" => mock_team_board }, trello.boards)
    # Private roadmap should not appear as the public roadmap.
    refute_equal("4abcdef1234567890abcdef1", trello.public_roadmap_board.id)
    # Private roadmap should match trello.roadmap_board
    assert_equal("4abcdef1234567890abcdef1", trello.roadmap_board.id)
  end

  def test_add_label
    mock_label_name = "mock_label"

    trello = load_conf(TrelloHelper, @config.trello, true)

    mock_label_id = "1abcd0000000000000000002"
    mock_label = Minitest::Mock.new
    mock_label.expect :id, mock_label_id
    mock_label.expect :id, mock_label_id
    mock_label.expect :id, mock_label_id
    mock_label.expect :name, mock_label_name

    trello.add_label(mock_label)
    assert_equal(mock_label_id, trello.label_by_id(mock_label_id).id)

    mock_label_id = "1abcd0000000000000000001"
    Trello::Label.stub(:find, nil) do
      assert_nil(trello.label_by_id(mock_label_id))
    end

    mock_label_name = "mock_label_2"
    mock_label_id = "1abcd0000000000000000003"
    mock_label = Minitest::Mock.new
    mock_label.expect :id, mock_label_id
    mock_label.expect :id, mock_label_id
    assert_equal(mock_label_id, trello.label_by_id(mock_label_id, {"id" => mock_label_id, "name" => mock_label_name}).id)

  end
end
