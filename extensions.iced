_ = require 'underscore'

String.prototype.titlecase = ->
  this.split(/\s/).map (str) ->
    ret = str.trim().split('')
    return '' if ret.length == 0
    ret[0] = ret[0].toUpperCase();
    ret.join('')
  .join(' ')

String.prototype.capitalize = ->
  ret = this.trim()
  ret = ret.charAt(0).toUpperCase() + ret.slice(1)

Array.prototype.sample = (number) ->
  if number == undefined
    if this.length > 0 then this[_.random(this.length - 1)] else null
  else
    if number > 0 then _.shuffle(this).slice(0, number) else []
