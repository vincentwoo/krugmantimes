express = require 'express'
redis   = require 'redis'
url     = require 'url'
cheerio = require 'cheerio'
request = require 'request'
fs      = require 'fs'
gm      = require('gm').subClass imageMagick: true

KRUGMANZ_DIR = __dirname + '/public/images/krugmanz'
KRUGMANZ = []

for filename in fs.readdirSync(KRUGMANZ_DIR)
  await gm("#{KRUGMANZ_DIR}/#{filename}").size defer err, dimensions
  dimensions.ratio = dimensions.width / dimensions.height
  dimensions.path = "/images/krugmanz/#{filename}"
  KRUGMANZ.push dimensions

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

if process.env.NODE_ENV == 'production'
  redisURL = url.parse process.env.REDISCLOUD_URL
  #db = redis.createClient redisURL.port, redisURL.hostname, no_ready_check: true
  maxAge = 86400000
else
  #db = redis.createClient()
  maxAge = 0

app = express()
app.use express.logger()
app.use express.compress()
app.use express.static(__dirname + '/public', maxAge: maxAge)
app.listen process.env.PORT || 5000

app.get '/', (req, res) ->
  await retrieve_nytimes defer body, headlines, summaries
  await
    extract_phrases headlines, defer headline_phrases
    extract_phrases summaries, defer summary_phrases

  for phrase in headline_phrases.concat(summary_phrases)
    regex = new RegExp "(\\W)#{phrase}(\\W)", 'g'
    body = body.replace regex, '$1Paul Krugman$2'

  res.charset = 'utf-8'
  res.setHeader 'Content-Type', 'text/html'
  res.setHeader 'Content-Length', body.length
  res.end body

retrieve_nytimes = (cb) ->
  request 'http://www.nytimes.com', (error, response, body) ->
    return cb('', '', '') if error || response.statusCode != 200
    $ = cheerio.load body

    $('title').text 'The Krugman Times'
    $('.byline').text 'By PAUL KRUGMAN'
    $('script').remove()
    $('body').append TRACKING

    $('img').each (idx, element) ->
      element = $(element)

      if element.attr('id') == 'mastheadLogo'
        element.attr 'src', '/images/krugman_times_logo.png'
        element.parent().replaceWith(element) # replace noscript tag with image
        return

      width  = parseInt element.attr('width')
      height = parseInt element.attr('height')
      return if !width || !height || width < 40 || height < 40

      element.attr 'src', KRUGMANZ[idx % KRUGMANZ.length].path

    $('.headlinesOnly img').each (idx) ->
      $(this).attr 'src', KRUGMANZ[idx % KRUGMANZ.length].path

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
