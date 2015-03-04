Components.utils.import('resource://gre/modules/Services.jsm')

Zotero.ReportCustomizer =
  parser: Components.classes['@mozilla.org/xmlextras/domparser;1'].createInstance(Components.interfaces.nsIDOMParser)
  serializer: Components.classes['@mozilla.org/xmlextras/xmlserializer;1'].createInstance(Components.interfaces.nsIDOMSerializer)

  set: (key, value) ->
    return Zotero.Prefs.set(".report-customizer.#{key}", value)

  get: (key) ->
    return Zotero.Prefs.get(".report-customizer.#{key}")

  show: (key, visible) ->
    if typeof visible == 'undefined' # get state
      try
        return not @get("remove.#{key}")
      return true

    # set state
    @set("remove.#{key}", not visible)
    return visible

  openPreferenceWindow: (paneID, action) ->
    io = {
      pane: paneID
      action: action
    }
    window.openDialog(
      'chrome://zotero-report-customizer/content/options.xul',
      'zotero-report-customizer-options',
      'chrome,titlebar,toolbar,centerscreen' + (if Zotero.Prefs.get('browser.preferences.instantApply', true) then 'dialog=no' else 'modal'),
      io
    )
    return

  label: (name) ->
    @labels ?= Object.create(null)
    @labels[name] ?= {
      name: name
      label: Zotero.getString("itemFields.#{name}")
    }
    return @labels[name]

  addField: (type, field) ->
    type.fields.push(field)
    @fields[field.name] = true
    return

  log: (msg...) ->
    msg = for m in msg
      switch
        when (typeof m) in ['string', 'number'] then '' + m
        when Array.isArray(m) then JSON.stringify(m)
        when m instanceof Error and m.name then "#{m.name}: #{m.message} \n(#{m.fileName}, #{m.lineNumber})\n#{m.stack}"
        when m instanceof Error then "#{e}\n#{e.stack}"
        else JSON.stringify(m)

    Zotero.debug("[report-customizer] #{msg.join(' ')}")
    return

  init: ->
    @tree = []
    @fields = {}
    collation = Zotero.getLocaleCollation()

    for type in Zotero.ItemTypes.getSecondaryTypes()
      @tree.push({
        id: type.id
        name: type.name
        label: Zotero.ItemTypes.getLocalizedString(type.id)
      })
    @tree.sort((a, b) -> collation.compareString(1, a.label, b.label))

    for type in @tree
      type.fields = []
      @addField(type, @label('itemType'))

      # getItemTypeFields yields an iterator, not an arry, so we can't just add them
      @addField(type, @label(Zotero.ItemFields.getName(field))) for field in Zotero.ItemFields.getItemTypeFields(type.id)
      @addField(type, @label('citekey')) if Zotero.BetterBibTex
      @addField(type, @label('tags'))
      @addField(type, @label('attachments'))
      @addField(type, @label('related'))
      @addField(type, @label('notes'))
      @addField(type, @label('dateAdded'))
      @addField(type, @label('dateModified'))
      @addField(type, @label('accessDate'))
      @addField(type, @label('extra'))
    @fields = Object.keys(@fields)

    # Load in the localization stringbundle for use by getString(name)
    @localizedStringBundle = Services.strings.createBundle('chrome://zotero-report-customizer/locale/zotero-report-customizer.properties', Services.locale.getApplicationLocale())
    Zotero.ItemFields.getLocalizedString = ((original) ->
      return (itemType, field) ->
        try
          return Zotero.ReportCustomizer.localizedStringBundle.GetStringFromName('itemFields.citekey') if field == 'citekey'
        # pass to original for consistent error messages
        return original.apply(this, arguments)
    )(Zotero.ItemFields.getLocalizedString)

    # monkey-patch Zotero.getString to supply new translations
    Zotero.getString = ((original) ->
      return (name, params) ->
        try
          return Zotero.ReportCustomizer.localizedStringBundle.GetStringFromName(name)  if name == 'itemFields.citekey'
        # pass to original for consistent error messages
        return original.apply(this, arguments)
    )(Zotero.getString)

    return

class Zotero.ReportCustomizer.XmlNode
  constructor: (@namespace, @root, @doc) ->
    if !@doc
      @doc = Zotero.OPDS.document.implementation.createDocument(@namespace, @root, null)
      @root = @doc.documentElement

  serialize: -> Zotero.OPDS.serializer.serializeToString(@doc)

  alias: (name) -> (v...) -> Zotero.ReportCustomizer.XmlNode::add.apply(@, [{"#{name}": v[0]}].concat(v.slice(1)))

  set: (node, attrs...) ->
    for attr in attrs
      for own name, value of attr
        if name == ''
          if typeof value == 'function'
            value.call(new @Node(@namespace, node, @doc))
          else node.appendChild(@doc.createTextNode('' + v))
        else
          node.setAttribute(name, '' + value)
    return

  add: (content...) ->
    for what in content
      switch
        when typeof what == 'string'
          @root.appendChild(@doc.createTextNode(what))
          continue

        when typeof what == 'function'
          what.call(new @Node(@namespace, @root, @doc))
          continue

        when what.appendChild
          @root.appendChild(what)
          continue

      for own name, value of what
        Zotero.ReportCustomizer.log("creating node #{name}")
        node = @doc.createElementNS(@namespace, name)
        @root.appendChild(node)

        switch typeof value
          when 'function'
            value.call(new @Node(@namespace, node, @doc))

          when 'string', 'number'
            node.appendChild(@doc.createTextNode('' + value))

          else # assume node with attributes
            @set(node, value)

    return

# Initialize the utility
window.addEventListener('load', ((e) ->
  Zotero.ReportCustomizer.init()
  return
), false)
