class Sprint
  def has_label(card, labels)
    (labels - trello.card_labels(card).map{|label| label.name }).length < labels.length
  end

  def has_comment(card, target_comment)
    #TODO Trello doesn't have an api for comments yet
    #card.comments.map{|comment| comment.body }.include?(target_comment)
    true
  end

  def queries
    {
      :needs_qe => {
        :parent   => :not_accepted,
        :function => lambda{ |card| !has_label(card, ['no-qe']) }
      },
      :qe_ready => {
        :parent => :needs_qe,
        :function => lambda{ |card| has_comment(card, 'tcms') }
      },
      :approved => {
        :function => lambda{ |card| has_label(card, ['tc-approved', 'no-qe']) }
      },
      :accepted   => {
        :function => lambda{ |card| TrelloHelper::ACCEPTED_STATES.include?(trello.card_list(card).name) || (TrelloHelper::COMPLETE_STATES.include?(trello.card_list(card).name) && has_label(card, ['no-qe'])) }
      },
      :completed  => {
        :parent   => :not_accepted,
        :function => lambda{ |card| TrelloHelper::COMPLETE_STATES.include?(trello.card_list(card).name) }
      },
      :not_dcut_complete => {
        :parent   => :not_completed,
        :function => lambda{ |card| has_label(card, ['devcut'])}
      },
      :release_incomplete => {
        :function => lambda{ |card| (trello.current_release_labels && has_label(card, trello.current_release_labels))},
        :include_backlog => true
      }
    }
  end
end
