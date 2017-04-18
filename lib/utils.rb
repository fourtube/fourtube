#!/usr/bin/ruby
# encoding: utf-8

module YoutubeUtils
    require "date"
    require "net/http"
    require "nokogiri"

    def YoutubeUtils.get_batch_infos_with_key(yids, key)
        results = []
        if yids.class == String
            yids = [yids]
        end

        res = Net::HTTP.get(URI.parse("https://www.googleapis.com/youtube/v3/videos?key=#{key}&part=snippet,contentDetails&id=#{yids.join(',')}"))
        doc=JSON.parse(res)
        doc["items"].each do |item|
            hash_result= {"yid"=> item["id"], "status" => "error"}
            if item["contentDetails"]
                values = {
                    published: item["snippet"]["publishedAt"],
                    title: item["snippet"]["title"],
                    description: item["snippet"]["description"],
                    uploader: item["snippet"]["channelTitle"],
                    duration: YoutubeUtils.duration_to_seconds(item["contentDetails"]["duration"]),
                    views: YoutubeUtils.get_views(item["id"])
                }
                hash_result["status"] = "ok"
                hash_result["infos"] = values
                hash_result["thumbs"] = [item["snippet"]["thumbnails"]["medium"]["url"]]
            else
                hash_result["infos"] = Hash.new(nil)
                hash_result["infos"][:deleted] = YoutubeUtils.get_reason(item["id"])
            end
            results << hash_result
        end
        return results
    end

    def YoutubeUtils.get_infos_without_key(yid)
        hash_result =  {"yid"=> yid, "status" => "error"}

        html = Net::HTTP.get(URI.parse("https://www.youtube.com/watch?v=#{yid}"))

        values = {
            published: YoutubeUtils.get_published(yid, html=html),
            title: YoutubeUtils.get_title(yid, html=html),
            description: YoutubeUtils.get_description(yid, html=html),
            uploader: YoutubeUtils.get_uploader(yid, html=html),
            duration: YoutubeUtils.get_duration(yid, html=html),
            views: YoutubeUtils.get_views(yid, html=html)
        }
        hash_result["infos"] = values
        if values[:title] == nil
            # Video failed to get =(
            hash_result["status"] = "error"
            hash_result["infos"][:deleted] = YoutubeUtils.get_reason(yid, html=html)
        else
            hash_result["thumbs"] = YoutubeUtils.get_thumb_urls(yid, html=html)
            hash_result["status"] = "ok"
        end

        return hash_result
    end

    def YoutubeUtils.get_thumb_urls(yid, html=nil)
        html = html || Net::HTTP.get(URI.parse("https://www.youtube.com/watch?v=#{yid}"))
        res = Nokogiri::HTML.parse(html)
        node_urls = res.css('link').select{|x| x.attr('itemprop')=='thumbnailUrl'}
        if node_urls.size > 0
            return node_urls.map{|n| n.attr("href")}
        else
            return nil
        end
    end

    def YoutubeUtils.duration_to_seconds(s)
        case s
        when /P(\d+)DT(\d+)H(\d+)M(\d+)S/
            return ($1.to_i * 86400) + ($2.to_i * 3600) + ($3.to_i * 60) + $4.to_i
        when /PT(\d+)H(\d+)M(\d+)S/
            return ($1.to_i * 3600) + ($2.to_i * 60) + $3.to_i
        when /PT(\d+)H(\d+)M/
            return ($1.to_i * 3600) + ($2.to_i * 60)
        when /PT(\d+)H(\d+)S/
            return ($1.to_i * 3600) + $2.to_i
        when /PT(\d+)M(\d+)S/
            return ($1.to_i * 60) + $2.to_i
        when /PT(\d+)H/
            return ($1.to_i * 3600)
        when /PT(\d+)M/
            return ($1.to_i * 60)
        when /PT(\d+)S/
            return $1.to_i
        end
    end

    def YoutubeUtils.get_reason(yid, html=nil)
        begin
            html = html || Net::HTTP.get(URI.parse("https://www.youtube.com/watch?v=#{yid}"))
            res = Nokogiri::HTML.parse(html)
            msg = res.css("h1.message").text.strip()
            if msg == "This video is unavailable." and res.css("title").text.split("-").size > 1
                return "Video not deleted"
            end
            return res.css("h1.message").text.strip()
        rescue Exception => e
            return "Can't get a reason"
        end
    end

    def YoutubeUtils.get_views(yid, html=nil)
        views = nil
        begin
            html = html || Net::HTTP.get(URI.parse("https://www.youtube.com/watch?v=#{yid}"))
            res = Nokogiri::HTML.parse(html)
            view_div = res.css("div.watch-view-count")
            if not view_div.text.empty?
                views =  view_div.text.split(" ")[0].gsub(",","").to_i
            end
        rescue Exception => e
            log_f = "/tmp/fourtube_fail_#{Time.now.to_i}.log"
            File.open(log_f,"w") do |f|
                f.write html
            end
            $stderr.puts "Fail with #{yid}, html log in #{log_f}"
            raise e
        end
        return views
    end

    def YoutubeUtils.get_published(yid, html=nil)
        html = html || Net::HTTP.get(URI.parse("https://www.youtube.com/watch?v=#{yid}"))
        res = Nokogiri::HTML.parse(html)
        text_date = res.css('meta').select{|x| x.attr('itemprop')=='datePublished'}[0]
        if text_date
            return text_date.attr("content")
        else
            return nil
        end
    end

    def YoutubeUtils.get_title(yid, html=nil)
        html = html || Net::HTTP.get(URI.parse("https://www.youtube.com/watch?v=#{yid}"))
        res = Nokogiri::HTML.parse(html)
        node_title = res.css('meta').select{|x| x.attr('name')=='title'}[0]
        if node_title
            text_title = node_title.attr('content')
            if text_title != nil and text_title != ""
                return text_title
            end
        end
        return nil
    end

    def YoutubeUtils.get_description(yid, html=nil)
        html = html || Net::HTTP.get(URI.parse("https://www.youtube.com/watch?v=#{yid}"))
        res = Nokogiri::HTML.parse(html)
        node_descr = res.css("div#watch-description-text p")
        res = nil
        if node_descr
            res = node_descr.children.map{|x| x.text}.join("\n").gsub(/\n+/) {|lol| lol[1..-1]}
        end
        if res == "" or res == nil
            return nil
        end
        return res
    end

    def YoutubeUtils.get_uploader(yid, html=nil)
        html = html || Net::HTTP.get(URI.parse("https://www.youtube.com/watch?v=#{yid}"))
        res = Nokogiri::HTML.parse(html)
        node_uploader = res.css("div.yt-user-info a")
        res = nil
        if node_uploader[0]
            res = node_uploader[0].text
        end
        if res == "" or res == nil
            return nil
        end
        return res
    end

    def YoutubeUtils.get_duration(yid, html=nil)
        html = html || Net::HTTP.get(URI.parse("https://www.youtube.com/watch?v=#{yid}"))
        res = Nokogiri::HTML.parse(html)
        text_duration = res.css('meta').select{|x| x.attr('itemprop')=='duration'}[0]
        if text_duration
            return YoutubeUtils.duration_to_seconds(text_duration.attr('content'))
        else
            return nil
        end
    end
end
