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
        "/test6" => 
            ["""dTAAsCNK7RA\" target=\"_blank\">Ok Go \"Here It Goes Again\"</a><br>
             89) <a class=\"Bottom\" href=\"http://www.youtube.com/watch?v=LU8DDYz68kM\" target=\"_blank\">Battle at Kruger (lions vs. buffalos vs. crocodiles)</a><br>
             90) <a class=\"Bottom\" href=\"http://www.youtube.com/watch?v=K2cYWfq--Nw\" target=\"_blank\">Daft Hands</a><br>
             91) <a class=\"Bottom\" href=\"http://www.youtube.com/watch?v=o9698TqtY4A\" target=\"_blank\">Human Beatbox</a><br>
             92) <a class=\"Bottom\" href=\"http://www.youtube.com/watch?v=r6tlw-oPDBM\" target=\"_blank\">Most T-Shirts Worn At Once</a><br>
             93) <a class=\"Bottom\" href=\"http://www.youtube.com/watch?v=jU9USxJ9vPs\" target=\"_blank\">Zero G Dog</a><br>
             94) <a class=\"Bottom\" href=\"http://www.youtube.com/watch?v=Ysqh1uzqGrc\" target=\"_blank\">Cuppy Cakes Song</a><br>
             95) <a class=\"Bottom\" href=\"http://www.youtube.com/watch?v=sbRom1Rz8OA\" target=\"_blank\">George Washington</a><br>
             96) <a class=\"Bottom\" href=\"http://www.youtube.com/watch?v=oh87njiWTmw\" target=\"_blank\">Scary Maze Prank</a><br>
             97) <a class=\"Bottom\" href=\"http://www.youtube.com/watch?v=OQSNhk5ICTI\" target=\"_blank\">Double Rainbow</a><br>
             98) <a class=\"Bottom\" href=\"http://www.youtube.com/watch?v=Pa1pIO4_lUY\" target=\"_blank\">Tranquilized Bear Hits Trampoline</a><br>""", 
             ["LU8DDYz68kM", "K2cYWfq--Nw", "o9698TqtY4A", "r6tlw-oPDBM", "jU9USxJ9vPs", "Ysqh1uzqGrc", "sbRom1Rz8OA", "oh87njiWTmw", "OQSNhk5ICTI", "Pa1pIO4_lUY"]],
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
        1.upto(TEST_HTML.size) do |t|
            req = "/test#{t}"
            b = BasicYoutube.new(url: "http://localhost:8001/#{req}")
            assert_equal(b.get_yids().sort, TEST_HTML[req][1].sort) 
        end
    end

end

