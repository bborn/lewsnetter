import { Controller } from "@hotwired/stimulus"
import EasyMDE from "easymde"

// Wraps a <textarea> in an EasyMDE editor (toolbar, side-by-side preview,
// fullscreen, syntax highlighting). On every keystroke the editor flushes the
// CodeMirror value back to the underlying <textarea> and dispatches a
// "markdown-editor:change" event so other controllers (the campaign preview
// iframe, the AI drafter) can react.
//
// Usage:
//   <textarea data-controller="markdown-editor"
//             data-markdown-editor-target="textarea"
//             ...></textarea>
//
// Other controllers can call the public methods:
//   - setValue(string)  — replace the editor contents
//   - getValue()        — return the current contents
//   - element references via target getters
export default class extends Controller {
  static targets = ["textarea"]

  connect() {
    // Bail out if we've already initialized this element (Turbo can re-invoke
    // connect() on the same node when navigating with morphing).
    if (this.editor) return

    const textarea = this.hasTextareaTarget ? this.textareaTarget : this.element

    // Upload URL for drag/paste/file-picker image inserts. Inferred from the
    // current path on /account/campaigns/:id/edit — POSTs to that campaign's
    // assets collection. On /campaigns/new there's no campaign yet, so we
    // leave it null and turn the image button off entirely.
    this.uploadUrl = this._computeUploadUrl()

    this.editor = new EasyMDE({
      element: textarea,
      spellChecker: true,
      autosave: { enabled: false },
      forceSync: true,
      status: false,
      minHeight: "360px",
      uploadImage: !!this.uploadUrl,
      imageMaxSize: 10 * 1024 * 1024, // 10MB
      imageAccept: 'image/png, image/jpeg, image/gif, image/webp, image/svg+xml',
      imagePathAbsolute: true,
      imageTexts: {
        sbInit: 'Drag or paste an image into the editor, or click the image button to pick a file.',
        sbOnDragEnter: 'Drop the image to upload it.',
        sbOnDrop: 'Uploading image #images_names#…',
        sbProgress: 'Uploading #file_name#: #progress#%',
        sbOnUploaded: 'Uploaded #image_name#'
      },
      errorMessages: {
        noFileGiven: 'You must select a file.',
        typeNotAllowed: 'This image type is not allowed.',
        fileTooLarge: 'Image #image_name# is too large (#image_size#). Max #image_max_size#.',
        importError: 'Something went wrong while uploading #image_name#.'
      },
      imageUploadFunction: this._uploadImage.bind(this),
      // Show the image toolbar button only when we have an upload URL.
      hideIcons: this.uploadUrl ? ["side-by-side"] : ["image", "side-by-side"],
      showIcons: this.uploadUrl ? ["image", "code", "table", "horizontal-rule"] : ["code", "table", "horizontal-rule"],
      toolbar: [
        "bold", "italic", "heading", "|",
        "quote", "unordered-list", "ordered-list", "|",
        "link", ...(this.uploadUrl ? ["image"] : []), "code", "table", "horizontal-rule", "|",
        "preview", "fullscreen", "|",
        "guide"
      ],
      previewClass: ["editor-preview", "prose", "max-w-none"],
      // Use the inline preview as the rendering target so we don't open a
      // side-by-side that pushes the page layout around.
      renderingConfig: {
        singleLineBreaks: false,
        codeSyntaxHighlighting: false
      }
    })

    // forceSync above keeps the underlying textarea in sync on every change,
    // so form submits get the latest markdown. We also fire a custom event
    // here so the preview iframe + form siblings can refresh.
    this.editor.codemirror.on("change", () => {
      this.dispatch("change", { detail: { value: this.editor.value() } })
    })
  }

  disconnect() {
    // EasyMDE leaks DOM (CodeMirror) if we don't tear down on Turbo navigation.
    if (this.editor) {
      this.editor.toTextArea()
      this.editor = null
    }
  }

  // Public API — used by ai_drafter_controller to write AI output back into the
  // editor without losing focus or stomping on the toolbar state.
  setValue(value) {
    if (!this.editor) return
    this.editor.value(value || "")
    // Manually fire change so listeners (preview) pick up the new content.
    this.dispatch("change", { detail: { value: this.editor.value() } })
  }

  getValue() {
    return this.editor ? this.editor.value() : (this.hasTextareaTarget ? this.textareaTarget.value : this.element.value)
  }

  // Public API — used by variable_picker_controller to splice a
  // `{{variable}}` token in at the current selection/cursor position.
  insertAtCursor(text) {
    if (!this.editor) return
    const cm = this.editor.codemirror
    cm.replaceSelection(text)
    cm.focus()
  }

  // Extract the campaign upload URL from the current pathname. Returns null
  // for /campaigns/new (no persisted campaign yet) so the image button stays
  // hidden until the campaign exists.
  _computeUploadUrl() {
    const match = window.location.pathname.match(/^\/account\/campaigns\/([^/]+)/)
    return match ? `/account/campaigns/${match[1]}/assets` : null
  }

  // EasyMDE-shaped upload callback. Receives a single File, posts it as
  // multipart, then resolves with the public URL we should splice into the
  // markdown. EasyMDE handles inserting `![alt](url)` at the cursor itself.
  async _uploadImage(file, onSuccess, onError) {
    if (!this.uploadUrl) {
      onError("Save the campaign first, then images can be uploaded.")
      return
    }

    const csrf = document.querySelector('meta[name=csrf-token]')?.content || ''
    const body = new FormData()
    body.append('file', file)

    try {
      const res = await fetch(this.uploadUrl, {
        method: 'POST',
        headers: { 'X-CSRF-Token': csrf, 'Accept': 'application/json' },
        body,
        credentials: 'same-origin'
      })
      if (!res.ok) {
        const payload = await res.json().catch(() => ({}))
        onError(payload.error || `Upload failed (${res.status}).`)
        return
      }
      const data = await res.json()
      onSuccess(data.url)
    } catch (err) {
      onError(`Upload failed: ${err.message || err}`)
    }
  }
}
