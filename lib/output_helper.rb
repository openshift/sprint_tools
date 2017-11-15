#!/usr/bin/env ruby

require 'stringio'
require 'ostruct'

module Kernel
  alias :old_puts :puts
  alias :old_print :print

  def puts(*args)
    _indent
    old_puts *args
  end

  def print(*args)
    _indent
    old_print *args
  end

  def capture_stdout
    out = StringIO.new
    $stdout = out
    yield
    return out
  ensure
    $stdout = STDOUT
  end

  private
  def _indent
    @indent ||= 0
    old_print " " * @indent * 2
  end
end

def heading(msg)
  puts msg
  puts "=" * msg.length
  @indent += 1
  yield if block_given?
  @indent -= 1
  puts ""
end

def _progress(msg)
  print "%s..." % msg
  yield
  indent = @indent
  @indent = 0
  puts "done"
  @indent = indent
end

def _table(title, hash, args = {})
  table = make_table(hash, args)

  heading title do
    table.lines.each do |line|
      puts table.fmt % line
    end
  end
end

def make_table(args, options = {})
  options = OpenStruct.new(options)
  # Sort the stuff or just convert to an array
  args = if (key = options.sort)
    args.sort do |a, b|
      a[key].to_s <=> b[key].to_s
    end
  else
    args.to_a
  end

  # Convert to a list or string
  args.map! do |line|
    line.map do |item|
      case item
      when Array
        item.join(", ")
      else
        item.to_s
      end
    end
  end

  if options.capitalize
    args.map! do |line|
      line[0].capitalize!
      line
    end
  end

  lens = []
  args.each do |line|
    line.each_with_index do |item, i|
      lens[i] = [lens[i], item.length].compact.max
    end
  end

  lens.pop
  lens.push(nil)

  lens.map! do |x|
    ["%", x, "s"].join('')
  end

  OpenStruct.new(
    fmt: lens.join(" %s " % (options.separator || "-")),
    lines: args,
    line_len: args.first ? args.first.length : 0
  )
end
