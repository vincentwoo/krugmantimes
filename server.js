var express = require('express');
var redis = require('redis');
var url = require('url');
var cheerio = require('cheerio');
var request = require('request');

var db;
var app = express();

app.configure('development', function() {
  db = redis.createClient();
});
app.configure('production', function() {
  var redisURL = url.parse(process.env.REDISCLOUD_URL);
  db = redis.createClient(
    redisURL.port, redisURL.hostname, {no_ready_check: true});
});

app.get('/', function(req, res){
  request('http://www.nytimes.com', function (error, response, body) {
    if (error || response.statusCode != 200) return;
    res.setHeader('Content-Type', 'text/html');
    res.setHeader('Content-Length', body.length);
    res.end(body);
  })
});

app.listen(process.env.PORT || 5000);
