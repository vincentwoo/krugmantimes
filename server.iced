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
  await retrieve_nytimes defer body

  res.charset = 'utf-8'
  res.setHeader 'Content-Type', 'text/html'
  res.setHeader 'Content-Length', body.length
  res.end body

retrieve_nytimes = (cb) ->
  console.log 'Requesting nytimes.com html'
  request 'http://www.nytimes.com', (error, response, body) ->
    return cb('', '', '') if error || response.statusCode != 200
    console.log "Loaded nytimes.com - #{Math.floor(body.length/1024)}kb"
    $ = cheerio.load body, lowerCaseTags: true

    $('title').text 'The Krugman Times'
    $('.byline').text 'By PAUL KRUGMAN'
    $('script, .adWrapper, .singleAd, .advertisement').remove()
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

    await
      $('#main .baseLayout .story').each () ->
        story = $(this)
        headlines = story.find('h2, h3, h5')
        summaries = story.find('.summary')
        text = "#{headlines.text().trim()} \n #{summaries.text().trim()}"
        return unless text.length > 50
        done = defer()
        extract_phrases text, (phrases) ->
          krugmanizms = _.sample KRUGMANIZMS, phrases.length
          phrases.forEach (phrase) ->
            return unless krugmanizm = krugmanizms.pop()
            regex = new RegExp "(\\W)#{phrase}(\\W)", 'g'
            headlines.toArray().concat(summaries.toArray()).forEach (elem) ->
              $(elem).text($(elem).text().replace regex, "$1#{krugmanizm}$2")
            headlines.each () ->
              $(this).text($(this).text().titlecase())
            summaries.each () ->
              $(this).text($(this).text().sentencecase()) 
          done()

    cb $.html()

extract_phrases = (text, cb) ->
  console.log "Requesting keyword extraction for: '#{text.substr 0, 40}...'"
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

      keywords = (keyword.text for keyword in keywords.keywords when keyword.text.length > 4)
      console.log "Found keywords: #{keywords.slice(0, 5).join(', ')}..."
      cb keywords

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
  console.log 'Initializing krugmantimes for production'
  redisURL = url.parse process.env.REDISCLOUD_URL
  #db = redis.createClient redisURL.port, redisURL.hostname, no_ready_check: true
  maxAge = 86400000
  ip = ':req[X-Forwarded-For]'
else
  console.log 'Initializing krugmantimes for development'
  #db = redis.createClient()
  maxAge = 0
  ip = ':remote-addr'

app.use express.static(__dirname + '/public', maxAge: maxAge)
app.use express.logger("#{ip} - :status(:method): :response-time ms - :url")
app.use express.compress()
console.log 'Express middleware installed'

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

String.prototype.titlecase = () ->
  this.split(' ').map (str) ->
    ret = str.trim().split('')
    return '' if ret.length == 0
    ret[0] = ret[0].toUpperCase();
    ret.join('')
  .join(' ')

String.prototype.sentencecase = () ->
  ret = this.trim()
  ret = ret.charAt(0).toUpperCase() + ret.slice(1)
  ret.replace /([.?!]\s+)(\w)/g, (match, pre, char) ->
    pre + char.toUpperCase();

_.sample = (obj, number) ->
  if number == undefined
    if obj.length > 0 then obj[_.random(obj.length - 1)] else null
  else 
    if number > 0 then _.shuffle(obj).slice(0, number) else []
