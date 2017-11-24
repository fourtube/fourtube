#!/usr/bin/ruby
# encoding: utf-8
require "optparse"

begin
    require_relative "lib/db.rb"
rescue Exception => e
    $stderr.puts "Please fix your database access / creds in config.json"
    exit 1
end
require_relative "lib/fetcher.rb"
require_relative "lib/logger.rb"
require_relative "lib/utils.rb"

$YT_DELETED_VIDEO_REASONS = [
    "This video does not exist.",
    "This video is not available.",
    "The YouTube account associated with this video has been terminated due to multiple third-party notifications of copyright infringement",
    "This video has been removed by the user",
    "This video has been removed for violating YouTube's Terms of Service.",
    "This video is no longer available because the YouTube account associated with this video has been terminated.",
    "This video is private",
    "This video is no longer available because the uploader has closed their YouTube account",
    "This video has been removed for violating YouTube's policy on nudity or sexual content.",
    "This video has been removed for violating YouTube's policy on violent or graphic content.",
    "This video has been removed for violating YouTube's policy on harassment and bullying."
]
$YT_COUNTRY_BLOCKED_MSG = [
    /blocked it in your country/,
    /not available on this country domain/,
    /This video contains content from .* who has blocked it on copyright grounds/,
]

class Main
    require "fileutils"
    require "json"
    $: << File.join(File.dirname(__FILE__),"lib/taglib")
    require "taglib"

    def initialize(options)
        @log = MyLogger.new()
        @log.add_logger(Logger.new(STDOUT))
        @arguments = options
        load_conf(@arguments[:config])
        if @arguments[:logfile]
            @log.add_logger(Logger.new(@arguments[:logfile]))
        end

        @threads=[]
    end

    def load_sites
        $CONF["sites"].each do |site|
            filename = site+".rb" unless site.end_with?(".rb")
            path = File.join("sites",filename)
            begin
                require_relative path
            rescue LoadError=>e
                @log.warn "Cannot load #{path}"
            end
        end
    end

    def load_conf(file)
        unless File.exist?(file)
            @log.err "Couldn't find config file #{file}."
            exit 1
        end
        begin
            $CONF = JSON.parse(File.read(file))
        rescue Exception => e
            @log.err "Problem opening config file #{file}#"
            raise e
        end
    end

    def start_fetcher_threads()
        load_sites()
        if Fetcher.sites.empty?
            @log.err "Didn't find any site to parse for youtube URL."
            @log.err "Add some in config.json, maybe?"
            exit 1
        end

        @fetcher_threads = []
        tick = 5 # Verify everything every tick
        t = Thread.new{
            @log.info "Starting fetcher thread"
            while true
                now = Time.now().to_i
                # Retry when we've waited "wait" time + up to 10% of wait, to appear not too bot-y
                Fetcher.sites.select{|site| now - site.last_check > (site.wait*(1 + (rand() / 10))) }.each do |site|
                    count = 0
                    begin
                        site.get_yids().each { |yid|
                            #@log.info "#{site} found #{yid}"
                            DBUtils.add_yid(yid, site.name)
                            count += 1
                        }
                        @log.info "#{site} found #{count} videos. Will retry in #{site.wait} seconds" unless site.wait < 30
                    rescue SocketError => e
                        # Internet is down, let's wait for a bit
                        @log.err "Failed to fetch yids from #{site}. Internet or your proxy is down, let's retry later"
                    rescue Exception => e
                        # TODO don't break but send an email or something
                        @log.err "Failed to fetch yids from #{site}"
                    end
                    site.last_check = now
                end
                sleep tick
            end
        }
        t.abort_on_exception = true
        return t
    end

    def update_video_infos(infos)
        yid = infos["yid"]
        if infos["status"] == "ok"
            DBUtils.update_video_infos_from_hash(yid, infos["infos"])
            DBUtils.save_thumbs(yid, infos["thumbs"])
        else
            reason = YoutubeUtils.get_reason(yid)
            DBUtils.update_video_infos_from_hash(yid, {downloaded: reason, deletion: Time.now()})
        end
    end

    def start_informer_threads()
        @informer = Thread.new {
            @log.info "Starting informer thread"
            Thread.current[:name]="Informer"
            while true
                count = 0
                if $CONF["youtube_key"] and $CONF["youtube_key"].size > 5
                    DBUtils.get_all_yids_without_infos.each_slice(10).to_a.each do |yid_slice|
                        YoutubeUtils.get_batch_infos_with_key(yid_slice, $CONF["youtube_key"]).each do |infos|
                            yid = infos["yid"]
                            if infos["infos"][:duration] < $CONF["download"]["minimum_duration"]
                     #           @log.info("#{infos["infos"][:duration]} < #{$CONF["download"]["minimum_duration"]} setting downloaded to #{DBUtils::DLDONE}")
                                DBUtils.set_downloaded(yid)
                                infos["infos"][:bien] = false
                            end
                            if infos["infos"][:duration] > $CONF["download"]["maximum_duration"]
                     #           @log.info("#{infos["infos"][:duration]} > #{$CONF["download"]["maximum_duration"]} setting downloaded to #{DBUtils::DLDONE}")
                                DBUtils.set_downloaded(yid)
                                infos["infos"][:bien] = false
                            end
                            update_video_infos(infos)
                            count+=1
                        end
                    end
                else
                    DBUtils.get_all_yids_without_infos.each do |yid|
                        update_video_infos(YoutubeUtils.get_infos_without_key(yid))
                        count+=1
                        sleep 5 # We don't want to hit the youtube.com website too much and be seen too bot-y
                    end
                end
                @log.info "Informer updated #{count} videos infos" unless count == 0
                sleep 5
            end
        }
        @informer.abort_on_exception = true
        return @informer
    end

    def add_cover(fmp4,image_data)
        if not fmp4 =~ /\.mp4$/
            @log.warn "ERROR: file not MP4, not adding nice tags"
        else
            cover_art = TagLib::MP4::CoverArt.new(TagLib::MP4::CoverArt::JPEG, image_data)
            item = TagLib::MP4::Item.from_cover_art_list([cover_art])
            TagLib::MP4::File.open(fmp4) do |mp4|
                mp4.tag.item_list_map.insert('covr', item)
                mp4.save
            end
        end
    end

    def ytdlfail(yid, errmsg)
        DBUtils.set_downloaded(yid, DBUtils::YTDLFAIL)
        @log.warn "The current version of youtube-dl failed to download #{yid} with error #{errmsg}."
        @log.warn "Please update your youtube-dl version."
        @log.warn "You can also re-run the last youtube-dl command with all the verbose flags to debugi"
    end

    def do_error(error_message, yid, proxy_to_try, tried=false)
        @log.debug "Handling error #{error_message}"
        case error_message
        when /#{yid}: YouTube said: (.*)$/i
            yt_error = $1
            case yt_error
            when Regexp.union($YT_COUNTRY_BLOCKED_MSG)
                if tried
                    DBUtils.set_downloaded(yid, "RETRY: "+JSON.generate(tried.merge(proxy_to_try)))
                else
                    DBUtils.set_downloaded(yid, "RETRY: {}")
                end
            when /Playback on other websites has been disabled by the video owner./
                err_msg = "Youtube said '#{yt_error}'"
                DBUtils.set_downloaded(yid, "#{DBUtils::YTERROR} #{yt_error}")
                @log.warn err_msg
