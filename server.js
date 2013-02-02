var express = require('express');
var redis = require('redis');
var cheerio = require('cheerio');
var request = require('request');

var db = redis.createClient();
var app = express();

app.get('/', function(req, res){
  request('http://www.nytimes.com', function (error, response, body) {
  if (error || response.statusCode != 200) return;
    res.setHeader('Content-Type', 'text/html');
    res.setHeader('Content-Length', body.length);
    res.end(body);
  })
});

app.listen(process.env.PORT || 5000);
