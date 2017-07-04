#!/usr/bin/ruby
# encoding: utf-8

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

    def initialize(config_file)
        load_conf(config_file)
        @log = MyLogger.new()

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

        # TODO move to "download"?
        if not $CONF["youtube_username"]
            @log.warn "You have not set a Youtube username in config.json."
            @log.warn "You won't be able to download '18+' videos."
        end

        if not ($CONF["youtube_key"] and $CONF["youtube_key"].size > 5)
            @log.warn "You have not set a Youtube API key in config.json."
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

        load_sites()

        if Fetcher.sites.empty?
            @log.err "Didn't find any site to parse for youtube URL."
            @log.err "Add some in config.json, maybe?"
            exit 1
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
        @fetcher_threads = []
        tick = 5 # Verify everything every tick
        t = Thread.new{
            while true
                now = Time.now().to_i
                # Retry when we've waited "wait" time + up to 10% of wait, to appear not too bot-y
                Fetcher.sites.select{|site| now - site.last_check > (site.wait*(1 + (rand() / 10))) }.each do |site|
                    count = 0
                    begin
                        site.get_yids().each { |yid|
                            @log.info "#{site} found #{yid}"
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
            Thread.current[:name]="Informer"
            @log.info "Informer thread starts"
            while true
                count = 0
                if $CONF["youtube_key"] and $CONF["youtube_key"].size > 5
                    DBUtils.get_all_yids_without_infos.each_slice(10).to_a.each do |yid_slice|
                        YoutubeUtils.get_batch_infos_with_key(yid_slice, $CONF["youtube_key"]).each do |infos|
                            yid = infos["yid"]
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
        io = IO.popen(command)
        DBUtils.set_downloaded(yid, msg=DBUtils::DLING)
        ytdl_msg = io.read.split("\n").join(" ")
        case ytdl_msg
        when /ERROR: (.+)$/
            error_message = $1
            case error_message
            when /^#{yid}: YouTube said: (.*)$/
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
                when /content too short/
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
            when /Signature extraction failed/
                ytdlfail(yid, error_message)
                return
            when /would lead to an infinite loop/
                DBUtils.set_downloaded(yid, DBUtils::RETRYDL)
            when /Connection reset by peer/
                DBUtils.set_downloaded(yid, DBUtils::RETRYDL)
            when /content too short/i
                DBUtils.set_downloaded(yid, DBUtils::RETRYDL)
            when /The uploader has not made this video available in your country/
                DBUtils.set_downloaded(yid, DBUtils::RETRYDL)
            when /This live stream recording is not available/
                ytdlfail(yid, error_message)
                return
            else
                DBUtils.set_downloaded(yid, "#{DBUtils::YTDLFAIL} #{error_message}")
                raise Exception.new("Problem with download of #{yid} : Unknown youtube-dl error '#{error_message}'")
            end
        when /^(WARNING: (.+)|)$/
            warn = $1
            if warn!=""
                @log.warn warn 
                if warn=~/unable to log in: bad username or password/
                    @log.warn "Use a webbrowser to connect to the YT Account, which was probabbly flagged as bot/spam"
                end
            end
            @log.success "Downloading finished, now post processing"
            output_files = Dir.glob("*#{yid}*",File::FNM_DOTMATCH)
            if output_files.size > 2
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
        else
            if ytdl_msg=~/no such option: (--.*)/
                @log.err "Your youtube-dl version probably doesn't support option #{$1}. Remove it from youtube_dl_extra_args in config.json or update your version"
                exit 1
            else
                raise Exception.new("Error with youtube_dl: '#{ytdl_msg}'")
            end
        end
        return nil
    end

    def start_downloader_threads()
        # TODO have more than 1 ?
        @downloader = Thread.new {
            while true
                yid = DBUtils.pop_yid_to_download(minimum_duration: $CONF["download"]["minimum_duration"], 
                                                  maximum_duration: $CONF["download"]["maximum_duration"])
                if yid
                    cur_dir=Dir.pwd()
                    do_download(yid)
                    Dir.chdir(cur_dir)
                else
#                    @log.info "nothing to download, sleeping"
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

        @threads << start_informer_threads()
        @threads << start_fetcher_threads()
        @threads << start_downloader_threads()
        @threads.each {|t| t.join()}
    end

end

def main(conf)
    m = Main.new(conf)
    m.go()
end

trap("INT"){
    # TODO
    # remove ytdl temps,
    exit
}

main(ARGV[0] || "config.json")
