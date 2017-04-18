#!/usr/bin/ruby
# encoding: utf-8

require_relative "../lib/fetcher.rb"
require "pp"

class BasicYoutube < Fetcher
    require "net/http"
    require "nokogiri"

    def initialize(url: , post_data:nil,wait:30*60, name:nil, test: false)
        @url = url
        @post_data = post_data
        @wait = wait
        @name = name || self.class.to_s
        add_source(self)
    end

    def fetch_url(url: , headers:{}, post_data:nil, limit:10)
        pp url
        if limit == 0
            # TODO msg
            $stderr.puts "Error, too may redirects for #{url}"
        end
        uri = URI(url)
        if post_data
            req = Net::HTTP::Post.new(uri, headers)
            req.set_form_data post_data
        else
            req = Net::HTTP::Get.new(uri, headers)
        end
        req['User-Agent'] = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/53.0.2785.143 Safari/537.36"

        res = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') {|http|
                http.request(req)
        }
        case res.code
        when "200"
            return res.body
        when "302"
            headers["Referer"]=url
            return fetch_url(url: res['location'], limit: limit - 1, headers: headers)
        when "404"
            return nil
        when "503"
            return nil
        end
        raise "Failure when fetching new yids for #{self}: Unknown http code #{res.code}.\n #{res.body}"
    end

    def parse(html)
        return Nokogiri::HTML(html)
    end

    def get_yids()
        yids = []
        html = fetch_url(url: @url, post_data: @post_data)
        if html
            yids.concat html.scan(/youtube.com\/watch\?v=(#{Fetcher::YIDPATTERN})/).flatten
            yids.concat html.scan(/youtube.com\/embed\/(#{Fetcher::YIDPATTERN})/).flatten
            yids.concat html.scan(/youtube.com\/v\/(#{Fetcher::YIDPATTERN})/).flatten
            yids.concat html.scan(/youtu.be\/(#{Fetcher::YIDPATTERN})/).flatten
        end
        return yids.compact.uniq
    end
end

BasicYoutube.new( 
    url: "https://www.reddit.com/r/DeepIntoYouTube/",
    wait: 2*60*60,
    name: "reddit_deepintoyoutube"
)
BasicYoutube.new( 
    url: "https://www.reddit.com/r/WTF/",
    wait: 30*60,
    name: "reddit_wtf"
)
BasicYoutube.new( 
    url: "https://www.reddit.com/r/WTF/new/",
    wait: 10*60,
    name: "reddit_wtf_new"
)
BasicYoutube.new( 
    url: "http://www.flipsidejapan.com/",
    wait: 5*60*60,
    name: "flipsidejapan"
)
BasicYoutube.new( 
    url: "http://everythingisterrible.blogspot.com/feeds/pages/default",
    wait: 4*60*60,
    name: "everything"
)
BasicYoutube.new( 
    url: "http://www.brain-magazine.fr/articles/page-pute/",
    wait: 24*60*60,
    name: "brain",
)
