Setup
=====
    bundle install


Run
===
    ./trello


Detailed Run Example
===
    ./trello update --update-roadmap --trace
    ./trello update --add-task-checklists --add-bug-checklists --update-bug-tasks --add-doc-tasks --add-doc-checklists --add-doc-cards --trace
    ./trello generate_roadmap_overview --out /tmp/roadmap_overview.html --trace
    cp /tmp/roadmap_overview.html /var/www/html/roadmap_overview.html
    ./trello generate_sprints_overview --out /tmp/sprints_overview.html --sprints 8 --trace
    cp /tmp/sprints_overview.html /var/www/html/sprints_overview.html
    ./trello generate_sprints_overview --out /tmp/previous_sprints_overview.html --sprints 8 --offset 8 --trace
    cp /tmp/previous_sprints_overview.html /var/www/html/previous_sprints_overview.html
    ./trello generate_sprint_schedule --out /tmp/sprint_schedule.html --sprints 10 --trace
    cp /tmp/sprint_schedule.html /var/www/html/sprint_schedule.html

    cp stylesheets/* /var/www/html/stylesheets/
