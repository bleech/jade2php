applyPlugins = (value, options, plugins, name) ->
  plugins.reduce ((value, plugin) ->
    if plugin[name] then plugin[name](value, options) else value
  ), value

findReplacementFunc = (plugins, name) ->
  eligiblePlugins = plugins.filter((plugin) ->
    plugin[name]
  )
  if eligiblePlugins.length > 1
    throw new Error('Two or more plugins all implement ' + name + ' method.')
  else if eligiblePlugins.length
    return eligiblePlugins[0][name].bind(eligiblePlugins[0])
  null

'use strict'

###!
# Pug
# Copyright(c) 2010 TJ Holowaychuk <tj@vision-media.ca>
# MIT Licensed
###

###*
# Module dependencies.
###

fs = require('fs')
path = require('path')
lex = require('pug-lexer')
stripComments = require('pug-strip-comments')
parse = require('pug-parser')
load = require('pug-load')
filters = require('pug-filters')
link = require('pug-linker')
# generateCode = require('pug-code-gen')
generateCode = require './generateCode'
runtime = require('pug-runtime')
runtimeWrap = require('pug-runtime/wrap')

###*
# Pug runtime helpers.
###

exports.runtime = runtime

###*
# Template function cache.
###

exports.cache = {}

###*
# Object for global custom filters.  Note that you can also just pass a `filters`
# option to any other method.
###

exports.filters = {}

compile = (str, options = {}) ->
  str = String(str)
  parsed = compileBody(str,
    compileDebug: false#options.compileDebug != false
    filename: options.filename
    basedir: options.basedir
    pretty: false#options.pretty
    doctype: options.doctype
    inlineRuntimeFunctions: false#options.inlineRuntimeFunctions
    globals: options.globals
    self: options.self
    includeSources: false#options.compileDebug == true
    debug: false#options.debug
    templateName: 'template'
    filters: options.filters
    filterOptions: options.filterOptions
    omitPhpRuntime: options.omitPhpRuntime
    omitPhpExtractor: options.omitPhpExtractor
    plugins: options.plugins)
  res = parsed.body
  res.dependencies = parsed.dependencies
  res

compileBody = (str, options) ->
  debug_sources = {}
  debug_sources[options.filename] = str
  dependencies = []
  plugins = options.plugins or []
  ast = load.string(str,
    filename: options.filename
    basedir: options.basedir
    lex: (str, options) ->
      lexOptions = {}
      Object.keys(options).forEach (key) ->
        lexOptions[key] = options[key]
        return
      lexOptions.plugins = plugins.filter((plugin) ->
        ! !plugin.lex
      ).map((plugin) ->
        plugin.lex
      )
      applyPlugins lex(str, lexOptions), options, plugins, 'postLex'
    parse: (tokens, options) ->
      tokens = tokens.map((token) ->
        if token.type == 'path' and path.extname(token.val) == ''
          return {
            type: 'path'
            line: token.line
            col: token.col
            val: token.val + '.pug'
          }
        token
      )
      tokens = stripComments(tokens, options)
      tokens = applyPlugins(tokens, options, plugins, 'preParse')
      parseOptions = {}
      Object.keys(options).forEach (key) ->
        parseOptions[key] = options[key]
        return
      parseOptions.plugins = plugins.filter((plugin) ->
        ! !plugin.parse
      ).map((plugin) ->
        plugin.parse
      )
      applyPlugins applyPlugins(parse(tokens, parseOptions), options, plugins, 'postParse'), options, plugins, 'preLoad'
    resolve: (filename, source, loadOptions) ->
      replacementFunc = findReplacementFunc(plugins, 'resolve')
      if replacementFunc
        return replacementFunc(filename, source, options)
      load.resolve filename, source, loadOptions
    read: (filename, loadOptions) ->
      str = null
      dependencies.push filename
      contents = undefined
      replacementFunc = findReplacementFunc(plugins, 'read')
      if replacementFunc
        contents = replacementFunc(filename, options)
      else
        contents = load.read(filename, loadOptions)
      str = applyPlugins(contents, { filename: filename }, plugins, 'preLex')
      debug_sources[filename] = str
      str
  )
  ast = applyPlugins(ast, options, plugins, 'postLoad')
  ast = applyPlugins(ast, options, plugins, 'preFilters')
  filtersSet = {}
  Object.keys(exports.filters).forEach (key) ->
    filtersSet[key] = exports.filters[key]
    return
  if options.filters
    Object.keys(options.filters).forEach (key) ->
      filtersSet[key] = options.filters[key]
      return
  ast = filters.handleFilters(ast, filtersSet, options.filterOptions)
  ast = applyPlugins(ast, options, plugins, 'postFilters')
  ast = applyPlugins(ast, options, plugins, 'preLink')
  ast = link(ast)
  ast = applyPlugins(ast, options, plugins, 'postLink')
  # Compile
  ast = applyPlugins(ast, options, plugins, 'preCodeGen')
  js = generateCode(ast,
    pretty: options.pretty
    compileDebug: options.compileDebug
    doctype: options.doctype
    inlineRuntimeFunctions: options.inlineRuntimeFunctions
    globals: options.globals
    self: options.self
    includeSources: if options.includeSources then debug_sources else false
    omitPhpRuntime: options.omitPhpRuntime
    omitPhpExtractor: options.omitPhpExtractor
    templateName: options.templateName)
  js = applyPlugins(js, options, plugins, 'postCodeGen')
  # Debug compiler
  if options.debug
    console.error '\nCompiled Function:\n\n[90m%s[0m', js.replace(/^/gm, '  ')
  {
    body: js
    dependencies: dependencies
  }

module.exports = compile
