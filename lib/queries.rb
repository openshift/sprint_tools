class Sprint
  def check_labels(card, target, retries=3)
    trello.card_labels(card).map{|label| label.name }.include?(target)
  end

  def check_comments(card, target)
    #TODO Trello doesn't have an api for comments yet
    #card.comments.map{|card| card.body }.include?(target)
    true
  end

  def queries
    {
      :needs_qe => {
        :function => lambda{ |card| !check_labels(card, 'no-qe') }
      },
      :qe_ready => {
        :parent => :needs_qe,
        :function => lambda{ |card| check_comments(card, 'tcms') }
      },
      :approved => {
        :function => lambda{ |card| check_labels(card, 'tc-approved') || check_labels(card, 'no-qe') }
      },
      :accepted   => {
        :function => lambda{ |card| trello.card_list(card).name == 'Accepted' }
      },
      :completed  => {
        :parent   => :not_accepted,
        :function => lambda{ |card| trello.card_list(card).name == 'Complete' }
      },
      :not_dcut_complete => {
        :parent   => :not_completed,
        :function => lambda{ |card| check_labels(card, 'devcut')}
      }
    }
  end
end
