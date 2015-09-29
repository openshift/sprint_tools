class Sprint
  def check_labels(x, target, retries=3)
    labels = nil
    i = 0
    while true
      begin
        labels = x.labels
        break
      rescue Exception => e
        puts "Error getting labels: #{e.message}"
        raise if i >= retries
        sleep 10
        i += 1
      end
    end
    labels.map{|x| x.name }.include?(target)
  end

  def check_comments(x, target)
    #TODO Trello doesn't have an api for comments yet
    #x.comments.map{|x| x.body }.include?(target)
    true
  end

  def queries
    {
      :needs_qe => {
        :function => lambda{ |x| !check_labels(x, 'no-qe') }
      },
      :qe_ready => {
        :parent => :needs_qe,
        :function => lambda{ |x| check_comments(x, 'tcms') }
      },
      :approved => {
        :function => lambda{ |x| check_labels(x, 'tc-approved') || check_labels(x, 'no-qe') }
      },
      :accepted   => {
        :function => lambda{ |x| x.list.name == 'Accepted' }
      },
      :completed  => {
        :parent   => :not_accepted,
        :function => lambda{ |x| list = x.list.name == 'Complete' }
      },
      :not_dcut_complete => {
        :parent   => :not_completed,
        :function => lambda{ |x| check_labels(x, 'devcut')}
      }
    }
  end
end
