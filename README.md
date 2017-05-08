
OpenShift Sprint Tools
===

[![TravisCI](https://travis-ci.org/openshift/sprint_tools.svg?branch=master)](https://travis-ci.org/openshift/sprint_tools)

Setup
===
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
        --card-url URL
            Card url Ex: https://trello.com/c/6EhPEbM4


**card_ref_from_url**

    DESCRIPTION:
        Print the card ref based on a given url

    OPTIONS:
        --card-url URL
            Card url Ex: https://trello.com/c/6EhPEbM4


**generate_roadmap_overview**

    DESCRIPTION:
        Generate the overview of the roadmap board

    OPTIONS:
        --out OUT_FILE
            The file to output Ex: /tmp/roadmap_overview.html


**generate_releases_overview**

    DESCRIPTION:
        Generate the releases overview

    OPTIONS:
        --out OUT_FILE
            The file to output Ex: /tmp/releases_overview.html


**generate_teams_overview**

    DESCRIPTION:
        Generate the teams overview

    OPTIONS:
        --out OUT_FILE
            The file to output Ex: /tmp/teams_overview.html


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


**generate_labels_overview**

    DESCRIPTION:
        Generate the labels overview

    OPTIONS:
        --out OUT_FILE
            The file to output Ex: /tmp/labels_overview.html


**generate_default_overviews**

    DESCRIPTION:
        Generate the default overviews

    OPTIONS:
        --out OUT_FILE
            The dir to output to Ex: /tmp


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


**organize_release_cards**

    DESCRIPTION:
        Rearrange board list cards sorted by release

    OPTIONS:
        --dry-run
          Show what changes would be made without actually making them


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


**days_left_in_sprint**

    DESCRIPTION:
        Print the number of days left in the sprint


**update**

    DESCRIPTION:
        An assortment of Trello modification utilities

    OPTIONS:
        --add-task-checklists
            Add task checklists to stories
        --add-bug-checklists
            Add checklists to stories
        --add-dependent-tasks
            Add dependent work tasks (e.g. documentation tasks) to corresponding labeled stories
        --add-dependent-cards
            Add dependent work cards (e.g. documentation cards) for corresponding labeled dev cards
        --update-bug-tasks
            Update closed/verified bug tasks
        --update-roadmap
            Update the roadmap board with progress from teams.  Note: Existing checklist items will be removed with matching [tag]s.


**sync_labels**

    DESCRIPTION:
        Sync the labels from the roadmap board to all the rest


**convert_markers_to_labels**

    DESCRIPTION:
        Convert [] markers on cards to epic- and future labels that exist


Detailed Run Example
===
    ./trello update --update-roadmap --trace
    ./trello update --add-task-checklists --add-bug-checklists --update-bug-tasks --add-dependent-tasks --add-dependent-cards --trace
    ./trello generate_default_overviews --out /tmp --trace
    cp /tmp/roadmap_overview.html /var/www/html/roadmap_overview.html
    cp /tmp/releases_overview.html /var/www/html/releases_overview.html
    cp /tmp/sprints_overview.html /var/www/html/sprints_overview.html
    cp /tmp/labels_overview.html /var/www/html/labels_overview.html
    ./trello generate_sprint_schedule --out /tmp/sprint_schedule.html --sprints 10 --trace
    cp /tmp/sprint_schedule.html /var/www/html/sprint_schedule.html

    cp stylesheets/* /var/www/html/stylesheets/
    ./trello sync_labels --trace
