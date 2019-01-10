#!/usr/bin/env ruby

require 'json'
require 'fileutils'
require 'tempfile'
require 'robotex'
require 'uri'
require 'open-uri'
require 'open_uri_redirections'
require 'dimensions'
require 'optparse'
require 'net/https'

DEFAULT_TILE_WIDTH = 1024
DEFAULT_TILE_HEIGHT = 1024
DEFAULT_EXTENSION = 'jpg'
USER_AGENT = 'iiif-dl'
DEFAULT_DELAY = 1
ROBOTEX = Robotex.new(USER_AGENT)

def download_identifier(identifier, force_tiling = false, final_filename = nil, width = nil, height = nil)
  final_filename ||= identifier.split('/').last
  max_tile_width = DEFAULT_TILE_WIDTH
  max_tile_height = DEFAULT_TILE_HEIGHT
  v2 = nil
  
  begin
    info_json_url = URI.encode(URI.escape("#{identifier}/info.json"),'[]')
    $stderr.puts "Checking info.json URL: #{info_json_url}"
    if ROBOTEX.allowed?(info_json_url)
      info_json = JSON.parse(open(info_json_url, "User-Agent" => USER_AGENT, :allow_redirections => :all, :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE).read)
      if info_json['tiles'] # IIIF 2.0
        v2 = true
        max_tile_width = info_json['tiles'][0]['width']
        if info_json['tiles'][0]['height']
          max_tile_height = info_json['tiles'][0]['height']
        else
          max_tile_height = max_tile_width
        end
      else # IIIF 1.1
        v2 = false
        if info_json['tile_width']
          max_tile_width = info_json['tile_width']
        end
        if info_json['tile_height']
          max_tile_height = info_json['tile_height']
        end
      end
      if info_json['width']
        width = info_json['width']
      end
      if info_json['height']
        height = info_json['height']
      end
    else
      $stderr.puts "Forbidden from accessing URL: #{info_json_url}"
      return
    end
  rescue Exception => e
    $stderr.puts "Error parsing info.json (#{e.message}), using default tile size"
  end

  quality = v2 ? 'default' : 'native'
  unless force_tiling
    [ URI.escape("#{identifier}/0,0,#{width},#{height}/full/0/#{quality}.#{DEFAULT_EXTENSION}"),
      URI.escape("#{identifier}/full/full/0/#{quality}.#{DEFAULT_EXTENSION}") ].each do |url|
      $stderr.puts "Attempting full-size download without stitching: #{url}"
      if ROBOTEX.allowed?(url)
        if system("wget --header='Referer: #{identifier}' -U \"#{USER_AGENT}\" -q -O #{final_filename}.jpg #{url}")
          $stderr.puts "Download succeeded, checking image dimensions..."
          if (Dimensions.width("#{final_filename}.jpg") == width) && (Dimensions.height("#{final_filename}.jpg") == height)
            $stderr.puts "Full-size download successful: #{final_filename}.jpg"
            return
          else
            $stderr.puts "Image dimensions don't match: expected #{width}x#{height} but got #{Dimensions.dimensions("#{final_filename}.jpg").join('x')}"
            FileUtils.rm("#{final_filename}.jpg")
          end
        end
      end
    end
  end

  x_tiles = (width / max_tile_width.to_f).ceil
  y_tiles = (height / max_tile_height.to_f).ceil
  $stderr.puts "#{x_tiles} x #{y_tiles} = #{x_tiles * y_tiles} tiles"
  $stderr.puts "Downloading and assembling: #{final_filename}.jpg"
  tile = 0
  tempfiles = []
  begin
    for y in 0..(y_tiles - 1)
      for x in 0..(x_tiles - 1)
        x_offset = max_tile_width * x
        y_offset = max_tile_height * y
        x_width = (x_offset + max_tile_width) > width ? width - x_offset : max_tile_width
        y_width = (y_offset + max_tile_height) > height ? height - y_offset : max_tile_height
        iiif_tile = "#{x_offset},#{y_offset},#{x_width},#{y_width}"
        url = URI.escape("#{identifier}/#{iiif_tile}/full/0/#{quality}.#{DEFAULT_EXTENSION}")
        if ROBOTEX.allowed?(url)
          $stderr.puts "Downloading tile #{iiif_tile}"
          delay = ROBOTEX.delay(url)
          tempfile = Tempfile.new(["#{final_filename}_#{tile}_",'.jpg'])
          tempfile.close
          tempfiles << tempfile
          while !system("wget --header='Referer: #{identifier}' -U \"#{USER_AGENT}\" -q -O #{tempfile.path} #{url}") do
            $stderr.puts "Retrying download for: #{url}"
            sleep (delay ? delay : DEFAULT_DELAY)
          end
          tile += 1
          sleep (delay ? delay : DEFAULT_DELAY)
        else
          $stderr.puts "User agent \"#{USER_AGENT}\" not allowed by `robots.txt` for #{url}, aborting"
          exit 1
        end # allowed?
      end # x
    end # y
    # assemble the tiles
    `montage -mode concatenate -tile #{x_tiles}x#{y_tiles} #{tempfiles.map{|t| t.path}.join(' ')} #{final_filename}.jpg`
  ensure
    tempfiles.each{|t| t.unlink}
  end
