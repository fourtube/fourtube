Dir.glob(File.join(File.dirname(__FILE__),"*.rb")).each {|test| require_relative File.basename(test) }
