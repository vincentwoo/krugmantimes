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
    if this.length > 0 then this[Math.floor(Math.random(this.length))] else null
  else
    if number > 0 then _.shuffle(this).slice(0, number) else []