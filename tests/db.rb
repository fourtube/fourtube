#!/usr/bin/ruby
# encoding: utf-8

require "pp"
require "sequel"
require "test/unit"

DB = Sequel.sqlite

class TestDB < Test::Unit::TestCase
    require_relative "../lib/db.rb"

    def testAllTheThings()
        yid = "AAAAAAAAAAA"
        DBUtils.add_yid(yid)

        assert_nothing_raised do
            DBUtils.add_yid(yid)
        end

        assert_equal(1, DBUtils.get_nb_videos())
        assert_equal([yid], DBUtils.get_all_yids_without_infos().sort)
        assert_equal("", DBUtils.get_downloaded_from_yid(yid))
        assert_equal(nil, DBUtils.get_retried(yid))
        assert_equal(yid, DBUtils.pop_yid_to_download())

        DBUtils.set_downloaded(yid, "DONE")
        assert_equal(nil, DBUtils.pop_yid_to_download())

        DBUtils.set_downloaded(yid, "RETRY: {\"toto\":\"tutu\"}")
        assert_equal(yid, DBUtils.pop_yid_to_download())
        assert_equal({"toto"=>"tutu"}, DBUtils.get_retried(yid))

        DBUtils.update_video_infos_from_hash(yid, {title: "titre"})
        assert_equal("titre", DBUtils.get_video_infos(yid)[:title])
    end
end

