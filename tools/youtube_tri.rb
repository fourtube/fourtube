#!/usr/bin/ruby

require "fileutils"
require "json"
require "optparse"
require "sequel"

require_relative "../lib/db.rb"

trap("SIGINT") { set_xterm_title("xterm") ; exit }

$config = nil
OptionParser.new do |parser|
  parser.on('-c', '--config CONFIG', 'Path to config.json') do |v|
    $config = v
  end
end.parse!

if not $config
  puts "Plz specify path to fourtube config.json file with -c"
  exit
end

$config = JSON.load(File.read($config))

$mplayer_path = "/usr/bin/mpv -vo=xv"
$videos_path = $config["download"]["destination_dir"]
$naze = File.join($video_path, "naze")
$bien = File.join($video_path, "YT_Greatest_Hits_#{Time.now.strftime('%Y')}")

db_path = $config["db"]["backend"]+"://"+$config["db"]["host"]+"/"+$config["db"]["table"]+"?user="+$config["db"]["user"]+"?password="+$config["db"]["pass"]
DB = Sequel.connect(db_path)

def set_xterm_title(msg)
    print "\033]0;#{msg}\007"
end

def keep_vid(yid,filename)
    puts "moving to #{$bien}"
    FileUtils.move(filename, $bien)
    DBUtils.set_bien(yid)
end

def del_vid(yid,filename)
    puts "moving to #{$naze}"
    FileUtils.move(filename, $naze)
    DBUtils.set_bien(yid, bien=false)
end

i = 0
while true
    l = DBUtils.get_videos_to_watch()
    s = l.count
    exit if s==0
    l.each do |row|
        yid = row[:yid]
        video_path = $videos_path+"/*#{yid}*"
        file = Dir.glob(video_path)[0]
        unless file
            puts "Can't find #{video_path}"
            next
        end
        i+=1
        puts "playing #{file} (video #{i}/#{s})"
        set_xterm_title(File.basename(file))
        IO.popen($mplayer_path+" -geometry 50%:50% \"#{file.gsub('$','\\$').gsub('`','\\`')}\"").read

        res=gets()
        if res.strip()=~/[a-z]{3}/
            keep_vid(yid,file)
        else
            del_vid(yid,file)
        end
    end
end
