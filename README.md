Setup
=====
    bundle install


Run
===
    ./trello <COMMAND> [OPTIONS]


Commands
===

**comment**

    DESCRIPTION:
        Adds a comment to a trello card

    OPTIONS:
        --card-ref SCOPE_TEAM_ID
            Get a single card Ex: team1_board1_1


**generate_roadmap_overview**

    DESCRIPTION:
        Generate the overview of the roadmap board

    OPTIONS:
        --out OUT_FILE
            The file to output Ex: /tmp/roadmap_overview.html


**generate_sprint_schedule**

    DESCRIPTION:
        Generate the sprint schedule

    OPTIONS:
        --out OUT_FILE
            The file to output Ex: /tmp/sprint_schedule.html
        --sprints NUM
            The number of sprints to show


**generate_sprints_overview**

    DESCRIPTION:
        Generate the sprints overview

    OPTIONS:
        --out OUT_FILE
            The file to output Ex: /tmp/sprints_overview.html
        --sprints NUM
            The number of sprints to show
        --offset NUM
            The number of sprints to offset from the latest


**list**

    DESCRIPTION:
        An assortment of Trello queries

    OPTIONS:
        --list LIST_NAME
            Restrict to a particular list
        --team TEAM_NAME (team1|team2)
            Restrict to a team
        --card-ref SCOPE_TEAM_ID
            Get a single card Ex: team1_board1_1


**list_invalid_users**

    DESCRIPTION:
        List the potentially invalid users



**report**

    DESCRIPTION:
        An assortment of Trello reporting utilities

    OPTIONS:
        --report-type NAME
            Available report types: dev, qe
        --send-email
            Send email?


**sprint_identifier**

    DESCRIPTION:
        Print the sprint identifier


**update**

    DESCRIPTION:
        An assortment of Trello modification utilities

    OPTIONS:
        --add-task-checklists
            Add task checklists to stories
        --add-bug-checklists
            Add checklists to stories
        --add-doc-tasks
            Add documentation tasks to documentation labeled stories
        --add-doc-cards
            Add documentation cards for documentation labeled dev cards
        --update-bug-tasks
            Update closed/verified bug tasks
        --update-roadmap
            Update the roadmap board with progress from teams.  Note: Existing checklist items will be removed with matching [tag]s.



Detailed Run Example
===
    ./trello update --update-roadmap --trace
    ./trello update --add-task-checklists --add-bug-checklists --update-bug-tasks --add-doc-tasks --add-doc-cards --trace
    ./trello generate_roadmap_overview --out /tmp/roadmap_overview.html --trace
    cp /tmp/roadmap_overview.html /var/www/html/roadmap_overview.html
    ./trello generate_sprints_overview --out /tmp/sprints_overview.html --sprints 8 --trace
    cp /tmp/sprints_overview.html /var/www/html/sprints_overview.html
    ./trello generate_sprints_overview --out /tmp/previous_sprints_overview.html --sprints 8 --offset 8 --trace
    cp /tmp/previous_sprints_overview.html /var/www/html/previous_sprints_overview.html
    ./trello generate_sprint_schedule --out /tmp/sprint_schedule.html --sprints 10 --trace
    cp /tmp/sprint_schedule.html /var/www/html/sprint_schedule.html

    cp stylesheets/* /var/www/html/stylesheets/
