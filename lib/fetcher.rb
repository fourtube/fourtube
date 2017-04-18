#!/usr/bin/ruby
# encoding: utf-8

class Fetcher
    YIDPATTERN = /([a-zA-Z0-9_-]{11})/

    @@sites = []

    def self.sites
        @@sites
    end

    def add_source(thing)
        @@sites << thing
    end

    def name
        return @name || self.class.to_s
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
end
