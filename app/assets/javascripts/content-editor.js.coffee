#= require jquery_2
#= require jquery_ujs
#= require bootstrap
#= require ckeditor/init
#= require_self

class @Editor
  constructor: (@selector) ->
    self = @
    @boundTextArea

  initCkeditor: (opts)->
    CKEDITOR.disableAutoInline = true
    CKEDITOR.dtd.$editable.td = 1

    $(@selector).each (i, elm)->
      $(elm).attr('contenteditable', true)
      conf = {toolbar: 'mini'}
      if opts.readOnly
        conf.readOnly = true
      CKEDITOR.inline( elm, conf)

  deactivate: ->
    for n, instance of CKEDITOR.instances
      console.log instance
      instance.setReadOnly()

  serialize: ->
    json = {}
    for n, instance of CKEDITOR.instances
      json[n] = instance.getData()

    json

  loadContents: (json) ->
    for n, instance of CKEDITOR.instances
      #load the contents into the template
      if json[n]
        instance.setData json[n]

  replaceHTML: (newHtml) ->
    if confirm('This will replace any content you\'ve already added. Are you sure?')
      CKEDITOR.instances[Object.keys(CKEDITOR.instances)[0]].setData newHtml
      if @boundTextArea
        json_string = JSON.stringify(@serialize())
        $(@boundTextArea).val json_string
    return

  bindToTextArea: (textArea) ->
    console.log textArea
    @boundTextArea = textArea
    #listen for changes and update the form
    for name, instance of CKEDITOR.instances
      instance.on 'change', ()=>
        json_string = JSON.stringify(@serialize())
        $(textArea).val json_string
        return
