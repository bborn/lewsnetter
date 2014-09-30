#= require jquery_2
#= require jquery_ujs
#= require bootstrap
#= require medium-editor
#= require mediumbutton
#= require_self

class @Editor
  constructor: (@selector) ->
    self = @
    @boundTextArea

  initMedium: ->
    @medium = new MediumEditor(@selector,
      firstHeader: "h1"
      secondHeader: "h2"
      cleanPastedHTML: true
      placeholder: ''
      buttonLabels : 'fontawesome'
      buttons: [
        'bold'
        'italic'
        'underline'
        'anchor'
        'header1'
        'header2'
        'quote'
        'image'
        'newline'
      ]
      extensions: {
        'newline': @insertNewLine()
      }

    )

  insertNewLine : ->
    thiz = @
    button = new MediumButton(
      label: "<i class=\"fa fa-level-down\"></i>"
      action: (html, mark) ->
        parentNode = thiz.medium.getSelectedParentElement()
        $(parentNode).before("<p>New paragraph</p>")
        thiz.clearSelection()
        thiz.medium.hideToolbarActions()
        html
    )
    button


  serialize: ->
    @medium.serialize()

  loadContents: (json) ->
    for element in @medium.elements
      #load the contents into the template
      if json[$(element).attr("id")]
        $(element).html json[$(element).attr("id")].value

  replaceHTML: (newHtml) ->
    if confirm('This will replace any content you\'ve already added. Are you sure?')
      $(@medium.elements[0]).html newHtml
      if @boundTextArea
        json_string = JSON.stringify(@medium.serialize())
        $(@boundTextArea).val json_string
    return

  bindToTextArea: (textArea) ->
    @boundTextArea = textArea
    #listen for changes and update the form
    for element in @medium.elements
      $(element).on "input", =>
        json_string = JSON.stringify(@medium.serialize())
        $(textArea).val json_string
        return

  clearSelection : ->
    if document.selection
      document.selection.empty()
    else window.getSelection().removeAllRanges()  if window.getSelection
    return
