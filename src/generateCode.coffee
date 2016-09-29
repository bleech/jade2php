jsExpressionToPhp = require './jsExpressionToPhp'

doctypes = require('doctypes')
makeError = require('pug-error')
buildRuntime = require('pug-runtime/build')
runtime = require('pug-runtime')
compileAttrs = require('pug-attrs')
compileAttrs = require('./compileAttrs')
selfClosing = require('void-elements')
constantinople = require('constantinople')
stringify = require('js-stringify')
addWith = require('with')

IF_REGEX = ///^if\s\(\s?(.*)\)$///
ELSE_IF_REGEX = ///^else\s+if\s+\(\s?(.*)\)$///
LOOP_REGEX = ///^(for|while)\s*\((.+)\)$///

# This is used to prevent pretty printing inside certain tags
WHITE_SPACE_SENSITIVE_TAGS =
  pre: true
  textarea: true
INTERNAL_VARIABLES = [
  'pug'
  'pug_mixins'
  'pug_interp'
  'pug_debug_filename'
  'pug_debug_line'
  'pug_debug_sources'
  'pug_html'
]

generateCode = (ast, options) ->
  new Compiler(ast, options).compile()

isConstant = (src) ->
  constantinople src,
    pug: runtime
    'pug_interp': undefined

toConstant = (src) ->
  constantinople.toConstant src,
    pug: runtime
    'pug_interp': undefined

###*
# Initialize `Compiler` with the given `node`.
#
# @param {Node} node
# @param {Object} options
# @api public
###

Compiler = (node, options) ->
  @options = options = options or {}
  @node = node
  @bufferedConcatenationCount = 0
  @hasCompiledDoctype = false
  @hasCompiledTag = false
  @pp = options.pretty or false
  if @pp and typeof @pp != 'string'
    @pp = '  '
  @debug = false != options.compileDebug
  @indents = 0
  @parentIndents = 0
  @terse = false
  @mixins = {}
  @dynamicMixins = false
  @eachCount = 0
  if options.doctype
    @setDoctype options.doctype

  @omitPhpRuntime = options.omitPhpRuntime or false
  @omitPhpExtractor = options.omitPhpExtractor or false
  @arraysOnly = if typeof options.arraysOnly is 'boolean' then options.arraysOnly else true

  @runtimeFunctionsUsed = []
  @inlineRuntimeFunctions = options.inlineRuntimeFunctions or false
  if @debug and @inlineRuntimeFunctions
    @runtimeFunctionsUsed.push 'rethrow'
  return

tagCanInline = (tag) ->

  isInline = (node) ->
    # Recurse if the node is a block
    if node.type == 'Block'
      return node.nodes.every(isInline)
    # When there is a YieldBlock here, it is an indication that the file is
    # expected to be included but is not. If this is the case, the block
    # must be empty.
    if node.type == 'YieldBlock'
      return true
    node.type == 'Text' and !/\n/.test(node.val) or node.isInline

  tag.block.nodes.every isInline

module.exports = generateCode
module.exports.CodeGenerator = Compiler

###*
# Compiler prototype.
###