end

if File.basename(__FILE__) == File.basename($PROGRAM_NAME)
  options = {}
  optparse = OptionParser.new do |opts|
    opts.banner = "Usage: iiif-dl.rb [options] [iiif-manifest.json]"
    options[:force_tiling] = false
    opts.on('-f','--force-tiling',"Don't attempt full-size downloads without tiling") do
      options[:force_tiling] = true
    end
    options[:identifier_download] = nil
    opts.on('-i','--identifier IDENTIFIER',"Download single IIIF identifier IDENTIFIER instead of image sequence from manifest JSON") do |identifier|
      options[:identifier_download] = identifier
    end
    opts.on('-h','--help','Display this screen') do
      puts opts
      exit
    end
  end
  optparse.parse!

  if options[:identifier_download]
    download_identifier(options[:identifier_download], options[:force_tiling])
  else
    $stderr.puts "Parsing manifest JSON..."
    iiif_manifest = JSON.parse(ARGF.read)

    manifest_id = ''
    begin
     manifest_id = " #{iiif_manifest['metadata'].select{|m| m['label'] == 'Id'}.first['value']}"
    rescue
    end

    metadata_prefix = "#{iiif_manifest['label']}#{manifest_id}".gsub(/[^-.a-zA-Z0-9_]/,'_')
    current_sequence = 0
    iiif_manifest['sequences'].each do |sequence|
      $stderr.puts "Downloading #{sequence['canvases'].length} canvases"
      current_canvas = 0
      sequence['canvases'].each do |canvas|
        $stderr.puts canvas['label']
        current_image = 0
        canvas['images'].each do |image|
          $stderr.puts "#{image['resource']['width']} x #{image['resource']['height']}"
          width = image['resource']['width'].to_i
          height = image['resource']['height'].to_i
          identifier = URI.unescape(image['resource']['service']['@id'].chomp('/'))
          $stderr.puts "Got identifier: #{identifier}"
          $stderr.puts "From: #{image['resource']['service']['@id']}"
          final_filename = "#{metadata_prefix} #{current_sequence} #{current_canvas} #{canvas['label']} #{current_image}".gsub(/[^-.a-zA-Z0-9_]/,'_')
          v2 = image['resource']['service']['@context'] =~ /iiif.io\/api\/image\/2/
          download_identifier(identifier, options[:force_tiling], final_filename, width, height)
          current_image += 1
        end # image loop
        current_canvas += 1
      end # canvas loop
      current_sequence += 1
    end # sequence loop
  end
end
