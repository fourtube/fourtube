#!/usr/bin/ruby
# encoding: utf-8

module DBUtils
    require "sequel"
    require "json"
    if not Object.const_defined?(:DB)
        c = JSON.parse(File.read(File.join(File.dirname(__FILE__),"..","config.json")))["db"]
        DB = Sequel.connect("#{c['backend']}://#{c['host']}/#{c['table']}?user=#{c['user']}&password=#{c['pass']}")
    end

    Sequel::Model.plugin(:schema)

    # TODO same with DONE, etc
    RETRYDL = ""
    DLDONE = "DONE"
    DLING = "DLING"
    YTERROR = "YTERROR"
    YTDLFAIL = "YTDLFAIL"

    class Thumbs < Sequel::Model(:thumbs)
        set_schema do
            primary_key :id
            String      :yid, :unique => true, :empty => false
            String      :urlthumb, :unique => false
            Bool        :cached, default: false
        end
        create_table unless table_exists?
    end

    class Infos < Sequel::Model(:infos)
        def before_create
            self.timestamp = Time.now
            super
        end
        set_schema do
            primary_key :id
            String      :yid, :unique => true, :empty => false
            DateTime    :timestamp
            String      :title
            File        :sig1
            String      :source
            String      :downloaded, default: ""
            Bool        :bien
            DateTime    :published
            DateTime    :deletion
            String      :uploader
            Fixnum      :duration
            String      :description
            String      :comment
            String      :file
            Fixnum      :views
            Bignum      :size
        end
        create_table unless table_exists?
    end

    def DBUtils.add_yid(yid, src="UNKNOWN")
        begin
            Infos.insert(yid: yid, timestamp: Time.now(), source:src, downloaded:'')
        rescue Sequel::UniqueConstraintViolation => e
            # We don't care about that
        end
    end

    def DBUtils.clean_dl()
        Infos.where(downloaded: DLING).update(downloaded: "")
        Infos.grep(:downloaded, "%402%").update(downloaded: "")
    end

    def DBUtils.get_all_bien()
        return Infos.where(:bien, true)
    end

    def DBUtils.get_all_yids_without_infos()
        return Infos.where(title: nil, downloaded:"").order(Sequel.desc(:timestamp)).limit(15).select_map(:yid)
    end

    def DBUtils.get_dls_from_source(source, delta)
        Infos.where(source: source).where{timestamp > (Time.now() - delta)}.count
    end

    def DBUtils.get_downloaded_from_yid(yid)
        return Infos.where(:yid => yid).get(:downloaded)
    end

    def DBUtils.get_nb_videos()
        return Infos.count()
    end

    def DBUtils.get_retried(yid)
        d = Infos.where(:yid => yid).get(:downloaded)
        retry_json = d[/^RETRY: ({.*})$/,1]
        return retry_json ? JSON.parse(retry_json) : nil
    end

    def DBUtils.get_source_names()
        return Infos.select(:source).distinct
    end

    def DBUtils.get_thumbsurl_from_yid(yid)
        Thumbs.where(yid: yid).order(Sequel.asc(:timestamp)).select_map(:urlthumb)
    end

    def DBUtils.get_video_infos(yid)
        return Infos.where(yid: yid).first
    end

    def DBUtils.get_ytdlfail()
        Infos.grep(:downloaded, "YTDLFAIL%").map(:downloaded)
    end

    def DBUtils.pop_yid_to_download(minimum_duration:nil, maximum_duration:nil)
        normal = Infos.where(downloaded: '').exclude(source: '')
        if minimum_duration
            normal = normal.where('duration > ?', minimum_duration)
        end
        if maximum_duration
            normal = normal.where('duration < ?', maximum_duration)
        end
        if normal
            normal.order(Sequel.asc(:timestamp)).get(:yid)
        else
            # If we have RETRY, we already have popped, no need to re-check duration boudaries
            Infos.grep(:downloaded, 'RETRY: %').exclude(source: '').order(Sequel.asc(:timestamp)).get(:yid)
        end
    end

    def DBUtils.retry_old_failed_videos(delta=(86400 * 30))
        Infos.grep(:downloaded, "YTDLFAIL%").where{timestamp < Time.now() - delta}.update(downloaded: RETRYDL)
    end

    def DBUtils.save_thumbs(yid, thumbs)
        Thumbs.multi_insert( thumbs.collect {|url|
            {yid: yid, urlthumb: url}
        })
    end

    def DBUtils.set_downloaded(yid, msg=DLDONE)
        Infos.where(yid: yid).update(downloaded: msg)
    end

    def DBUtils.update_video_infos_from_hash(yid, hash)
        # TODO consistent notation
        Infos.where(yid: yid).update(hash)
    end
end

