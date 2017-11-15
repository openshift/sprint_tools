require 'rubygems'
require 'rake/testtask'

$stdout.sync = true
$stderr.sync = true

task default: "check_syntax"

Rake::TestTask.new(:test) do |t|
  t.libs.unshift("test")
  t.verbose = true
  t.test_files = FileList["test/**/test_*.rb"]
end

desc "Check syntax"
task :check_syntax do

  syntax_check_cmd = %{
set -e
for f in `find ./ -name *.rb`
do
ruby -c $f >/dev/null;
done
ruby -c trello >/dev/null;
}
  `#{syntax_check_cmd}`
  if $?.exitstatus != 0
    exit 1
  end
end
