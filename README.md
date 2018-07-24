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
    bundle exec ./iiif-dl.rb --help
    
    Usage: iiif-dl.rb [options] [iiif-manifest.json]
        -f, --force-tiling               Don't attempt full-size downloads without tiling
        -i, --identifier IDENTIFIER      Download single IIIF identifier IDENTIFIER instead of image sequence from manifest JSON
        -h, --help                       Display this screen
    
    bundle exec ./iiif-dl.rb iiif-manifest.json
    bundle exec ./iiif-dl.rb -i http://example.com/iiif/IIIF_SHELFMARK_0001

You can download an IIIF manifest from e.g. the [Digital Bodleian](http://digital.bodleian.ox.ac.uk/):

![Digital Bodleian IIIF manifest download](http://i.imgur.com/WQLemyw.png)

Alternately, if you have [PhantomJS](http://phantomjs.org/) installed, you can use `jsonreqs.js` to list all URLs ending in `.json` requested by a given webpage URL:

    phantomjs jsonreqs.js 'http://example.com/viewer.asp?manuscript=shelfmark'

In single-identifier mode, you pass the URL of an IIIF identifier, i.e. what `/info.json` would be appended to in order to make [an Image Information Request](https://iiif.io/api/image/2.1/#image-information-request).
