express = require('express')
redis   = require('redis')
url     = require('url')
cheerio = require('cheerio')
request = require('request')

KRUGMANZ = [
  'http://media.salon.com/2010/04/pistols_at_dawn_paul_krugman_vs_andrew_sorkin.jpg',
  'http://www.wired.com/images_blogs/underwire/2012/05/Krugman-6601.jpg',
  'http://www.skepticmoney.com/wp-content/uploads/2012/08/Paul-Krugman.jpg',
  'http://www.princeton.edu/~paw/web_exclusives/more/more_pics/more6_krugman.jpg'
]
app = express();
maxAge = 0;

app.configure 'development', () ->
  db = redis.createClient();

app.configure 'production', () ->
  redisURL = url.parse process.env.REDISCLOUD_URL
  db = redis.createClient redisURL.port, redisURL.hostname, {no_ready_check: true}
  maxAge = 86400000;


app.get '/', (req, res) ->
  #http://access.alchemyapi.com/calls/url/URLGetRankedNamedEntities?apikey=3c834e2a6bb7f81706b92a9aebe3d307d53ff9ec&url=nytimes.com&outputMode=json
  request 'http://www.nytimes.com', (error, response, body) ->
    $ = cheerio.load(body);

    $('title').text 'The Krugman Times';
    $('.byline').text 'By PAUL KRUGMAN';

    $('img').each (idx, element) ->
      element = $(element);

      if element.attr('id') == 'mastheadLogo'
        element.attr('src', '/images/krugman_times_logo.png');
        element.parent().prev().remove();      # delete document.write script tag
        element.parent().replaceWith(element); # replace noscript tag with image
        return

      width  = parseInt(element.attr('width'))
      height = parseInt(element.attr('height'))
      return if !width || !height || (width < 40 || height < 40)

      element.attr 'src', KRUGMANZ[idx % KRUGMANZ.length]

    $('.headlinesOnly img').each (idx) ->
      $(this).attr 'src', KRUGMANZ[idx % KRUGMANZ.length]

    body = $.html();
    res.charset = 'utf-8';
    res.setHeader 'Content-Type', 'text/html';
    res.setHeader 'Content-Length', body.length;
    res.end body;

app.use(express.static(__dirname + '/public', {maxAge: maxAge}))

app.listen process.env.PORT || 5000
