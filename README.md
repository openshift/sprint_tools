
OpenShift Sprint Tools
===

[![TravisCI](https://travis-ci.org/openshift/sprint_tools.svg?branch=master)](https://travis-ci.org/openshift/sprint_tools)

## Prerequisites

* Ruby v2.3 (other versions _might_ work, but are not tested)
* ImageMagick v6


## Setup

### macOS

macOS comes with Ruby preinstalled, but it's an older version so we need to
install a more recent Ruby version. You can do this without affecting the macOS
default version by using [rbenv](https://github.com/rbenv/rbenv).

Once you've followed the install instructions for `rbenv` run the following:

```
rbenv install 2.3.5
echo "2.3.5" > ~/.rbenv/version
rbenv rehash
gem install bundler
```

Running `which bundler` should point to the `.rbenv/shims` location and not
`/usr/local/bin`. Double check your profile has the required `rbenv init -`
output incldued and run `rbenv rehash` to ensure the shim is used.

```
$ which bundler       
/Users/SOMEUSERNAME/.rbenv/shims/bundler
```

Now install ImageMagick like so:

```
brew unlink imagemagick
brew install imagemagick@6
brew link imagemagick@6 --force
```

Finally you can run the following to install dependencies:

    bundler install

### Other Platforms

Once you're running the correct Ruby and ImageMagick versions run:

    bundle install


## Run

    ./trello <COMMAND> [OPTIONS]


##Configuration

You'll need to update `config/trello.yml` with your board IDs and API
credentials. You can find the API credentials by following the `ruby-trello` guide
[here](https://github.com/jeremytregunna/ruby-trello#configuration).

To get the necessary board IDs visit the board in your browser then add
`/report.json` to the end of the URL. The JSON returned contains the ID for that
specific board.


### Commands

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


**create_roadmap_labels**

    DESCRIPTION:
        creates each of LABEL1 LABEL2 ... as labels on the configured roadmap board

    OPTIONS:
        LABEL1 [LABEL2 ...]
            Labels names to be created


**backup_org_boards**

    DESCRIPTION:
        dump a JSON backup of all organization boards to the specified directory

    OPTIONS:
        --out-dir DIRECTORY
            Directory to dump backup json to


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


**generate_developers_overview**

    DESCRIPTION:
        Generate the developers overview

    OPTIONS:
        --out OUT_FILE
            The file to output Ex: /tmp/developers_overview.html


**generate_raw_overview**

    DESCRIPTION:
        Generate a CSV-formatted file containing the card data used in the overview pages, suitable to importing into a spreadsheet.

    OPTIONS:
        --out OUT_FILE
            The file to output Ex: /tmp/raw_overview.csv


**generate_release_json**

    DESCRIPTION:
        Generate json for the cards in a release

    OPTIONS:
        --out-dir DIRECTORY
            The dir to output to Ex: /tmp
        --release RELEASE
            Release to build json for Ex: 3.3
        --product PRODUCT
            Product to build json for Ex: myproduct


**generate_trello_login_to_email_json**

    DESCRIPTION:
        Generate a json file with trello login -> email

    OPTIONS:
        --out OUT_FILE
            File to output the resulting json to Ex: /tmp/trello_login_to_email.json


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


**list_roadmap_labels**

    DESCRIPTION:
        List the labels belonging to a board, defaulting to the Roadmap board designated in the configuration.

    OPTIONS:
        --board BOARD_NAME
            List labels on a particular board


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


**release_identifier**

    DESCRIPTION:
        Print the release identifier


**sprint_identifier**

    DESCRIPTION:
        Print the sprint identifier


**days_left_in_sprint**

    DESCRIPTION:
        Print the number of days left in the sprint


**days_until_code_freeze**

    DESCRIPTION:
        Print the number of days left until the next code freeze


**days_until_feature_complete**

    DESCRIPTION:
        Print the number of days left until feature_complete


**days_until_stage_one_dep_complete**

    DESCRIPTION:
        Print the number of days left until stage one dependencies are feature complete


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


**rename_label**

    DESCRIPTION:
        Renames a label on all configured boards

    OPTIONS:
        --from FROM
            The label to rename
        --to TO
            What to rename it to


## Detailed Run Example
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