#            when /content too short/
                # let's just retry later
#                    ytdlfail(yid, yt_error)
            when /Please sign in to view this video./
                _msg = ""
                if $CONF["youtube_username"]
                    # WTF we are signed in
                    _msg="#{DBUtils::YTDLFAIL} #{yt_error}"
                else
                    _msg="#{DBUtils::YTDLFAIL} need credentials"
                end
                @log.warn _msg
                DBUtils.set_downloaded(yid, _msg)
            when Regexp.union($YT_DELETED_VIDEO_REASONS)
                # Unrecoverable error, videos sent to Youtube Limbo.
                err_msg = "Youtube said '#{yt_error}'"
                DBUtils.set_downloaded(yid, "#{DBUtils::YTERROR} #{yt_error}")
                @log.warn err_msg
            else
                raise Exception.new("Problem with download of #{yid} : Unknown YouTube error '#{yt_error}'")
            end
        when /The uploader has not made this video available in your country/
            if tried
                DBUtils.set_downloaded(yid, "RETRY: "+JSON.generate(tried.merge(proxy_to_try)))
            else
                DBUtils.set_downloaded(yid, "RETRY: {}")
            end
        when /Signature extraction failed/
            ytdlfail(yid, error_message)
            return
        when /would lead to an infinite loop/
            DBUtils.set_downloaded(yid, DBUtils::RETRYDL)
        when /Connection reset by peer/
            DBUtils.set_downloaded(yid, DBUtils::RETRYDL)
        when /content too short/i
            DBUtils.set_downloaded(yid, DBUtils::RETRYDL)
        when /This live stream recording is not available/
            ytdlfail(yid, error_message)
            return
        else
            DBUtils.set_downloaded(yid, "#{DBUtils::YTDLFAIL} #{error_message}")
            raise Exception.new("Problem with download of #{yid} : Unknown youtube-dl error '#{error_message}'")
        end
    end

    def do_download(yid)
        video_file = nil
        Dir.chdir($CONF["download"]["tmp_dir"])

        available_proxies = $CONF["download"]["proxies"]

        proxy_cmd = ""
        tried = DBUtils.get_retried(yid)
        if tried
            @log.info "We need to retry with a proxy. Already tried: #{tried}"
            available_proxies =  available_proxies.dup.delete_if {|k,_| tried.key?(k)}
            if available_proxies.empty?
                @log.warn "No more proxy to try =("
                # TODO mark the download accordingly
                return
            end
            proxy_to_try = [available_proxies.to_a.sample()].to_h
            proxy_cmd = "--proxy #{proxy_to_try.first[1]}"
        end
        command = "#{@youtube_dl_cmd} #{proxy_cmd} https://www.youtube.com/watch?v=#{yid} 2>&1"
        @log.debug command
        DBUtils.set_downloaded(yid, msg=DBUtils::DLING)
        ytdl_msg = nil
        IO.popen(command) do |io|
            ytdl_msg = io.read.split("\n").join(" ")
        end

        case ytdl_msg
        when /error: (.+)$/i
            do_error(ytdl_msg, yid, proxy_to_try, tried)
            return nil
        when /WARNING: (.+)$/
            warn = $1
            if warn!=""
                @log.warn warn unless warn=~/Your copy of avconv is outdated, update avconv to version/
                if warn=~/unable to log in: .*password/i
                    warn = "Use a webbrowser to connect to the YT Account, which was probabbly flagged as bot/spam"
                    raise warn
                end
            end
        when /has already been downloaded and merged/
            # continue
        when ""
            # Continue
        else
            raise Exception.new("WTF #{ytdl_msg}")
        end
        @log.success "Downloading finished, now post processing"
        output_files = Dir.glob("*#{yid}*",File::FNM_DOTMATCH)
        if output_files.size > 2
            pp output_files
            raise "Too many output files in #{`pwd`}"
        end
        video_file = output_files.reject{ |f| f=~/\.jpg$/ }[0]
        jpg_file = output_files.select{|f| f=~/\.jpg$/}[0]
        if not jpg_file or not File.exist?(jpg_file)
            if @video_converter_cmd
                `#{@video_converter_cmd} -i \"#{video_file}\" -vframes 1 -f image2 \"#{jpg_file}\"`
            end
        end
        if File.exist?(jpg_file)
            add_cover(video_file, File.read(jpg_file))
            File.delete(jpg_file)
        end
        FileUtils.mv(video_file, $CONF["download"]["destination_dir"])
        video_file = File.join($CONF["download"]["destination_dir"], video_file)
        @log.success "PostProcessing #{yid} over."
        DBUtils.set_downloaded(yid)
        file_size = File.stat(video_file).size.to_i
        DBUtils.update_video_infos_from_hash(yid,{file: File.basename(video_file), size: file_size})
        return nil
    end

    def start_downloader_threads()
        FileUtils.mkdir_p($CONF["download"]["destination_dir"])
        FileUtils.mkdir_p($CONF["download"]["tmp_dir"])

        @youtube_dl_cmd = $CONF["download"]["youtube_dl_cmd"] || `which youtube-dl`.strip()
        if @youtube_dl_cmd == ""
            @log.err "Please update \"youtube_dl_cmd\" in config.json to your local installation of youtube-dl, or remove that key altogether, to use the one in your PATH"
            exit 1
        else
            begin
                res = `#{@youtube_dl_cmd} --version | egrep "^20[0-9.]+$"`
                raise unless res=~/^20[0-9.]+$/
            rescue Exception => e
                @log.err "'#{@youtube_dl_cmd}' is not a valid youtube-dl binary"
                exit
            end
        end
        #
        # TODO move to "download"?
        if not $CONF["youtube_username"]
            @log.warn "You have not set a Youtube username in config.json."
            @log.warn "You won't be able to download '18+' videos."
        end

        @video_converter_cmd = $CONF["download"]["video_converter_cmd"] || "avconv"
        begin
            res = `#{@video_converter_cmd} -version 2>&1 | egrep "Copyright"`
            raise unless res=~/developers/
        rescue Exception => e
            @log.warn "'#{@video_converter_cmd}' is not a valid video conversion command (use ffmpeg or avconv)"
            @video_converter_cmd = nil
        end

        if $CONF["download"]["youtube_dl_extra_args"]
            @youtube_dl_cmd << " " << $CONF["download"]["youtube_dl_extra_args"]
        end
        if $CONF["youtube_username"]
            @youtube_dl_cmd << " -u \"#{$CONF['youtube_username']}\""
            @youtube_dl_cmd << " -p \"#{$CONF['youtube_password']}\""
        end

        if not ($CONF["youtube_key"] and $CONF["youtube_key"].size > 5)
            @log.warn "You have not set a Youtube API key in config.json."
        end

        # TODO have more than 1 ?
        @downloader = Thread.new {
            @log.info "Starting downloader thread"
            while true
                yid = DBUtils.pop_yid_to_download(minimum_duration: $CONF["download"]["minimum_duration"],
                                                  maximum_duration: $CONF["download"]["maximum_duration"])
                if yid
                    cur_dir=Dir.pwd()
                    begin
                        do_download(yid)
                        nb_to_dl = DBUtils.get_nb_to_dl()
                        @log.info "Still #{nb_to_dl} videos to download"
                    rescue Exception => e
                        @log.err "Exception when downloading #{yid}"
                        raise e
                    end
                    Dir.chdir(cur_dir)
                else
                    sleep 60
                end
            end
            sleep 1
        }
        @downloader.abort_on_exception = true
        return @downloader
    end

    def start_local_downloaded_threads()
        @local_downloader = Thread.new{
            #Inotify stuff
            while true
            end
            sleep 10
        }
        @local_downloader.abort_on_exception = true
        return @local_downloader
    end

    def go()
        DBUtils.clean_dl()

        failed_dl_vids = DBUtils.get_ytdlfail().size
        if failed_dl_vids > 0
            @log.warn "You have #{failed_dl_vids} videos that youtube-dl couldn't download."
        end
        DBUtils.retry_old_failed_videos()

        @threads << start_informer_threads() if @arguments[:inform]
        @threads << start_fetcher_threads() if @arguments[:fetch]
        @threads << start_downloader_threads() if @arguments[:download]
        @threads.each {|t| t.join()}
    end

