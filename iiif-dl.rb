#!/usr/bin/env ruby

require 'json'
require 'fileutils'
require 'tempfile'
require 'robotex'
require 'uri'
require 'open-uri'
require 'open_uri_redirections'

DEFAULT_TILE_WIDTH = 1000
DEFAULT_TILE_HEIGHT = 1000
DEFAULT_EXTENSION = 'jpg'
USER_AGENT = 'iiif-dl'
DEFAULT_DELAY = 1

robotex = Robotex.new(USER_AGENT)
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
      identifier = image['resource']['service']['@id'].chomp('/')
      max_tile_width = DEFAULT_TILE_WIDTH
      max_tile_height = DEFAULT_TILE_HEIGHT
      
      begin
        info_json_url = URI.escape("#{identifier}/info.json")
        if robotex.allowed?(info_json_url)
          info_json = JSON.parse(open(info_json_url, "User-Agent" => USER_AGENT, :allow_redirections => :all).read)
          if info_json['tiles'] # IIIF 2.0
            max_tile_width = info_json['tiles'][0]['width']
            if info_json['tiles'][0]['height']
              max_tile_height = info_json['tiles'][0]['height']
            else
              max_tile_height = max_tile_width
            end
          else # IIIF 1.1
            if info_json['tile_width']
              max_tile_width = info_json['tile_width']
            end
            if info_json['tile_height']
              max_tile_height = info_json['tile_height']
            end
          end
        end
      rescue Exception => e
        $stderr.puts "Error parsing info.json (#{e.message}), using default tile size"
      end

      x_tiles = (width / max_tile_width.to_f).ceil
      y_tiles = (height / max_tile_height.to_f).ceil
      $stderr.puts "#{x_tiles} x #{y_tiles} tiles"
      final_filename = "#{metadata_prefix} #{current_sequence} #{current_canvas} #{canvas['label']} #{current_image}.jpg".gsub(/[^-.a-zA-Z0-9_]/,'_')
      $stderr.puts "Downloading and assembling #{final_filename}"
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
            quality = image['resource']['service']['@context'] =~ /iiif.io\/api\/image\/2/ ? 'default' : 'native'
            url = URI.escape("#{identifier}/#{iiif_tile}/full/0/#{quality}.#{DEFAULT_EXTENSION}")
            if robotex.allowed?(url)
              $stderr.puts "Downloading tile #{iiif_tile}"
              delay = robotex.delay(url)
              tempfile = Tempfile.new(["#{metadata_prefix}_#{tile}_",'.jpg'])
              tempfile.close
              tempfiles << tempfile
              while !system("wget -U \"#{USER_AGENT}\" -q -O #{tempfile.path} #{url}") do
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
        `montage -mode concatenate -tile #{x_tiles}x#{y_tiles} #{tempfiles.map{|t| t.path}.join(' ')} #{final_filename}`
      ensure
        tempfiles.each{|t| t.unlink}
      end
      current_image += 1
    end # image loop
    current_canvas += 1
  end # canvas loop
  current_sequence += 1
end # sequence loop
