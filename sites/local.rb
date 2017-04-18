#!/usr/bin/ruby
# encoding: utf-8

require_relative "../lib/fetcher.rb"

class LocalFetcher < Fetcher
    def initialize(url)
        @url = url
        add_source(self)      # Don't forget that !
        @file_path = @url.sub("file://","")
    end

    def get_yids()
        yids = []
        return yids unless File.exist?(@file_path)
        File.open(@file_path,"r").each_line do |l|
            case l
            when /youtube.com\/watch\?v=(#{Fetcher::YIDPATTERN})/
                yids << $1
            when /youtube.com\/embed\/(#{Fetcher::YIDPATTERN})/
                yids << $1
            when /youtube.com\/v\/(#{Fetcher::YIDPATTERN})/
                yids << $1
            when /youtu.be\/(#{Fetcher::YIDPATTERN})/
                yids << $1
            when /^\s*(#{Fetcher::YIDPATTERN})\s*$/
                yids << $1
            end
        end
        File.open(@file_path,"w") do |f|
            f.truncate(0)
        end
        return yids
    end

    def wait
        return 5
    end

    def name
        return "LocalFetcher"
    end
end

LocalFetcher.new("file://to_dl")
