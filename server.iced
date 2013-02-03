express = require('express')
redis   = require('redis')
url     = require('url')
cheerio = require('cheerio')
request = require('request')

KRUGMANZ = [
  'http://media.salon.com/2010/04/pistols_at_dawn_paul_krugman_vs_andrew_sorkin.jpg'
  'http://www.wired.com/images_blogs/underwire/2012/05/Krugman-6601.jpg'
  'http://www.skepticmoney.com/wp-content/uploads/2012/08/Paul-Krugman.jpg'
  'http://www.princeton.edu/~paw/web_exclusives/more/more_pics/more6_krugman.jpg'
]

app = express();

if process.env.NODE_ENV == 'production'
  redisURL = url.parse process.env.REDISCLOUD_URL
  #db = redis.createClient redisURL.port, redisURL.hostname, {no_ready_check: true}
  maxAge = 86400000
else
  #db = redis.createClient()
  maxAge = 0

app.use express.static(__dirname + '/public', {maxAge: maxAge})

retrieve_nytimes = (cb) ->
  request 'http://www.nytimes.com', (error, response, body) ->
    return '' if error || response.statusCode != 200
    $ = cheerio.load body

    $('title').text 'The Krugman Times'
    $('.byline').text 'By PAUL KRUGMAN'

    $('img').each (idx, element) ->
      element = $(element)

      if element.attr('id') == 'mastheadLogo'
        element.attr 'src', '/images/krugman_times_logo.png'
        element.parent().prev().remove()      # delete document.write script tag
        element.parent().replaceWith(element) # replace noscript tag with image
        return

      width  = parseInt(element.attr('width'))
      height = parseInt(element.attr('height'))
      return if !width || !height || (width < 40 || height < 40)

      element.attr 'src', KRUGMANZ[idx % KRUGMANZ.length]

    $('.headlinesOnly img').each (idx) ->
      $(this).attr 'src', KRUGMANZ[idx % KRUGMANZ.length]

    headlines = ($(headline).text().replace(/\n/g, " ").trim() for headline in $('h2, h3, h5')).join('\n')
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

app.listen process.env.PORT || 5000