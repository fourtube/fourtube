#!/usr/bin/ruby
# encoding: utf-8

require "test/unit"
require "webrick"

class TestBasicYoutube < Test::Unit::TestCase
    require_relative "../sites/basicyoutube.rb"

    TEST_HTML = {
        "/test1" => 
            ["""lolololilol""", []],
        "/test2" => 
            ["""youtube.com/watch?v=aaaAAAzzz_-""", ["aaaAAAzzz_-"]],
        "/test3" => 
            ["""youtube.com/watch?v=aaaAAAzzz_-\nyoutube.com/watch?v=zzz_-zzz_zZ""", ["aaaAAAzzz_-", "zzz_-zzz_zZ"]],
        "/test4" => 
            ["""youtube.com/watch?v=aaaAAAzzz_-youtube.com/watch?v=zzz_-zzz_zZ""", ["aaaAAAzzz_-", "zzz_-zzz_zZ"]],
        "/test5" => 
            ["""youtu.be/aaaAAAzzz_-youtube.com/v/zzz_-zzz_zZ""", ["aaaAAAzzz_-", "zzz_-zzz_zZ"]],
    }

    def restart_webrick()
        @serv_thread.kill if @serv_thread
        @serv_thread = Thread.new do
            s = WEBrick::HTTPServer.new(
                :AccessLog => [],
                :Logger => WEBrick::Log::new("/dev/null", 7),
                :Port => 8001,
            )
            s.mount_proc '/' do |req, res|
                res.body = TEST_HTML[req.path][0]
            end
            s.start
        end
        sleep(1)
    end

    def setup()
        restart_webrick()
    end

    def teardown()
        @serv_thread.exit
    end

    def tests()
        1.upto(5) do |t|
            req = "/test#{t}"
            b = BasicYoutube.new(url: "http://localhost:8001/#{req}")
            assert_equal(b.get_yids().sort, TEST_HTML[req][1].sort) 
        end
    end

end

