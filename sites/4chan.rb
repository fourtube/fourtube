#!/usr/bin/ruby1.9.1
# encoding: utf-8

$: << File.join(File.dirname(__FILE__))
$: << File.join(File.dirname(__FILE__),"..","lib")

# TODO require relative
require "fetcher.rb"
require "basicyoutube.rb"

class Fetcher4chan < BasicYoutube

    def get_yids()
        html = fetch_url(url: @url)
        chanpatt=/watch\?v=(...<wbr>........)/
        return html.split(/<\/?a/).map{|l| l[chanpatt,1]}.compact.uniq.map{|yi|yi.gsub("<wbr>","")}.select {|yi| yi=~Fetcher::YIDPATTERN}
    end
end

Fetcher4chan.new( url: "https://boards.4chan.org/b/",
                 wait: 10*60,
                 name: "4chan_b")