end

def main(options)
    m = Main.new(options)
    m.go()
end

trap("INT"){
    # TODO
    # remove ytdl temps,
    exit
}

options = {
    config: "config.json",
    download: true,
    fetch: true,
    inform: true
}
OptionParser.new do |opts|
    used_only = false
    opts.banner = "Usage: #{__FILE__}"
    opts.on("--download-only") {|v|
        options[:download] = true
        options[:fetch] = false
        options[:inform] = false
        used_only = true
    }
    opts.on("--fetch-only") {|v|
        options[:download] = false
		options[:fetch] = true
		options[:inform] = false
		used_only = true
    }
    opts.on("--inform-only") {|v|
        options[:download] = false
		options[:fetch] = false
		options[:inform] = true
		used_only = true
    }
    opts.on("--[no-]download") {|v|
        raise Exception.new("Can't use --[no-]download with a --*-only switch on ") if used_only
        options[:download] = v
    }
    opts.on("--[no-]fetch") {|v|
        raise Exception.new("Can't use --[no-]fetch with a --*-only switch on ") if used_only
        options[:fetch] = v
    }
    opts.on("--[no-]inform") {|v|
        raise Exception.new("Can't use --[no-]inform with a --*-only switch on ") if used_only
        options[:inform] = v
    }
    opts.on("--config config") {|v|
        options[:config] = v
    }
    opts.on("--logfile logfile") {|v|
        options[:logfile] = v
    }
end.parse!


main(options)
