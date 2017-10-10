#!/usr/bin/ruby
# encoding: utf-8

require "test/unit"

class TestFetcher < Test::Unit::TestCase
    require_relative "../lib/fetcher.rb"

    def testManageSites
        Fetcher.reset_sites()
        f1 = Fetcher.new()
        assert_equal(Fetcher.sites, [f1])
        assert_equal(f1.name, "Fetcher")
        assert_equal(f1.wait, 1800)
        assert_equal(f1.url, nil)
        assert_equal(f1.to_s, "Fetcher('')")
        assert_equal(f1.last_check, 0)
    end

    def testExtractYids()
        f = Fetcher.new()

        test_data = [
            ["""lolololilol""", []],
            ["""youtube.com/watch?v=aaaAAAzzz_-""", ["aaaAAAzzz_-"]],
            ["""youtube.com/watch?v=aaaAAAzzz_-\nyoutube.com/watch?v=zzz_-zzz_zZ""", ["aaaAAAzzz_-", "zzz_-zzz_zZ"]],
            ["""youtube.com/watch?v=aaaAAAzzz_-youtube.com/watch?v=zzz_-zzz_zZ""", ["aaaAAAzzz_-", "zzz_-zzz_zZ"]],
            ["""youtu.be/aaaAAAzzz_-youtube.com/v/zzz_-zzz_zZ""", ["aaaAAAzzz_-", "zzz_-zzz_zZ"]],
        ]
        test_data.each do |input, output|
            assert_equal(f.extract_yids_from_string(input).sort, output.sort)
        end
    end

end

