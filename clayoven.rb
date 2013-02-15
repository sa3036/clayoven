require 'slim'
require 'yaml'
require_relative 'httpd'
require_relative 'claytext'

def when_introduced(filename)
  timestamp = `git log --reverse --pretty="%at" #{filename} 2>/dev/null | head -n 1`.strip
  if timestamp == ""
    Time.now
  else
    Time.at(timestamp.to_i)
  end
end

class ConfigData
  attr_accessor :rootpath, :rcpath, :ignorepath, :rc, :ignore

  def initialize
    @rootpath = ".clayoven"
    @rcpath = "#{rootpath}/rc"
    @ignorepath = "#{rootpath}/ignore"
    @ignore = ["\\.html$", "~$", "^.\#", "^\#.*\#$",
               "^\\.git$", "^\\.gitignore$", "^\\.htaccess$"]
    @rc = nil

    Dir.mkdir @rootpath if not Dir.exists? @rootpath
    if File.exists? @ignorepath
      @ignore = IO.read(@ignorepath).split("\n")
    else
      File.open(@ignorepath, "w") { |ignoreio|
        ignoreio.write @ignore.join("\n") }
      puts "[NOTE] #{@ignorepath} populated with sane defaults"
    end
  end
end

class Page
  attr_accessor :filename, :permalink, :timestamp, :title, :topic, :body,
  :paragraphs, :target, :indexfill, :topics

  def render(topics)
    @topics = topics
    @paragraphs = ClayText.process! @body
    Slim::Engine.set_default_options pretty: true, sort_attrs: false
    rendered = Slim::Template.new { IO.read("design/template.slim") }.render(self)
    File.open(@target, mode="w") { |targetio|
      nbytes = targetio.write(rendered)
      puts "[GEN] #{@target} (#{nbytes} bytes out)"
    }
  end
end

class IndexPage < Page
  def initialize(filename)
    @filename = filename
    if @filename == "index"
      @permalink = @filename
    else
      @permalink = filename.split(".index")[0]
    end
    @topic = @permalink
    @target = "#{@permalink}.html"
    @timestamp = when_introduced @filename
  end
end

class ContentPage < Page
  attr_accessor :pub_date

  def initialize(filename)
    @filename = filename
    @topic, @permalink = @filename.split(":", 2)
    @target = "#{@permalink}.html"
    @indexfill = nil
    @timestamp = when_introduced @filename
  end
end

def main
  if not File.exists? "index"
    puts "error: index file not found; aborting"
    exit 1
  end

  config = ConfigData.new
  all_files = (Dir.entries(".") -
               [".", "..", ".clayoven", "design"]).reject { |entry|
    config.ignore.any? { |pattern| %r{#{pattern}} =~ entry }
  }

  if not Dir.entries("design").include? "template.slim"
    puts "error: design/template.slim file not found; aborting"
    exit 1
  end

  index_files = ["index"] + all_files.select { |file| /\.index$/ =~ file }
  content_files = all_files - index_files
  topics = index_files.map { |file| file.split(".index")[0] }.uniq

  # Next, look for stray files
  (content_files.reject { |file| topics.include? (file.split(":", 2)[0]) })
    .each { |stray_entry|
    content_files = content_files - [stray_entry]
    puts "warning: #{stray_entry} is a stray file or directory; ignored"
  }

  index_pages = index_files.map { |filename| IndexPage.new(filename) }
  content_pages = content_files.map { |filename| ContentPage.new(filename) }

  # First, fill in all the page attributes
  (index_pages + content_pages).each { |page|
    page.title, page.body = (IO.read page.filename).split("\n\n", 2)
  }

  # Compute the indexfill for indexes
  topics.each { |topic|
    topic_index = index_pages.select { |page| page.topic == topic }[0]
    topic_index.indexfill = content_pages.select { |page|
      page.topic == topic }.sort { |a, b| b.timestamp <=> a.timestamp }
  }

  (index_pages + content_pages).each { |page| page.render topics }
end

case ARGV[0]
when "httpd"
  Httpd.start
else
  main
end
