require 'newrelic' if process.env.NODE_ENV == 'production'

express = require 'express'
redis   = require 'redis'
crypto  = require 'crypto'
url     = require 'url'
cheerio = require 'cheerio'
request = require 'request'
fs      = require 'fs'
_       = require 'underscore'
require './extensions'

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

    $('title').text 'The Krugman Times'
    $('.adWrapper, .singleAd, .advertisement, meta, .ad').remove()
    $('script').each (idx, element) ->
      element = $(element)
      unless element.attr('src')?.indexOf('typeface.nytimes') > 0 ||
              element.text().indexOf('Typekit') > 0
        element.remove()

    $('#shell').html """
      <div id="flip-wrap">#{$('#shell').html()}</div>
      #{MODAL_INJECT}
    """
    $('.byline').each ->
     $(this).html """
        By
        <span class="krugman-highlight">
          <span class="new">PAUL KRUGMAN</span>
          <span class="old">#{$(this).text().substr(3)}</span>
        </span>
      """
    $('.masthead-menu').replaceWith """
      <div class="krugman-explanation">
        The New York Times By Its Only Columnist <br>
        Press the <span>?</span> key to reveal a surprise, or
        <a id="krugman-faq" href="#">read about what this is</a> <br>
        <small>The New York Times trademarks and copyright-protected material used with permission of The New York Times Company © 2013</small>
      </div>
    """

    $('.nyt-logo').replaceWith('<img src="/images/krugman_times_logo.png" />')

    $('img').each (idx, element) ->
      element = $(element)

      src = element.attr('src') || element.attr('SRC')
      if src && src.indexOf('/adx/') != -1
        return element.remove() # kill some ad images

      width  = +element.attr 'width'
      height = +element.attr 'height'
      return unless width > 40 && height > 40

      fit_krugman_photo($, element, width, height)

    $('.headlinesOnly .thumb img').each ->
      fit_krugman_photo($, $(this), 50, 50)

    imageRegions = [
      '#photoSpotRegion .columnGroup.first .image'
      '.extendedVideoPocketPlayerContainer'
      '#timescastVideoPlayerContainer'
      '#photospotVideoPlayerContainer'
      '.ledePhoto'
      '.media.photo'
    ]
    $(imageRegions.join(', ')).each ->
      fit_krugman_photo($, $(this))

    await
      $('.story, #photoSpotRegion .columnGroup, .headlinesOnly').each ->
        story = $(this)
        headlines = if story.hasClass('headlinesOnly')
          story.find('li>a:not(.thumb), h6>a')
        else
          story.find('h2>a, h3>a, h5>a')
        summaries = story.find('.summary')
        text = "#{headlines.text().trim()} \n #{summaries.text().trim()}"
        return unless text.length > 50
        done = defer()
        extract_keywords text, (keywords) ->
          headlines.each -> perform_substitutions $(this), keywords, true
          summaries.each -> perform_substitutions $(this), keywords, false
          done()

    html = $.html()
    html = html.replace /<\/head>/, HEAD_INJECT + '</head>'
    html = html.replace /<\/body>/, BODY_INJECT + '</body>'

    db.set '/', html
    db.expire '/', expiry
    cb html

perform_substitutions = (elem, keywords, titlecase) ->
  text = elem.html()
  return if text.indexOf('krugman-highlight') != -1 # we've been here before

  for keyword in keywords
    regex = new RegExp keyword.phrase, 'gm'
    text = text.replace regex, (matched, offset, str) ->
      if titlecase
        replace = keyword.replacement.titlecase()
      else
        prior = str.substr 0, offset
        replace = if prior.match /([.!?]|^)\s*$/
          keyword.replacement.capitalize()
        else
          keyword.replacement
      '<span class="krugman-highlight">' +
        "<span class=\"old\">#{matched}</span>" +
        "<span class=\"new\">#{replace}</span>" +
      '</span>'

  elem.html text

extract_keywords = (text, cb) ->
  hash = crypto.createHash('md5').update(text).digest('hex');
  await db.get "text:#{hash}", defer err, reply
  if reply
    return cb JSON.parse(reply)

  console.log "Requesting keyword extraction for text with fingerprint #{hash}"
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

      krugmanizms = KRUGMANIZMS.sample keywords.length
      keywords = keywords.map((keyword) ->
        phrase: keyword
        replacement: krugmanizms.pop()
      ).filter (keyword) -> keyword.replacement

      db.set "text:#{hash}", JSON.stringify(keywords)
      cb keywords

current_krugmanz = []
fit_krugman_photo = ($, element, width, height) ->
  current_krugmanz = _.shuffle(KRUGMANZ) if current_krugmanz.length == 0
  photo = current_krugmanz.pop()
  contents = if width && height
    """
      <div class="krugman-photo new"
        style="width: #{width}px; height: #{height}px;
        background-image: url('#{photo}');">
      </div>
    """
  else
    """
      <div class="krugman-container new">
          <div class="krugman-dummy"></div>
          <div class="krugman-element"
            style="background-image: url('#{photo}');">
          </div>
      </div>
    """
  contents = """
    <div class="krugman-highlight block">
      #{contents}
      <div class="old">
        #{$.html(element)}
      </div>
    </div>
  """
  element.replaceWith contents

if process.env.NODE_ENV == 'production'
  console.log 'Initializing krugmantimes for production'
  redisURL = url.parse process.env.REDISCLOUD_URL
  db = redis.createClient redisURL.port, redisURL.hostname, no_ready_check: true
  db.auth redisURL.auth.split(':')[1]
  maxAge = 604800000
  expiry = 60
  ip = ':req[X-Forwarded-For]'
else
  console.log 'Initializing krugmantimes for development'
  db = redis.createClient()
  maxAge = 0
  expiry = 0
  ip = ':remote-addr'

db.on 'error', (err) -> console.log('REDIS ERR: ' + err);

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

KRUGMANIZMS = [
  'New Keynesianism'
  'stimulus package'
  'market efficiency'
  'deficit spending'
  'financial crisis'
  'shadow banking system'
  'liquidity trap'
  'Paul Krugman'
  'economies of scale'
  'utility function'
  'multiple equilibria'
  'quantitative easing'
  'market correction'
  'monetary policy'
]

KRUGMANZ = fs.readdirSync(__dirname + '/public/images/krugmanz')
  .map (filename) -> "/images/krugmanz/#{filename}"
HEAD_INJECT = fs.readFileSync './inject/head.html', 'utf8'
BODY_INJECT = fs.readFileSync './inject/body.html', 'utf8'
MODAL_INJECT = fs.readFileSync './inject/modal.html', 'utf8'
