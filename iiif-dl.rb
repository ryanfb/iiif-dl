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
require 'ruby-progressbar'

DEFAULT_TILE_WIDTH = ENV['DEFAULT_TILE_WIDTH'].nil? ? 1024 : ENV['DEFAULT_TILE_WIDTH'].to_i
DEFAULT_TILE_HEIGHT = ENV['DEFAULT_TILE_HEIGHT'].nil? ? 1024 : ENV['DEFAULT_TILE_HEIGHT'].to_i
DEFAULT_EXTENSION = ENV['DEFAULT_EXTENSION'] || 'jpg'
USER_AGENT = ENV['USER_AGENT'] || 'iiif-dl'
DEFAULT_DELAY = ENV['DEFAULT_DELAY'].nil? ? 1 : ENV['DEFAULT_DELAY'].to_f
MAX_RETRIES = ENV['MAX_RETRIES'].nil? ? 3 : ENV['MAX_RETRIES'].to_i
VERIFY_SSL = (ENV['VERIFY_SSL'] == 'true') ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
ROBOTEX = Robotex.new(USER_AGENT)
OPEN_URI_OPTIONS = {"User-Agent" => USER_AGENT, :allow_redirections => :all, :ssl_verify_mode => VERIFY_SSL}

def escape_url(url)
  URI.encode(URI.escape(url),'[]')
end

def log_output(output_string, progress_bar = nil)
  if progress_bar.nil?
    $stderr.puts output_string
  else
    progress_bar.log output_string
  end
end

