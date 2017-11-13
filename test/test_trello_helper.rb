require 'helper'
require 'trello_helper'

class TestTrelloHelper < SprintTools::TestCase
  def setup
    super
    @config = load_std_config
    @std_teams = {
      team1: {
        boards: {
          team1_board1: "1abcdef1234567890abcdef1",
          team1_board2: "2abcdef1234567890abcdef1"
        },
        dependent_work_boards: {
          "3abcdef1234567890abcdef1" => {
            label: "documentation",
            new_list_name: "New",
            card_name_prefix: "Team1-Document",
            card_desc_prefix: "Corresponding Development Card",
            task_reminder_text: "Update this card with team1-specific details about what needs to be documented."
          }
        }
      },
      team2: {
        boards: {
          team2_board: "02abcdef1234567890abcdef"
        }
      },
      team3: {
        boards: {
          team3_board: "03abcdef1234567890abcdef",
          team3_board_private: "13abcdef1234567890abcdef"
        },
        exclude_from_sprint_report: true,
        exclude_from_dependent_work_board: true
      }
    }
  end

  # Silly test to validate equality of loaded config with hardcoded
  # config. Only really tests the YAML loader, but you gotta start
  # somewhere.
  #
  def test_teams
    trello = load_conf(TrelloHelper, @config.trello, true)
    assert_equal @std_teams, trello.teams
  end

  # Make sure the valid_products function works
  def test_valid_products
    trello = load_conf(TrelloHelper, @config.trello, true)
    assert_equal(['product2', 'product3', 'product1'], trello.valid_products)
  end
end
