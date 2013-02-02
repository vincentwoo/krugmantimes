var express = require('express');
var app = express();

app.get('/', function(req, res){
  var body = "Hello Krugman's World";
  res.setHeader('Content-Type', 'text/plain');
  res.setHeader('Content-Length', body.length);
  res.end(body);
});

app.listen(process.env.PORT || 5000);
