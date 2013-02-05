express = require 'express'
redis   = require 'redis'
url     = require 'url'
cheerio = require 'cheerio'
request = require 'request'
fs      = require 'fs'
gm      = require('gm').subClass imageMagick: true
_       = require 'underscore'

KRUGMANZ = [] # array of krugman images
KRUGMANIZMS = [] # array of krugman sayings
app = express() # main app object
app.listen process.env.PORT || 5000

app.get '/', (req, res) ->
  await retrieve_nytimes defer body, headlines, summaries
  await
    extract_phrases headlines, defer headline_phrases
    extract_phrases summaries, defer summary_phrases

  for phrase in headline_phrases.concat(summary_phrases)
    regex = new RegExp "(\\W)#{phrase}(\\W)", 'g'
    body = body.replace regex, "$1#{KRUGMANIZMS[_.random(KRUGMANIZMS.length - 1)]}$2"

  res.charset = 'utf-8'
  res.setHeader 'Content-Type', 'text/html'
  res.setHeader 'Content-Length', body.length
  res.end body

retrieve_nytimes = (cb) ->
  request 'http://www.nytimes.com', (error, response, body) ->
    return cb('', '', '') if error || response.statusCode != 200
    $ = cheerio.load body, lowerCaseTags: true

    $('title').text 'The Krugman Times'
    $('.byline').text 'By PAUL KRUGMAN'
    $('script').remove()
    $('.adWrapper').remove()
    $('body').append TRACKING

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

    $('.headlinesOnly .thumb img').each () ->
      $(this).replaceWith fit_krugman_photo(50, 50)

    headlines = ($('h2, h3, h5').map () -> $(this).text().replace(/\n/g, " ").trim()).join '\n'
    summaries = $('p.summary').text()
    cb $.html(), headlines, summaries

extract_phrases = (text, cb) ->
  request
    url: ' http://access.alchemyapi.com/calls/text/TextGetRankedKeywords'
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
      cb (keyword.text for keyword in keywords.keywords when keyword.text.length > 4)

fit_krugman_photo = (width, height) ->
  photo = KRUGMANZ[_.random(KRUGMANZ.length - 1)]
  """
    <span style="width: #{width}px; height: #{height}px;
      display: inline-block;
      background-image: url('#{photo.path}');
      background-size: cover;
      background-position: center center;
      ">
    </span>
  """

if process.env.NODE_ENV == 'production'
  redisURL = url.parse process.env.REDISCLOUD_URL
  #db = redis.createClient redisURL.port, redisURL.hostname, no_ready_check: true
  maxAge = 86400000
  ip = ':req[X-Forwarded-For]'
else
  #db = redis.createClient()
  maxAge = 0
  ip = ':remote-addr'

app.use express.static(__dirname + '/public', maxAge: maxAge)
app.use express.logger("#{ip} - :status(:method): :response-time ms - :url")
app.use express.compress()

KRUGMANZ_DIR = __dirname + '/public/images/krugmanz'
KRUGMANIZMS = [
  'New Keynesianism'
  'stimulus'
  'trillion dollar coin'
  "market efficiency"
  'deficit spending'
  'financial crisis'
  'government intervention'
  'shadow banking system'
  'debt ceiling'
  'liquidity trap'
  'zero lower bound'
]
await fs.readdir KRUGMANZ_DIR, defer err, filenames
await
  filenames.forEach (filename, idx) ->
    done = defer KRUGMANZ[idx]
    gm("#{KRUGMANZ_DIR}/#{filename}").size (err, dimensions) ->
      dimensions.ratio = dimensions.width / dimensions.height
      dimensions.path = "/images/krugmanz/#{filename}"
      done dimensions

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
