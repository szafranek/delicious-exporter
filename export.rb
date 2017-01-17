#!/usr/bin/env ruby

require 'rubygems'
require 'nokogiri'
require 'time'
require 'optparse'
require 'open-uri'
require 'tmpdir'


def parse_options
  options = {}

  opt_parser = OptionParser.new do |opts|
    opts.summary_width = 42

    opts.banner = "Usage: ruby #{File.basename(__FILE__)} -u DELICIOUS_USERNAME -o OUTPUT_FILE"

    opts.on("-u", "--username DELICIOUS_USERNAME", "Delicious username") do |u|
      options[:username] = u
    end
  
    opts.on("-o", "--output-file OUTPUT_FILE", "Output file") do |o|
      options[:output_file] = o
    end

    opts.on("--validate", "Validate links. Resolve redirects, skip 404s and other server errors.") do |v|
      options[:validate] = v
    end

    opts.on("-s", "--silent", "Run silently") do |s|
      options[:silent] = s
    end

    opts.on_tail("-h", "--help", "Show this message") do
      puts opts
      puts "Example: ruby #{File.basename(__FILE__)} -u johndoe -o bookmarks.html"
      exit
    end
  end

  begin
    opt_parser.parse!
    mandatory = [:username, :output_file]
    missing = mandatory.select { |param| options[param].nil? }
    unless missing.empty?
      raise OptionParser::MissingArgument.new(missing.join(", "))
    end
  rescue OptionParser::InvalidOption, OptionParser::MissingArgument => e
    puts $!.to_s
    puts opt_parser
    exit
  end
  options
end

def http_status(url)
  `curl -Is --connect-timeout 5 '#{url}' | head -n 1`.chomp
end

def url(el)
  el.css(".articleInfoPan a")[0]["href"]
end

def effective_url(url)
  `curl -ILs -o /dev/null -w %{url_effective} '#{url}'`
end

def element_string(url, el)
  title = el.css("h3 a.title").text
  add_date = Time.strptime(el["date"], "%s").to_i
  tags = el.css(".tagName a").map{ |a| a.text }.join(",")
  %Q(<DT><A HREF="#{url}" ADD_DATE="#{add_date}" LAST_VISIT="#{add_date}" LAST_MODIFIED="#{add_date}" TAGS="#{tags}">#{title}</A>\n)
end

def page_count()
  username = $options[:username]
  user_page = Nokogiri::HTML(open("https://del.icio.us/#{username}"))
  link_count = user_page.css(".profileMidpanel h1 span:last-child").text.to_i
  (link_count / 10).ceil.to_i  
end

def download_pages(dir, page_count)
  username = $options[:username]
  unless $options[:silent]
    puts "Downloading #{page_count} pages to a temporary directory #{dir}"
  end
  if page_count > 1
    pages = "[1-#{page_count}]"
    current_page = "#1"
  else
    pages = "1"
    current_page = "1"
  end
  query = %Q{curl -s 'https://del.icio.us/#{username}?&page=#{pages}' -o "#{dir}/page-#{current_page}.html"}
  `#{query}`
end

def print_status(status)
  print status, " | ", url, "\n"
end

def bookmarks_string
  items_string = ""
  tmpdir = Dir.mktmpdir
  page_count = page_count()
  download_pages(tmpdir, page_count)
  for n in 1..page_count
  	page = Nokogiri::HTML(open("#{tmpdir}/page-#{n}.html"))
  	elements = page.css(".articleThumbBlockOuter")
  	for el in elements
  		url = url(el)
      if $options[:validate]
        status = http_status(url)
        if status.start_with?("HTTP/1.1 301", "HTTP/1.1 302", "HTTP/1.1 307")
          url = effective_url(url)
          status = http_status(url)
        end
        if status.empty?
          status = "Server not found"
          puts "\e[31m#{status}\e[0m | #{url}"
          next
        end
        unless $options[:silent]
          puts "#{status} | #{url}"
        end
      end
      items_string << element_string(url, el)
  	end
  end
  FileUtils.remove_entry(tmpdir)
  
  result = <<-EOT
  <!DOCTYPE NETSCAPE-Bookmark-file-1>
  <meta charset="UTF-8">
  <Title>Bookmarks</Title>
  <H1>Bookmarks</H1>
  <DL>
    <DT><H3 FOLDED ADD_DATE="#{Time.now.to_i}">Delicious</H3>
    <DL><p>
    #{items_string}
    </DL><p>
  </DL><p>
  EOT
end


def save(string)
  file = $options[:output_file]
  File.open(file, 'w') { |f| f.write(string) }
  unless $options[:silent]
    puts "#{file} saved"
  end
end


$options = parse_options()
save(bookmarks_string())
