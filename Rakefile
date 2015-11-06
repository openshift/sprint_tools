require 'rubygems'

$stdout.sync = true
$stderr.sync = true

namespace :sprint_tools do

  desc "Check syntax"
  task :check_syntax do

    syntax_check_cmd = %{
set -e
for f in `find lib -name *.rb`
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
end

task :default => "sprint_tools:check_syntax"
