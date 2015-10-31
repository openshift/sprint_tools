class Sprint
  def has_label(card, labels)
    (labels - trello.card_labels(card).map{|label| label.name }).length < labels.length
  end

  def check_comments(card, target)
    #TODO Trello doesn't have an api for comments yet
    #card.comments.map{|card| card.body }.include?(target)
    true
  end

  def queries
    {
      :needs_qe => {
        :function => lambda{ |card| !has_label(card, ['no-qe']) }
      },
      :qe_ready => {
        :parent => :needs_qe,
        :function => lambda{ |card| check_comments(card, ['tcms']) }
      },
      :approved => {
        :function => lambda{ |card| has_label(card, ['tc-approved', 'no-qe']) }
      },
      :accepted   => {
        :function => lambda{ |card| trello.card_list(card).name == 'Accepted' || (trello.card_list(card).name == 'Complete' && has_label(card, ['no-qe'])) }
      },
      :completed  => {
        :parent   => :not_accepted,
        :function => lambda{ |card| trello.card_list(card).name == 'Complete' }
      },
      :not_dcut_complete => {
        :parent   => :not_completed,
        :function => lambda{ |card| has_label(card, ['devcut'])}
      },
      :release_incomplete => {
        :parent   => :not_accepted,
        :function => lambda{ |card| (trello.current_release_labels && has_label(card, trello.current_release_labels))}
      }
    }
  end
end
