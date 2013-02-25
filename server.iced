require 'newrelic' if process.env.NODE_ENV == 'production'

express = require 'express'
redis   = require 'redis'
crypto  = require 'crypto'
url     = require 'url'
cheerio = require 'cheerio'
request = require 'request'
fs      = require 'fs'
gm      = require('gm').subClass imageMagick: true
_       = require 'underscore'

KRUGMANZ = [] # array of krugman images
KRUGMANIZMS = [] # array of krugman sayings
app = express() # main app object

retrieve_nytimes = (cb) ->
  await db.get "/", defer err, reply
  return cb('') if err
  if reply
    console.log 'Cache hit for homepage'
    return cb(reply)
  console.log 'Requesting nytimes.com html'
  request 'http://www.nytimes.com', (error, response, body) ->
    return cb('', '', '') if error || response.statusCode != 200
    console.log "Loaded nytimes.com - #{Math.floor(body.length/1024)}kb"
    $ = cheerio.load body, lowerCaseTags: true

    $('body').append TRACKING
    $('head').append CSS

    $('title').text 'The Krugman Times'
    $('.byline').text 'By PAUL KRUGMAN'
    $('script, .adWrapper, .singleAd, .advertisement').remove()

    $('img').each (idx, element) ->
      element = $(element)

      if element.attr('id') == 'mastheadLogo'
        element.attr 'src', '/images/krugman_times_logo.png'
        return element.parent().replaceWith(element) # replace noscript tag with image

      if (element.attr('src') || element.attr('SRC')).indexOf('/adx/') != -1
        return element.remove() # kill some ad images

      width  = +element.attr 'width'
      height = +element.attr 'height'
      return unless width > 40 && height > 40

      element.replaceWith fit_krugman_photo(width, height)

    $('.headlinesOnly .thumb img').each ->
      $(this).replaceWith fit_krugman_photo(50, 50)

    $('#photoSpotRegion .columnGroup.first').html fit_krugman_photo()

    await
      $('#main .baseLayout .story, #photoSpotRegion .columnGroup').each ->
        story = $(this)
        headlines = story.find('h2, h3, h5')
        summaries = story.find('.summary')
        text = "#{headlines.text().trim()} \n #{summaries.text().trim()}"
        return unless text.length > 50
        done = defer()
        extract_keywords text, (keywords) ->
          keywords.forEach (keyword) ->
            regex = new RegExp "(\\W)#{keyword.phrase}(\\W)", 'g'
            headlines.toArray().concat(summaries.toArray()).forEach (elem) ->
              $(elem).text($(elem).text().replace regex, "$1#{keyword.replacement}$2")
            headlines.each ->
              $(this).text($(this).text().titlecase())
            summaries.each ->
              $(this).text($(this).text().sentencecase())
          done()

    html = $.html()
    db.set '/', html
    db.expire '/', expiry
    cb html

extract_keywords = (text, cb) ->
  hash = crypto.createHash('md5').update(text).digest('hex');
  console.log "Requesting keyword extraction for text with fingerprint #{hash}"
  await db.get "text:#{hash}", defer err, reply
  if reply
    console.log "Cache hit for text with fingerprint #{hash}"
    return cb JSON.parse(reply)

  request
    url: 'http://access.alchemyapi.com/calls/text/TextGetRankedKeywords'
    method: 'post'
    qs:
      apikey: process.env.ALCHEMY_API_KEY
      outputMode: 'json'
    form:
      text: text,
    (error, response, keywords) ->
      return cb([]) if error || response.statusCode != 200
      keywords = JSON.parse keywords
      return cb([]) unless keywords.status == 'OK'

      keywords = (keyword.text for keyword in keywords.keywords when keyword.text.length > 4)
      console.log "Found keywords: #{keywords.slice(0, 5).join(', ')}..."

      krugmanizms = KRUGMANIZMS.sample keywords.length
      keywords = keywords.map((keyword) ->
        phrase: keyword
        replacement: krugmanizms.pop()
      ).filter (keyword) -> keyword.replacement

      db.set "text:#{hash}", JSON.stringify(keywords)
      cb keywords

