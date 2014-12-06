require 'date'

class Date
  def next(_day)
    find_day(_day)
  end

  def previous(_day)
    find_day(_day, :before)
  end

  def friday?
    wday == 5
  end

  def monday?
    wday == 1
  end

  def thursday?
    wday == 4
  end

  private
  def find_day(_day,mod = :after)
    mult = (mod == :after ? 1 : -1)
    _start = self + (1*mult)
    _end   = self + (7 * mult)
    range  = Range.new(*[_start,_end].sort)
    range.select{|x| x.send("#{_day}?".to_sym)}.first
  end
end