Compiler.prototype =
  jsExpressionToPhp: (s) ->
    jsExpressionToPhp s,
      arraysOnly: @arraysOnly

  runtime: (name) ->
    if @inlineRuntimeFunctions
      @runtimeFunctionsUsed.push name
      'pug_' + name
    else
      'pug.' + name
  error: (message, code, node) ->
    err = makeError(code, message,
      line: node.line
      filename: node.filename)
    throw err
    return
  compile: ->
    @buf = []
    if @pp
      @buf.push 'var pug_indent = [];'
    @lastBufferedIdx = -1
    @visit @node
    if !@dynamicMixins
      # if there are no dynamic mixins we can remove any un-used mixins
      mixinNames = Object.keys(@mixins)
      i = 0
      while i < mixinNames.length
        mixin = @mixins[mixinNames[i]]
        if !mixin.used
          x = 0
          while x < mixin.instances.length
            y = mixin.instances[x].start
            while y < mixin.instances[x].end
              @buf[y] = ''
              y++
            x++
        i++
    # js = @buf.join('\n')
    result = ''
    result += require './phpRuntimeCode' unless @omitPhpRuntime
    result += require './phpExtractorCode' unless @omitPhpExtractor
    result += @buf.join('')
    result

  setDoctype: (name) ->
    @doctype = doctypes[name.toLowerCase()] or '<!DOCTYPE ' + name + '>'
    @terse = @doctype.toLowerCase() == '<!doctype html>'
    @xml = 0 == @doctype.indexOf('<?xml')
    return
  buffer: (str) ->
    self = this
    if @lastBufferedIdx == @buf.length and @bufferedConcatenationCount < 100
      if @lastBufferedType == 'code'
        @bufferedConcatenationCount++
      @lastBufferedType = 'text'
      @lastBuffered += str
      @buf[@lastBufferedIdx - 1] = @bufferStartChar + @lastBuffered
    else
      @bufferedConcatenationCount = 0
      @buf.push str
      @lastBufferedType = 'text'
      @bufferStartChar = ''
      @lastBuffered = str
      @lastBufferedIdx = @buf.length
    return
  bufferExpression: (src) ->
    if isConstant(src)
      return @buffer(toConstant(src) + '')
    if @lastBufferedIdx == @buf.length and @bufferedConcatenationCount < 100
      @bufferedConcatenationCount++
      if @lastBufferedType == 'text'
        @lastBuffered += ''
      @lastBufferedType = 'code'
      @lastBuffered += src
      @buf[@lastBufferedIdx - 1] = @bufferStartChar + @lastBuffered
    else
      @bufferedConcatenationCount = 0
      @buf.push src
      @lastBufferedType = 'code'
      @bufferStartChar = ''
      @lastBuffered = '(' + src + ')'
      @lastBufferedIdx = @buf.length
    return
  prettyIndent: (offset, newline) ->
    offset = offset or 0
    newline = if newline then '\n' else ''
    @buffer newline + Array(@indents + offset).join(@pp)
    if @parentIndents
      @buf.push 'pug_html = pug_html + pug_indent.join("");'
    return
  visit: (node, parent) ->
    msg = null
    debug = @debug
    if !node
      msg = undefined
      if parent
        msg = 'A child of ' + parent.type + ' (' + (parent.filename or 'Pug') + ':' + parent.line + ')'
      else
        msg = 'A top-level node'
      msg += ' is ' + node + ', expected a Pug AST Node.'
      throw new TypeError(msg)
    if debug and node.debug != false and node.type != 'Block'
      if node.line
        js = ';pug_debug_line = ' + node.line
        if node.filename
          js += ';pug_debug_filename = ' + stringify(node.filename)
        @buf.push js + ';'
    if !@['visit' + node.type]
      msg = undefined
      if parent
        msg = 'A child of ' + parent.type
      else
        msg = 'A top-level node'
      msg += ' (' + (node.filename or 'Pug') + ':' + node.line + ')' + ' is of type ' + node.type + ',' + ' which is not supported by pug-code-gen.'
      switch node.type
        when 'Filter'
          msg += ' Please use pug-filters to preprocess this AST.'
        when 'Extends', 'Include', 'NamedBlock', 'FileReference'
          # unlikely but for the sake of completeness
          msg += ' Please use pug-linker to preprocess this AST.'
      throw new TypeError(msg)
    @visitNode node
    return
  visitNode: (node) ->
    @['visit' + node.type] node
  visitCase: (node) ->
    @buf.push "<?php switch (#{@jsExpressionToPhp node.expr}) : ?>"
    @visit node.block, node
    @buf.push "<?php endswitch ?>"
    return
  visitWhen: (node) ->
    if 'default' == node.expr
      @buf.push "<?php default : ?>"
    else
      @buf.push "<?php case #{@jsExpressionToPhp node.expr} : ?>"
    if node.block
      @visit node.block, node
      @buf.push "<?php break ?>" unless "default" is node.expr
    return
  visitLiteral: (node) ->
    @buffer node.str
    return
  visitNamedBlock: (block) ->
    @visitBlock block
  visitBlock: (block) ->
    escapePrettyMode = @escapePrettyMode
    pp = @pp
    # Pretty print multi-line text
    if pp and block.nodes.length > 1 and !escapePrettyMode and block.nodes[0].type == 'Text' and block.nodes[1].type == 'Text'
      @prettyIndent 1, true
    i = 0
    while i < block.nodes.length
      # Pretty print text
      if pp and i > 0 and !escapePrettyMode and block.nodes[i].type == 'Text' and block.nodes[i - 1].type == 'Text' and /\n$/.test(block.nodes[i - 1].val)
        @prettyIndent 1, false
      @visit block.nodes[i], block
      ++i
    return
  visitMixinBlock: (block) ->
    @buf.push "<?php if (is_callable($block)) $block(); ?>"
    return
  visitDoctype: (doctype) ->
    if doctype and (doctype.val or !@doctype)
      @setDoctype doctype.val or 'html'
    if @doctype
      if ///<\?///.test @doctype
        @buf.push "<?php echo \'#{@doctype.replace "'", "\'"}\' ?>"
      else
        @buffer @doctype
    @hasCompiledDoctype = true
    return
  visitMixin: (mixin) ->
    args = mixin.args or ""
    block = mixin.block
    attrs = mixin.attrs
    attrsBlocks = mixin.attributeBlocks

    rest = undefined
    if args and ///\.\.\.[a-zA-Z_][a-z_A-Z0-9]*\s*$///.test args
      args = args.split(',')
      rest = args.pop().trim().replace(/^\.\.\./, "")
      args = if args.length > 0 then args.join(',') else undefined
    phpArgs = if args then @jsExpressionToPhp(args).replace(///;$///, '') else undefined

    phpMixinName = mixin.name.replace ///-///g, '_'

    pp = @pp
    dynamic = mixin.name[0] is "#"
    key = mixin.name
    @dynamicMixins = true  if dynamic
    @mixins[key] = @mixins[key] or
      used: false
      instances: []

    if mixin.call
      @mixins[key].used = true
      @buf.push "<?php mixin__#{phpMixinName}("

      if block
        @buf.push "function()"
        @buf.push " use ($block) " if @insideMixin
        @buf.push "{ ?>"
        @buf.push require './phpExtractorCode' unless @omitPhpExtractor
        @visit block
        @buf.push "<?php }"
      else
        @buf.push "null" if phpArgs or attrs.length > 0

      if attrs.length > 0
        preMergedAttrs = {}
        for attr in attrs
          if attr.name is 'class'
            preMergedAttrs.class = [] unless preMergedAttrs.class
            preMergedAttrs.class.push attr.val
          else
            preMergedAttrs[attr.name] = attr.val
        @buf.push ", array(" + (for key, value of preMergedAttrs
          """'#{key}' => #{@jsExpressionToPhp if key is 'class' then "[#{value}]" else value}"""
        ).join(', ') + ")"
      else
        @buf.push ", array()" if phpArgs

      @buf.push ", #{phpArgs}" if phpArgs
      @buf.push ") ?>"
    else
      mixin_start = @buf.length
      mixinAttrs = ['$block = null', '$attributes = array()']
      if phpArgs
        for phpArg in phpArgs.split ', '
          mixinAttrs.push "#{phpArg} = null"
      @buf.push "<?php if (!function_exists('mixin__#{phpMixinName}')) { function mixin__#{phpMixinName}(#{mixinAttrs.join ', '}) { "
      if rest
        @buf.push "#{@jsExpressionToPhp rest} = array_slice(func_get_args(), #{mixinAttrs.length}); "
      if phpArgs
        @buf.push "global $■;"
        @buf.push ("$■['#{phpArg.replace '$', ''}'] = #{phpArg};" for phpArg in phpArgs.split ', ').join ''
      @buf.push "?>"
      @parentIndents++
      oldInsideMixin = @insideMixin
      @insideMixin = yes
      @visit block, mixin
      @insideMixin = oldInsideMixin
      @parentIndents--
      @buf.push "<?php } } ?>"
      mixin_end = @buf.length
      @mixins[key].instances.push
        start: mixin_start
        end: mixin_end

    return
  visitTag: (tag, interpolated) ->

    bufferName = ->
      if interpolated
        self.bufferExpression tag.expr
      else
        self.buffer name
      return

    @indents++
    name = tag.name
    pp = @pp
    self = this
    if WHITE_SPACE_SENSITIVE_TAGS[tag.name] == true
      @escapePrettyMode = true
    if !@hasCompiledTag
      if !@hasCompiledDoctype and 'html' == name
        @visitDoctype()
      @hasCompiledTag = true
    # pretty print
    if pp and !tag.isInline
      @prettyIndent 0, true
    if tag.selfClosing or !@xml and selfClosing[tag.name]
      @buffer '<'
      bufferName()
      @visitAttributes tag.attrs, tag.attributeBlocks.slice()
      if @terse and !tag.selfClosing
        @buffer '>'
      else
        @buffer '/>'
      # if it is non-empty throw an error
      if tag.code or tag.block and !(tag.block.type == 'Block' and tag.block.nodes.length == 0) and tag.block.nodes.some(((tag) ->
          tag.type != 'Text' or !/^\s*$/.test(tag.val)
        ))
        @error name + ' is a self closing element: <' + name + '/> but contains nested content.', 'SELF_CLOSING_CONTENT', tag
    else
      # Optimize attributes buffering
      @buffer '<'
      bufferName()
      @visitAttributes tag.attrs, tag.attributeBlocks.slice()
      @buffer '>'
      if tag.code
        @visitCode tag.code
      @visit tag.block, tag
      # pretty print
      if pp and !tag.isInline and WHITE_SPACE_SENSITIVE_TAGS[tag.name] != true and !tagCanInline(tag)
        @prettyIndent 0, true
      @buffer '</'
      bufferName()
      @buffer '>'
    if WHITE_SPACE_SENSITIVE_TAGS[tag.name] == true
      @escapePrettyMode = false
    @indents--
    return
  visitInterpolatedTag: (tag) ->
    @visitTag tag, true
  visitText: (text) ->
    @buffer text.val
    return
  visitComment: (comment) ->
    if !comment.buffer
      return
    if @pp
      @prettyIndent 1, true
    @buffer '<!--' + comment.val + '-->'
    return
  visitYieldBlock: (block) ->
  visitBlockComment: (comment) ->
    if !comment.buffer
      return
    if @pp
      @prettyIndent 1, true
    @buffer '<!--' + (comment.val or '')
    @visit comment.block, comment
    if @pp
      @prettyIndent 1, true
    @buffer '-->'
    return
  visitCode: (code) ->
    if code.buffer
      val = code.val.trimLeft()
      val = @jsExpressionToPhp val
      val = "htmlspecialchars(" + val + ")"  if code.mustEscape isnt false
      val = '<?php echo ' + val + ' ?>'
      @bufferExpression val
    else if IF_REGEX.test code.val
      m = code.val.match IF_REGEX
      condition = m[1]
      @visitConditional
        condition: condition
        block: code.block
        nextElses: @nextElses
    else if ///^else///.test code.val
      # ignore else and else-if, they was catched in @nextElses when processing first if
    else if LOOP_REGEX.test code.val
      @visitLoop code
    else
      @buf.push "<?php #{@jsExpressionToPhp code.val} ?>"

      # Block support
      if code.block
        @visit code.block
    return
  visitLoop: (loopNode) ->
    m = loopNode.val.match LOOP_REGEX
    loopType = m[1]
    conditions = m[2]
    @buf.push "<?php #{loopType} (#{@jsExpressionToPhp conditions}) : ?>"
    @visit(loopNode.block, loopNode) if loopNode.block
    @buf.push "<?php end#{loopType} ?>"
  visitConditional: (cond, nested = false) ->
    test = cond.test
    unless nested
      @buf.push "<?php if (#{@jsExpressionToPhp test}) : ?>"
    else
      @buf.push "<?php elseif (#{@jsExpressionToPhp test}) : ?>"
    @visit cond.consequent, cond
    if cond.alternate
      if cond.alternate.type is 'Conditional'
        @visitConditional cond.alternate, true
      else
        @buf.push "<?php else : ?>"
        @visit cond.alternate, cond
    unless nested
      @buf.push "<?php endif ?>"
  visitWhile: (loopNode)->
    test = loopNode.test
    @buf.push "<?php while (#{@jsExpressionToPhp test}) : ?>"
    @visit loopNode.block, loopNode if loopNode.block
    @buf.push "<?php endwhile ?>"
    return
  visitEach: (each) ->
    as = if each.key
      "#{@jsExpressionToPhp each.key} => #{@jsExpressionToPhp each.val}"
    else
      @jsExpressionToPhp each.val
    scopePushPhp = ""
    scopePushPhp += "$■['#{each.key}'] = #{@jsExpressionToPhp each.key};" if each.key
    scopePushPhp += "$■['#{each.val}'] = #{@jsExpressionToPhp each.val};"
    @buf.push "<?php if (#{@jsExpressionToPhp each.obj}) : foreach (#{@jsExpressionToPhp each.obj} as #{as}) : #{scopePushPhp} ?>"
    @visit each.block, each
    unless each.alternate
      @buf.push "<?php endforeach; endif ?>"
    else
      @buf.push "<?php endforeach; else : ?>"
      @visit each.alternate
      @buf.push "<?php endif ?>"
    return
  visitAttributes: (attrs, attributeBlocks) ->
    if attributeBlocks.length
      if attrs.length
        val = @attrs(attrs)
        attributeBlocks.unshift val
      if attributeBlocks.length > 1
        @bufferExpression "<?php pug_attrs(array_merge(" + attributeBlocks.map((attr) => @jsExpressionToPhp(attr)).join(',') + '), ' + stringify(@terse) + '); ?>'
      else
        @bufferExpression "<?php pug_attrs(" + @jsExpressionToPhp(attributeBlocks[0]) + ', ' + stringify(@terse) + '); ?>'
    else if attrs.length
      @attrs attrs, true
    return
  attrs: (attrs, buffer) ->
    res = compileAttrs(attrs,
      terse: @terse
      format: if buffer then 'html' else 'object'
      runtime: @runtime.bind(this)
      jsExpressionToPhp: @jsExpressionToPhp.bind(this)
    )
    if buffer
      @bufferExpression res
    res
