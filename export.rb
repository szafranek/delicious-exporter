#!/usr/bin/env ruby

require 'rubygems'
require 'nokogiri'
require 'time'
require 'optparse'
require 'open-uri'
require 'tmpdir'
require 'json'

def parse_options
  options = {}

  opt_parser = OptionParser.new do |opts|
    opts.summary_width = 42

    opts.banner = "Usage: ruby #{File.basename(__FILE__)} -u DELICIOUS_USERNAME -o OUTPUT_FILE"

    opts.on("-u", "--username DELICIOUS_USERNAME", "Delicious username") do |u|
      options[:username] = u
    end
    
    opts.on("-p", "--password DELICIOUS_PASSWORD", "Delicious password. If you don't provide it, only public bookmarks will be exported.") do |p|
      options[:password] = p
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

def check_status(status, query)
  if !status.success?
    puts "Error executing query:\n#{query}"
    puts caller
    exit
  end
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
  tags = el.css(".tagName a").map{ |a| a.text }
  unless el.css("li.privateText").empty?
    tags << "___private"
  end
  tags_str = tags.join(",")
  %Q(<DT><A HREF="#{url}" ADD_DATE="#{add_date}" LAST_VISIT="#{add_date}" LAST_MODIFIED="#{add_date}" TAGS="#{tags_str}">#{title}</A>\n)
end

def login(tmpdir, username, password)
  cookie_file = "#{tmpdir}/cookie.txt"
  query = %Q{curl -s -c #{cookie_file} -d "username=#{username}" -d "password=#{password}" "https://del.icio.us/login"}
  response_str = `#{query}`
  check_status($?, query)
  response = JSON.parse(response_str)
  unless response["error_msgs"].empty?
    puts response["error_msgs"].join("\n")
    exit
  end
  cookie_name, cookie_value = response["session"].to_s.split("=", 2)
  cookie_time = (Time.now + (60*60*24*365)).to_i
  # Setting a cookie that del.icio.us sets via JavaScript
  File.open(cookie_file, "a") { |f|
    f << "del.icio.us	TRUE	/	FALSE	#{cookie_time}	#{cookie_name}	#{cookie_value}\n"
  }
  cookie_file
end

def cookify_query(query, cookie_file)
    query << (cookie_file ? " -b '#{cookie_file}'" : "")
    query
end

def page_count(tmpdir, cookie_file)
  username = $options[:username]
  page = "#{tmpdir}/home.html"
  query = cookify_query("curl -s 'https://del.icio.us/#{username}' -o '#{page}'", cookie_file)
  `#{query}`
  check_status($?, query)
  user_page = Nokogiri::HTML(File.read(page))
  link_count = user_page.css(".profileMidpanel h1 span:last-child").text.to_i
  pages = (link_count.to_f / 10).ceil.to_i
  puts "#{link_count} links, #{pages} pages to download"
  pages
end

def download_pages(dir, cookie_file, page_count)
  username = $options[:username]
  unless $options[:silent]
    puts "Downloading #{page_count} pages to a temporary directory..."
  end
  if page_count > 1
    pages = "[1-#{page_count}]"
    current_page = "#1"
  else
    pages = "1"
    current_page = "1"
  end
  query = cookify_query("curl -s 'https://del.icio.us/#{username}?&page=#{pages}' -o '#{dir}/page-#{current_page}.html'", cookie_file)
  `#{query}`
  check_status($?, query)
end

def print_status(status)
  print status, " | ", url, "\n"
end

def bookmarks_string
  items_string = ""
  tmpdir = Dir.mktmpdir
  cookie_file = $options[:password] ? login(tmpdir, $options[:username], $options[:password]) : nil
  page_count = page_count(tmpdir, cookie_file)
  download_pages(tmpdir, cookie_file, page_count)
  for n in 1..page_count
    page = Nokogiri::HTML(File.read("#{tmpdir}/page-#{n}.html"))
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
