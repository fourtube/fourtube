#!/usr/bin/ruby
# encoding: utf-8

require_relative "../lib/fetcher.rb"

class LocalFetcher < Fetcher
    def initialize(url)
        super()
        @url = url
        @file_path = @url.sub("file://","")
    end

    def get_yids()
      return [] unless File.exist?(@file_path)
      yids = []
      begin
        File.open(@file_path,"r").each_line do |l|
            yids.concat(extract_yids_from_string(l))
        end
        File.open(@file_path,"w") do |f|
            f.truncate(0)
        end
      rescue Errno::EACCES
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
