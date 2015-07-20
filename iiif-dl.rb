#!/usr/bin/env ruby

require 'json'
require 'fileutils'
require 'tempfile'

MAX_TILE_WIDTH = 1000
MAX_TILE_HEIGHT = 1000
DEFAULT_SUFFIX = 'default.jpg'

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
      x_tiles = (width / MAX_TILE_WIDTH.to_f).ceil
      y_tiles = (height / MAX_TILE_HEIGHT.to_f).ceil
      $stderr.puts "#{x_tiles} x #{y_tiles} tiles"
      final_filename = "#{metadata_prefix} #{current_sequence} #{current_canvas} #{canvas['label']} #{current_image}.jpg".gsub(/[^-.a-zA-Z0-9_]/,'_')
      $stderr.puts "Downloading and assembling #{final_filename}"
      tile = 0
      tempfiles = []
      begin
        for y in 0..(y_tiles - 1)
          for x in 0..(x_tiles - 1)
            x_offset = MAX_TILE_WIDTH * x
            y_offset = MAX_TILE_HEIGHT * y
            x_width = (x_offset + MAX_TILE_WIDTH) > width ? width - x_offset : MAX_TILE_WIDTH
            y_width = (y_offset + MAX_TILE_HEIGHT) > height ? height - y_offset : MAX_TILE_HEIGHT
            tempfile = Tempfile.new(["#{metadata_prefix}_#{tile}_",'.jpg'])
            tempfile.close
            tempfiles << tempfile
            iiif_tile = "#{x_offset},#{y_offset},#{x_width},#{y_width}"
            url = "#{image['resource']['service']['@id']}/#{iiif_tile}/full/0/#{DEFAULT_SUFFIX}"
            $stderr.puts "Downloading tile #{iiif_tile}"
            `wget -q -O #{tempfile.path} #{url}`
            tile += 1
          end
        end
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
