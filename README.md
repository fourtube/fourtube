# Fourtube

This is a complete framework/piece of shit that helps me automatically browse
some website, looking for youtube URLs, download them, then push them in a 
nice little database for later use.

## Quick Start

Install the packages, update [config.json](https://github.com/fourtube/fourtube/wiki/Config.Json) and run `ruby 4tube.rb`.

### Database

This project requires a working SQL database. The following assumes MySQL, but it should work with other backends.

Tweak [config.json](https://github.com/fourtube/fourtube/wiki/Config.Json) to your needs.

### Packages'n'code

TL;DR, with MySQL DB:

    apt-get install ruby-nokogiri ruby-sequel ruby-mysql2 ruby-dev g++ libtag1-dev
    git clone https://github.com/fourtube/fourtube/
    cd fourtube
    cp config.json.template config.json
    vim config.json
    gem install taglib-ruby -i /tmp/
    mkdir lib/taglib
    mv /tmp/gems/taglib-ruby-0.*/lib/taglib* lib/taglib/
    ruby 4tube.rb

More info in the [Requirements](https://github.com/fourtube/fourtube/wiki/Requirements) wiki page.

## Wiki

For more info, head over the [wiki](https://github.com/fourtube/fourtube/wiki/Home).
