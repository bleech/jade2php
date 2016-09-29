isConstant = (src) ->
  constantinople src,
    pug: runtime
    'pug_interp': undefined

toConstant = (src) ->
  constantinople.toConstant src,
    pug: runtime
    'pug_interp': undefined

###*
# options:
#  - terse
#  - runtime
#  - format ('html' || 'object')
###

compileAttrs = (attrs, options) ->

  addAttribute = (key, val, mustEscape, buf) ->
    if isConstant(val)
      if options.format == 'html'
        str = (runtime.attr(key, toConstant(val), mustEscape, options.terse))
        last = buf[buf.length - 1]
        if last and last[last.length - 1] == str[0]
          buf[buf.length - 1] = last.substr(0, last.length - 1) + str.substr(1)
        else
          buf.push str
      else
        val = toConstant(val)
        if mustEscape
          val = runtime.escape(val)
        buf.push stringify(key) + ': ' + stringify(val)
    else
      if options.format == 'html'
        buf.push "<?php pug_attr('#{key}', #{options.jsExpressionToPhp val}, #{if mustEscape then 'true' else 'false'}) ?>"
      else
        if mustEscape
          val = 'pug_escape(' + val + ')'
        buf.push stringify(key) + ': ' + val
    return

  assert Array.isArray(attrs), 'Attrs should be an array'
  assert attrs.every((attr) ->
    attr and typeof attr == 'object' and typeof attr.name == 'string' and (typeof attr.val == 'string' or typeof attr.val == 'boolean') and typeof attr.mustEscape == 'boolean'
  ), 'All attributes should be supplied as an object of the form {name, val, mustEscape}'
  assert options and typeof options == 'object', 'Options should be an object'
  assert typeof options.terse == 'boolean', 'Options.terse should be a boolean'
  assert typeof options.runtime == 'function', 'Options.runtime should be a function that takes a runtime function name and returns the source code that will evaluate to that function at runtime'
  assert options.format == 'html' or options.format == 'object', 'Options.format should be "html" or "object"'
  buf = []
  classes = []
  classEscaping = []
  attrs.forEach (attr) ->
    key = attr.name
    val = attr.val
    mustEscape = attr.mustEscape
    if key == 'class'
      classes.push val
      classEscaping.push mustEscape
    else
      if key == 'style'
        if isConstant(val)
          val = stringify(runtime.style(toConstant(val)))
        else
          val = options.runtime('style') + '(' + val + ')'
      addAttribute key, val, mustEscape, buf
    return
  classesBuf = []
  if classes.length
    if classes.every(isConstant)
      addAttribute 'class', stringify(runtime.classes(classes.map(toConstant), classEscaping)), false, classesBuf
    else
      classes = classes.map((cls, i) ->
        if isConstant(cls)
          cls = stringify(if classEscaping[i] then runtime.escape(toConstant(cls)) else toConstant(cls))
          classEscaping[i] = false
          cls
        else
          cls
      )
      addAttribute 'class', 'pug_classes([' + classes.join(',') + '], ' + stringify(classEscaping) + ')', false, classesBuf
  buf = classesBuf.concat(buf)
  if options.format == 'html'
    if buf.length then buf.join('') else '""'
  else
    '{' + buf.join(',') + '}'

'use strict'
assert = require('assert')
constantinople = require('constantinople')
runtime = require('pug-runtime')
stringify = require('js-stringify')
module.exports = compileAttrs
