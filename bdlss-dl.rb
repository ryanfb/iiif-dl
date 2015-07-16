#!/usr/bin/env ruby

require 'json'

MAX_TILE_WIDTH = 1000
MAX_TILE_HEIGHT = 1000

iiif_manifest = JSON.parse(ARGF.read)
iiif_manifest['sequences'].each do |sequence|
  $stderr.puts "Downloading #{sequence['canvases'].length} canvases"
  sequence['canvases'].each do |canvas|
    $stderr.puts canvas['label']
    canvas['images'].each do |image|
      $stderr.puts "#{image['resource']['width']} x #{image['resource']['height']}"
      width = image['resource']['width'].to_i
      height = image['resource']['height'].to_i
      x_tiles = (width / (MAX_TILE_WIDTH + 1).to_f).ceil
      y_tiles = (height / (MAX_TILE_HEIGHT + 1).to_f).ceil
      $stderr.puts "#{x_tiles} x #{y_tiles} tiles"
      $stderr.puts "#{iiif_manifest['label']} #{iiif_manifest['metadata'].select{|m| m['label'] == 'Id'}.first['value']} #{canvas['label']}".tr(' ','_')
      tile = 0
      filenames = []
      for y in 0..(y_tiles - 1)
        for x in 0..(x_tiles - 1)
          x_offset = (MAX_TILE_WIDTH + 1) * x
          y_offset = (MAX_TILE_HEIGHT + 1) * y
          x_width = (x_offset + MAX_TILE_WIDTH) > width ? width % MAX_TILE_WIDTH : MAX_TILE_WIDTH
          y_width = (y_offset + MAX_TILE_HEIGHT) > height ? height % MAX_TILE_HEIGHT : MAX_TILE_HEIGHT
          filename = "#{tile}.jpg"
          filenames << filename
          iiif_tile = "#{x_offset},#{y_offset},#{x_width},#{y_width}"
          url = "#{image['resource']['service']['@id']}/#{iiif_tile}/full/0/default.jpg"
          $stderr.puts "Downloading tile #{iiif_tile}"
          `wget -q -O #{filename} #{url}`
          tile += 1
        end
      end
      `montage -mode concatenate -tile #{x_tiles}x#{y_tiles} #{filenames.join(' ')} tiled.jpg`
      break
    end
    break
  end
end
