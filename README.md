# iiif-dl

Command-line tile downloader/assembler for IIIF endpoints/manifests.

Download full-resolution image sequences from any IIIF server.

Currently not compatible with IIIF 3.0. See [this issue](https://github.com/ryanfb/iiif-dl/issues/12).

See also: [dzi-dl](https://github.com/ryanfb/dzi-dl/), [dezoomify](https://github.com/lovasoa/dezoomify), [dezoomify-rs](https://github.com/lovasoa/dezoomify-rs)

## Requirements

 * Ruby
 * [Bundler](http://bundler.io/)
 * [ImageMagick](http://www.imagemagick.org/)
 
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

## Docker Usage

There's also [an automated build for this repository on Docker Hub at `ryanfb/iiif-dl`](http://hub.docker.com/r/ryanfb/iiif-dl). It defines an `ENTRYPOINT` which will start `iiif-dl.rb` and pass any other arguments or environment variables to it, as well as defining a `/data` volume which you can map to your host to store manifests and images. For example, if you were in a directory with a IIIF manifest named `manifest.json`, you could download it with:

    docker run -t -v $(pwd):/data ryanfb/iiif-dl manifest.json
