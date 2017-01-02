# Delicious Exporter

A scrapper for exporting your bookmarks from del.icio.us.

## Background

deli.icio.us is a bookmarking service that went through a series of increasingly less fortunate acquisitions. As of January 1st, 2017, the website is frequently down, yet doesn't allow users to export their bookmarks. It also no longer offers an API, and prohibits anyone from content scraping.

This is deeply unsettling, since many users have used del.icio.us to store thousands of bookmarks, capturing years of internet browsing history.

Delicious Exporter allows users to export their content to [HTML bookmarks](https://msdn.microsoft.com/en-us/library/aa753582.aspx) file, in a format accepted by major browsers. It will preserve tags and dates. Additional option enables validation and skipping of dead URLs.


## Requirements

* Ruby
* nokigiri (`gem install nokogiri`)
* curl

## Usage

### Basic usage:

`./export.rb -u USERNAME -o bookmarks.html`

`USERNAME` is delicious user name. `bookmarks.html` is the output file, where the bookmarks will be saved.

This will export all public links from selected del.icio.us account, including dead ones. This may take few minutes, depending on the number of bookmarks in your account.

### Export with links validation

`./export.rb -u USERNAME -o bookmarks.html --validate`

When you provide `--validate` option, the script will try to fix or skip dead links:
1. If the server doesn't respond within 5 seconds, the link will be skipped.
2. If the server sends a redirect header, the script will follow it and save the target URL.

This mode is much slower and can take about 2 minutes for every hundred of links.

## License

The script is available under provisions of [public domain license](https://creativecommons.org/publicdomain/zero/1.0/). You are free to copy and modify it without asking for author's permission. The author doesn't provide any warranty or support.

Please be aware that content scraping is currently not allowed by [del.icio.us' terms and conditions](https://del.icio.us/terms). The author doesn't take any responsibility for your usage of this script.
