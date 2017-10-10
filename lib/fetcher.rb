#!/usr/bin/ruby
# encoding: utf-8

class Fetcher

    YIDPATTERN = /([a-zA-Z0-9_-]{11})/

    URL_PATTERNS = [
        /youtube.com\/watch\?v=#{YIDPATTERN}/,
        /youtube.com\/v\/#{YIDPATTERN}/,
        /youtu.be\/#{YIDPATTERN}/,
        /youtube.com\/oembed\?url=http%3A\/\/www.youtube.com\/watch\?v%3D#{YIDPATTERN}/,
        /www.youtube.com\/embed\/#{YIDPATTERN}/
    ]

    @@sites = []

    def initialize()
        add_source(self)
    end

    def self.reset_sites()
        @@sites = []
    end

    def self.sites
        @@sites
    end

    def add_source(thing)
        @@sites << thing
    end

    def name
        return @name || self.class.to_s
    end

    def wait
        return @wait || 30*60
    end

    def url
        return @url
    end

    def to_s()
        return "#{name()}('#{url}')"
    end

    def last_check=(last)
        @last = last
    end

    def last_check
        return (@last ||= 0)
    end

    def extract_yids_from_string(string)
        yids = []
        Fetcher::URL_PATTERNS.each do |p|
            yids.concat(string.scan(p).map{|x| x[0]})
        end
        return yids.uniq
    end

end
