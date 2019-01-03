require "test/unit"
require "pp"
require "json"

class TestUtils < Test::Unit::TestCase
    require_relative "../lib/utils.rb"
    $CASES =
        # Fail video
        { "pute" => {
            deleted: "This video does not exist.",
            views: Proc.new{|x| x == nil},
            published: nil,
            title: nil,
            uploader: nil,
            duration: nil,
            thumbs_max: nil,
            thumbs_mq: nil,
            status: "error"
        },
        # Gangnamstyle
         "9bZkp7q19f0" => {
            deleted: "Video not deleted",
            views: Proc.new{|x| x > 2712600000},
            published: "2012-07-15T07:46:32.000Z",
            title: "PSY - GANGNAM STYLE(강남스타일) M/V",
            duration: 253,
            description: "PSY - ‘I LUV IT’ M/V @ https://youtu.be/Xvjnoagk6GU\nPSY - ‘New Face’ M/V @https://youtu.be/OwJPPaEyqhI\n\nPSY - 8TH ALBUM '4X2=8' on iTunes @\nhttps://smarturl.it/PSY_8thAlbum\n\nPSY - GANGNAM STYLE(강남스타일) on iTunes @ http://smarturl.it/PsyGangnam\n\n#PSY #싸이 #GANGNAMSTYLE #강남스타일\n\nMore about PSY@\nhttp://www.psypark.com/\nhttp://www.youtube.com/officialpsy\nhttp://www.facebook.com/officialpsy\nhttp://twitter.com/psy_oppa\nhttps://www.instagram.com/42psy42\nhttp://iTunes.com/PSY\nhttp://sptfy.com/PSY\nhttp://weibo.com/psyoppa\nhttp://twitter.com/ygent_official",
            uploader: "officialpsy",
            thumbs_max: ["https://i.ytimg.com/vi/9bZkp7q19f0/maxresdefault.jpg"],
            thumbs_mq: ["https://i.ytimg.com/vi/9bZkp7q19f0/mqdefault.jpg"],
            status: "ok"
        },
        # Old deleted vid
         "3ZOeMVHrFRE" => {
            deleted: "This video is no longer available because the YouTube account associated with this video has been terminated.",
            views: Proc.new{|x| x==nil},
            published: nil,
            title: nil,
            uploader: nil,
            duration: nil,
            thumbs_max: nil,
            thumbs_mq: nil,
            status: "error"
        }
        }

    def test_duration()
        cases = [
            # input , expected
            ["lol", nil],
            ["PT3H",3*60*60],
            ["PT3M37S",3*60+37],
            ["PT3H37S",3*60*60+37],
            ["PT3H8M37S",3*60*60+8*60+37],
        ]
        cases.each do |c|
            assert_equal(c[1], YoutubeUtils.duration_to_seconds(c[0]))
        end
    end

    def test_pull_from_youtube()
        $CASES.each do |y,t|
            # Pulling html page from youtube only once
            yid = y
            html = Net::HTTP.get(URI.parse("https://www.youtube.com/watch?v=#{yid}"))
            assert_equal(t[:deleted], YoutubeUtils.get_reason(yid, html), "Testing reason for #{yid}")
            assert(t[:views].call(YoutubeUtils.get_views(yid, html)), "Testing views for #{yid}")
            assert_equal(t[:published] ? t[:published][0..9] : nil , YoutubeUtils.get_published(yid, html), "Testing published for #{yid}")
            assert_equal(t[:title], YoutubeUtils.get_title(yid, html), "Testing title for #{yid}")
            assert_equal(t[:description], YoutubeUtils.get_description(yid, html), "Testing description for #{yid}")
            assert_equal(t[:uploader], YoutubeUtils.get_uploader(yid, html), "Testing uploader for #{yid}")
            assert_equal(t[:duration], YoutubeUtils.get_duration(yid, html), "Testing duration for #{yid}")
        end
    end

    def test_get_infos()
        key = JSON.parse(File.read("config.json"))["youtube_key"]
        if key and key.size > 5
            yids = $CASES.keys
            YoutubeUtils.get_batch_infos_with_key(yids, key).each do |infos|
                yid = infos["yid"]
                expected = $CASES[yid]
                val = infos["infos"]
                assert_equal(expected[:status], infos["status"], "Checking status for YoutubeUtils.get_infos_with_key #{yid}")
                assert_equal(expected[:published], val[:published], "Checking published for YoutubeUtils.get_infos_with_key #{yid}")
                assert_equal(expected[:uploader], val[:uploader], "Checking uploader for YoutubeUtils.get_infos_with_key #{yid}")
                assert_equal(expected[:duration], val[:duration], "Checking duration for YoutubeUtils.get_infos_with_key #{yid}")
                assert_equal(expected[:description], val[:description], "Checking description for YoutubeUtils.get_infos_with_key #{yid}")
                assert_equal(expected[:title], val[:title], "Checking title for YoutubeUtils.get_infos_with_key #{yid}")
                assert_equal(expected[:thumbs_mq], infos["thumbs"], "Checking thumbs for YoutubeUtils.get_infos_with_key #{yid}")
                if infos["status"] == "error"
                    assert_equal(expected[:deleted], val[:deleted], "Checking deleted for YoutubeUtils.get_infos_with_key #{yid}")
                end
            end
        end
        $CASES.each do |yid, t|
            infos = YoutubeUtils.get_infos_without_key(yid)
            val = infos["infos"]
            assert_equal(t[:status], infos["status"], "Checking status for YoutubeUtils.get_infos_without_key #{yid}")
            assert_equal(t[:published] ? t[:published][0..9] : nil, val[:published], "Checking published for YoutubeUtils.get_infos_without_key #{yid}")
            assert_equal(t[:uploader], val[:uploader], "Checking uploader for YoutubeUtils.get_infos_without_key #{yid}")
            assert_equal(t[:duration], val[:duration], "Checking duration for YoutubeUtils.get_infos_without_key #{yid}")
            assert_equal(t[:description], val[:description], "Checking description for YoutubeUtils.get_infos_without_key #{yid}")
            assert_equal(t[:title], val[:title], "Checking title for YoutubeUtils.get_infos_without_key #{yid}")
            assert_equal(t[:thumbs_max], infos["thumbs"], "Checking thumbs for YoutubeUtils.get_infos_without_key #{yid}")
            if infos["status"] == "error"
                assert_equal(t[:deleted], val[:deleted], "Checking deleted for YoutubeUtils.get_infos_without_key #{yid}")
            end
        end

    end
end
