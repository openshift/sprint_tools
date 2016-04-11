class Sprint

  def has_label?(card, labels)
    (labels - trello.card_labels(card).map{|label| label.name }).length < labels.length
  end

  def has_comment?(card, target_comments)
    trello.list_comments(card).each do |comment|
      target_comments.each do |target_comment|
        return true if comment.include?(target_comment)
      end
    end
    false
  end

  def has_referencing_card?(rfe, stories)
    id = rfe['id']
    url = "https://bugzilla.redhat.com/show_bug.cgi?id=#{id}"
    stories.each do |card|
      #return true if card.name.include?(url)
      return true if card.desc.include?(url)
      #checklists = trello.list_checklists(card)
      #checklists.each do |checklist|
      #  checklist.items.each do |item|
      #    return true if item.name.include?(url)
      #  end
      #end
      #trello.list_comments(card).each do |comment|
      #  return true if comment.include?(url)
      #end
    end
    return false
  end

  def queries
    {
      :needs_qe => {
        :parent   => :not_accepted,
        :function => lambda{ |card| !has_label?(card, ['no-qe']) }
      },
      :qe_ready => {
        :parent => :needs_qe,
        :function => lambda{ |card| has_comment?(card, ['tcms', 'goo.gl']) }
      },
      :approved => {
        :parent   => :qe_ready,
        :function => lambda{ |card| has_label?(card, ['tc-approved', 'no-qe']) }
      },
      :accepted   => {
        :function => lambda{ |card| TrelloHelper::ACCEPTED_STATES.include?(trello.card_list(card).name) || (TrelloHelper::COMPLETE_STATES.include?(trello.card_list(card).name) && has_label?(card, ['no-qe'])) }
      },
      :completed  => {
        :parent   => :not_accepted,
        :function => lambda{ |card| TrelloHelper::COMPLETE_STATES.include?(trello.card_list(card).name) }
      },
      :not_dcut_complete => {
        :parent   => :not_completed,
        :function => lambda{ |card| has_label?(card, ['devcut'])}
      },
      :code_freeze_incomplete => {
        :function => lambda{ |card| (trello.current_release_labels && has_label?(card, trello.current_release_labels))},
        :include_backlog => true
      },
      :stage1_incomplete => {
        :parent   => :code_freeze_incomplete,
        :function => lambda{ |card| has_label?(card, [TrelloHelper::STAGE1_DEP_LABEL])},
        :include_backlog => true
      },
      :new_rfes => {
        :function => lambda{ |rfe| !has_referencing_card?(rfe, all_stories)},
        :type => 'rfes'
      },
      :complete_rfes => {
        :function => lambda{ |rfe| has_referencing_card?(rfe, accepted_and_after_stories)},
        :type => 'rfes'
      }
    }
  end
end