fit_krugman_photo = (width, height) ->
  photo = KRUGMANZ[_.random(KRUGMANZ.length - 1)]
  if width && height
    """
      <div class="krugman-photo"
        style="width: #{width}px; height: #{height}px;
        background-image: url('#{photo.path}');">
      </div>
    """
  else
    """
      <div class="krugman-container">
          <div class="krugman-dummy"></div>
          <div class="krugman-element"
            style="background-image: url('#{photo.path}');">
          </div>
      </div>
    """

if process.env.NODE_ENV == 'production'
  console.log 'Initializing krugmantimes for production'
  redisURL = url.parse process.env.REDISCLOUD_URL
  db = redis.createClient redisURL.port, redisURL.hostname, no_ready_check: true
  db.auth redisURL.auth.split(':')[1]
  maxAge = 86400000
  expiry = 60
  ip = ':req[X-Forwarded-For]'
else
  console.log 'Initializing krugmantimes for development'
  db = redis.createClient()
  maxAge = 0
  expiry = 0
  ip = ':remote-addr'

app.use express.static(__dirname + '/public', maxAge: maxAge)
app.use express.logger("#{ip} - :status(:method): :response-time ms - :url")
app.use express.compress()
app.get '/', (req, res) ->
  await retrieve_nytimes defer body

  res.charset = 'utf-8'
  res.setHeader 'Content-Type', 'text/html'
  res.setHeader 'Content-Length', body.length
  res.end body
app.listen process.env.PORT || 5000
console.log 'Express middleware installed'

KRUGMANZ_DIR = __dirname + '/public/images/krugmanz'
KRUGMANIZMS = [
  'New Keynesianism'
  'stimulus'
  'market efficiency'
  'deficit spending'
  'financial crisis'
  'shadow banking system'
  'debt ceiling'
  'liquidity trap'
  'Paul Krugman'
]
console.log 'Reading directory of krugman images'
await fs.readdir KRUGMANZ_DIR, defer err, filenames
console.log 'Images found, getting their dimensions'
filenames.forEach (filename, idx) ->
  await gm("#{KRUGMANZ_DIR}/#{filename}").size defer err, dimensions
  console.log "Krugman #{idx} loaded, #{dimensions.width}px x #{dimensions.height}px"
  dimensions.ratio = dimensions.width / dimensions.height
  dimensions.path = "/images/krugmanz/#{filename}"
  KRUGMANZ[idx] = dimensions

TRACKING = """
  <script type="text/javascript">
    var _gaq = _gaq || [];
    _gaq.push(['_setAccount', 'UA-38200823-1']);
    _gaq.push(['_setDomainName', 'krugmantimes.com']);
    _gaq.push(['_trackPageview']);
    (function() {
      var ga = document.createElement('script'); ga.type = 'text/javascript'; ga.async = true;
      ga.src = ('https:' == document.location.protocol ? 'https://ssl' : 'http://www') + '.google-analytics.com/ga.js';
      var s = document.getElementsByTagName('script')[0]; s.parentNode.insertBefore(ga, s);
    })();
  </script>
  """
CSS = """
  <style>
    .krugman-container {
        display: inline-block;
        position: relative;
        width: 100%;
    }
    .krugman-dummy {
        padding-top: 75%; /* 4:3 aspect ratio */
    }
    .krugman-element {
        position: absolute;
        top: 0;
        bottom: 0;
        left: 0;
        right: 0;
        background-size: cover;
        background-position: center center;
    }
    .krugman-photo {
      display: inline-block;
      background-size: cover;
      background-position: center center;
    }
  </style>
  """

String.prototype.titlecase = ->
  this.split(' ').map (str) ->
    ret = str.trim().split('')
    return '' if ret.length == 0
    ret[0] = ret[0].toUpperCase();
    ret.join('')
  .join(' ')

String.prototype.sentencecase = ->
  ret = this.trim()
  ret = ret.charAt(0).toUpperCase() + ret.slice(1)
  ret.replace /([.?!]\s+)(\w)/g, (match, pre, char) ->
    pre + char.toUpperCase();

Array.prototype.sample = (number) ->
  if number == undefined
    if this.length > 0 then this[_.random(obj.length - 1)] else null
  else
    if number > 0 then _.shuffle(this).slice(0, number) else []