def download_identifier(identifier, force_tiling = false, final_filename = nil, width = nil, height = nil, progress_bar = nil)
  final_filename ||= identifier.split('/').last
  max_tile_width = DEFAULT_TILE_WIDTH
  max_tile_height = DEFAULT_TILE_HEIGHT
  v2 = nil
  
  begin
    info_json_url = escape_url("#{identifier}/info.json")
    log_output "Checking info.json URL: #{info_json_url}", progress_bar
    if ROBOTEX.allowed?(info_json_url)
      info_json = JSON.parse(open(info_json_url, OPEN_URI_OPTIONS).read)
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
      log_output "Forbidden from accessing URL: #{info_json_url}", progress_bar
      return
    end
  rescue StandardError => e
    log_output "Error parsing info.json (#{e.message}), using default tile size", progress_bar
  end

  quality = v2 ? 'default' : 'native'
  unless force_tiling
    [ escape_url("#{identifier}/0,0,#{width},#{height}/full/0/#{quality}.#{DEFAULT_EXTENSION}"),
      escape_url("#{identifier}/full/full/0/#{quality}.#{DEFAULT_EXTENSION}") ].each do |url|
      log_output "Attempting full-size download without stitching: #{url}", progress_bar
      if ROBOTEX.allowed?(url)
        begin
          IO.copy_stream(open(url, OPEN_URI_OPTIONS.merge({"Referer" => identifier})), "#{final_filename}.jpg")
          if File.exist?("#{final_filename}.jpg")
            log_output "Download succeeded, checking image dimensions...", progress_bar
            if (Dimensions.width("#{final_filename}.jpg") == width) && (Dimensions.height("#{final_filename}.jpg") == height)
              log_output "Full-size download successful: #{final_filename}.jpg", progress_bar
              return true
            else
              log_output "Image dimensions don't match: expected #{width}x#{height} but got #{Dimensions.dimensions("#{final_filename}.jpg").join('x')}", progress_bar
              FileUtils.rm("#{final_filename}.jpg")
            end
          end
        rescue StandardError => e
          log_output "Error downloading #{url}: #{e.inspect}", progress_bar
        end
      end
    end
  end

  x_tiles = (width / max_tile_width.to_f).ceil
  y_tiles = (height / max_tile_height.to_f).ceil
  log_output "#{x_tiles} x #{y_tiles} = #{x_tiles * y_tiles} tiles", progress_bar
  log_output "Downloading and assembling: #{final_filename}.jpg", progress_bar
  $stderr.puts
  tile_progress = ProgressBar.create(:title => "Downloading Tiles", :total => (x_tiles * y_tiles), :format => '%t (%c/%C): |%B| %p%% %E')
  tile = 0
  tempfiles = []
  begin
    for y in 0..(y_tiles - 1)
      for x in 0..(x_tiles - 1)
        retries = 0
        x_offset = max_tile_width * x
        y_offset = max_tile_height * y
        x_width = (x_offset + max_tile_width) > width ? width - x_offset : max_tile_width
        y_width = (y_offset + max_tile_height) > height ? height - y_offset : max_tile_height
        iiif_tile = "#{x_offset},#{y_offset},#{x_width},#{y_width}"
        url = escape_url("#{identifier}/#{iiif_tile}/full/0/#{quality}.#{DEFAULT_EXTENSION}")
        if ROBOTEX.allowed?(url)
          log_output "Downloading tile #{iiif_tile}", tile_progress
          delay = ROBOTEX.delay(url)
          tempfile = Tempfile.new(["#{final_filename}_#{tile}_",'.jpg'])
          tempfile.close
          tempfiles << tempfile
          begin
            IO.copy_stream(open(url, OPEN_URI_OPTIONS.merge({"Referer" => identifier})), tempfile.path)
            unless File.exist?(tempfile.path)
              raise("File not downloaded")
            end
          rescue StandardError => e
            log_output e.inspect, tile_progress
            log_output "Retrying download for: #{url}", tile_progress
            sleep (delay ? delay : DEFAULT_DELAY)
            if retries < MAX_RETRIES
              retries += 1
              retry
            else
              log_output "Maximum retries (#{MAX_RETRIES}) reached, skipping", tile_progress
              return false
            end
          end
          tile += 1
          sleep (delay ? delay : DEFAULT_DELAY)
        else
          log_output "User agent \"#{USER_AGENT}\" not allowed by `robots.txt` for #{url}, aborting", tile_progress
          exit 1
        end # ROBOTEX.allowed?
        tile_progress.increment
      end # x
    end # y
    # assemble the tiles
    `montage -mode concatenate -tile #{x_tiles}x#{y_tiles} #{tempfiles.map{|t| t.path}.join(' ')} #{final_filename}.jpg`
    if File.exist?("#{final_filename}.jpg")
      log_output "Assembled image from tiles: #{final_filename}.jpg"
      if !((Dimensions.width("#{final_filename}.jpg") == width) && (Dimensions.height("#{final_filename}.jpg") == height))
        log_output "WARNING: Final image dimensions don't match, expected #{width}x#{height} but got #{Dimensions.dimensions("#{final_filename}.jpg").join('x')}", tile_progress
      end
    else
      log_output "ERROR: Expected #{final_filename}.jpg to be assembled from tiles, but file does not exist.", tile_progress
      return false
    end
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
      canvas_progress = ProgressBar.create(:title => "Downloading Canvases", :total => sequence['canvases'].length, :format => '%t (%c/%C): |%B| %p%% %E')
      current_canvas = 0
      sequence['canvases'].each do |canvas|
        log_output "Canvas Label: #{canvas['label']}", canvas_progress
        current_image = 0
        canvas['images'].each do |image|
          log_output "Image Dimensions: #{image['resource']['width']} x #{image['resource']['height']}", canvas_progress
          width = image['resource']['width'].to_i
          height = image['resource']['height'].to_i
          identifier = URI.unescape(image['resource']['service']['@id'].chomp('/'))
          log_output "Got identifier: #{identifier}", canvas_progress
          log_output "From: #{image['resource']['service']['@id']}", canvas_progress
          final_filename = "#{metadata_prefix} #{current_sequence} #{current_canvas} #{canvas['label']} #{current_image}".gsub(/[^-.a-zA-Z0-9_]/,'_')
          v2 = image['resource']['service']['@context'] =~ /iiif.io\/api\/image\/2/
          download_identifier(identifier, options[:force_tiling], final_filename, width, height, canvas_progress)
          current_image += 1
        end # image loop
        current_canvas += 1
        canvas_progress.increment
      end # canvas loop
      current_sequence += 1
    end # sequence loop
  end
end
