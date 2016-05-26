# iiif-dl

Command-line tile downloader/assembler for IIIF endpoints/manifests.

Download full-resolution image sequences from any IIIF server.

See also: [dzi-dl](https://github.com/ryanfb/dzi-dl/)

## Requirements

 * `wget`
 * [ImageMagick](http://www.imagemagick.org/)
 * Ruby
 * [Bundler](http://bundler.io/)
 
## Usage

    bundle install
    bundle exec ./iiif-dl.rb iiif-manifest.json

You can download an IIIF manifest from e.g. the [Digital Bodleian](http://digital.bodleian.ox.ac.uk/):

![Digital Bodleian IIIF manifest download](http://i.imgur.com/WQLemyw.png)
