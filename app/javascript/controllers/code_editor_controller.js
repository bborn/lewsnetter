import { Controller } from "@hotwired/stimulus"
import { EditorView, basicSetup } from "codemirror"
import { EditorState } from "@codemirror/state"
import { xml } from "@codemirror/lang-xml"

// Wraps a <textarea> in a CodeMirror 6 editor with XML/MJML syntax
// highlighting, line numbers, bracket matching, and search. The original
// textarea is kept in the DOM but visually hidden — its value is synced on
// every CodeMirror update so form submits capture the current contents.
//
// Image flow (when `data-code-editor-upload-url-value` is set):
//   - Drag image(s) onto the editor → uploaded, inserted at drop position.
//   - Paste image from clipboard (Cmd-V) → uploaded, inserted at cursor.
//   - Toolbar "Insert image" button → file picker → uploaded, inserted at cursor.
// Each upload first inserts a placeholder MJML comment so authors see
// where the image will land; on success the placeholder is replaced with
// `<mj-image src="…" alt="" />`. On failure the placeholder turns into an
// inline error comment that the author can delete.
//
// Usage:
//   <textarea data-controller="code-editor"
//             data-code-editor-language-value="xml"
//             data-code-editor-min-height-value="500px"
//             data-code-editor-upload-url-value="/account/email_templates/123/assets"
//             ...></textarea>
//
// The element being decorated MUST be a <textarea> (Stimulus controllers
// here attach directly to the element so the form picks up the form field
// name + id automatically). The CodeMirror view is inserted as a sibling
// right after the textarea, wrapped in a container that hosts the toolbar.
export default class extends Controller {
  static values = {
    language: { type: String, default: "xml" },
    minHeight: { type: String, default: "400px" },
    uploadUrl: { type: String, default: "" }
  }

  connect() {
    if (this.view) return  // guard against Turbo double-connect

    const textarea = this.element
    textarea.style.display = "none"

    // Build the language extension. Today only xml/mjml is wired; future
    // languages plug in here.
    const langExtension = this.languageValue === "xml" ? xml() : []

    const updateListener = EditorView.updateListener.of((update) => {
      if (update.docChanged) {
        textarea.value = update.state.doc.toString()
      }
    })

    // Sizing: let the editor fill available width, and respect minHeight.
    const sizingTheme = EditorView.theme({
      "&": {
        fontSize: "13px",
        border: "1px solid rgb(209 213 219)",
        borderRadius: "0.375rem",
        backgroundColor: "white"
      },
      ".cm-scroller": {
        fontFamily: "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace",
        minHeight: this.minHeightValue
      },
      ".cm-content": {
        padding: "10px 0"
      },
      ".cm-gutters": {
        backgroundColor: "rgb(249 250 251)",
        borderRight: "1px solid rgb(229 231 235)",
        color: "rgb(156 163 175)"
      },
      "&.cm-focused": {
        outline: "2px solid rgb(99 102 241)",
        outlineOffset: "0"
      }
    })

    // Drag-and-drop image handler (CodeMirror DOM event).
    const dropHandler = EditorView.domEventHandlers({
      dragover: (event) => {
        if (this._eventHasFiles(event)) {
          event.preventDefault()
          event.dataTransfer.dropEffect = "copy"
          return true
        }
        return false
      },
      drop: (event, view) => {
        const files = this._imageFilesFromEvent(event)
        if (!files.length) return false
        event.preventDefault()
        const pos = view.posAtCoords({ x: event.clientX, y: event.clientY }) ?? view.state.selection.main.head
        files.forEach((file, idx) => this._handleImageFile(file, { insertPos: pos + idx }))
        return true
      },
      paste: (event, view) => {
        const files = this._imageFilesFromClipboard(event)
        if (!files.length) return false
        event.preventDefault()
        files.forEach((file) => this._handleImageFile(file))
        return true
      }
    })

    this.view = new EditorView({
      state: EditorState.create({
        doc: textarea.value,
        extensions: [
          basicSetup,
          langExtension,
          updateListener,
          sizingTheme,
          dropHandler
        ]
      })
    })

    // Build the wrapper: optional toolbar + the editor itself, inserted
    // right after the (hidden) textarea.
    this.wrapper = document.createElement("div")
    this.wrapper.className = "code-editor-wrapper"
    this.wrapper.style.cssText = "display:flex;flex-direction:column;gap:6px;"

    if (this.uploadUrlValue) {
      this.wrapper.appendChild(this._buildToolbar())
    }
    this.wrapper.appendChild(this.view.dom)

    textarea.insertAdjacentElement("afterend", this.wrapper)
  }

  disconnect() {
    if (this.view) {
      this.view.destroy()
      this.view = null
    }
    if (this.wrapper && this.wrapper.parentNode) {
      this.wrapper.parentNode.removeChild(this.wrapper)
      this.wrapper = null
    }
    if (this.element) {
      this.element.style.display = ""
    }
  }

  // ---- Toolbar ---------------------------------------------------------

  _buildToolbar() {
    const bar = document.createElement("div")
    bar.className = "code-editor-toolbar"
    bar.style.cssText = "display:flex;align-items:center;gap:8px;"

    const button = document.createElement("button")
    button.type = "button"
    button.textContent = "Insert image"
    button.className = "code-editor-toolbar__button"
    // Inline styles keep this self-contained — matches the DESIGN.md
    // hairline-bordered, mono-caps eyebrow aesthetic without depending on
    // a shared CSS class that doesn't exist yet.
    button.style.cssText = [
      "font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace",
      "font-size:11px",
      "letter-spacing:0.06em",
      "text-transform:uppercase",
      "color:rgb(82 82 91)",
      "background:white",
      "border:1px solid rgb(228 228 231)",
      "border-radius:6px",
      "padding:6px 10px",
      "cursor:pointer"
    ].join(";")
    button.addEventListener("click", () => this._openFilePicker())

    const hint = document.createElement("span")
    hint.textContent = "or drop / paste an image into the editor"
    hint.style.cssText = "font-size:12px;color:rgb(113 113 122);"

    bar.appendChild(button)
    bar.appendChild(hint)

    // Hidden file input lives on the wrapper so the picker can be invoked
    // from the toolbar without polluting the form DOM with a visible input.
    this.fileInput = document.createElement("input")
    this.fileInput.type = "file"
    this.fileInput.accept = "image/*"
    this.fileInput.multiple = true
    this.fileInput.style.display = "none"
    this.fileInput.addEventListener("change", (event) => {
      const files = Array.from(event.target.files || []).filter((f) => f.type.startsWith("image/"))
      files.forEach((file) => this._handleImageFile(file))
      // Reset so picking the same file twice in a row re-triggers change.
      event.target.value = ""
    })
    bar.appendChild(this.fileInput)

    return bar
  }

  _openFilePicker() {
    if (this.fileInput) this.fileInput.click()
  }

  // ---- File detection --------------------------------------------------

  _eventHasFiles(event) {
    const dt = event.dataTransfer
    if (!dt) return false
    if (dt.types && Array.from(dt.types).includes("Files")) return true
    return !!(dt.files && dt.files.length)
  }

  _imageFilesFromEvent(event) {
    const dt = event.dataTransfer
    if (!dt || !dt.files) return []
    return Array.from(dt.files).filter((f) => f.type.startsWith("image/"))
  }

  _imageFilesFromClipboard(event) {
    const items = event.clipboardData && event.clipboardData.items
    if (!items) return []
    const files = []
    for (const item of items) {
      if (item.kind === "file" && item.type.startsWith("image/")) {
        const file = item.getAsFile()
        if (file) files.push(file)
      }
    }
    return files
  }

  // ---- Upload + insert -------------------------------------------------

  // Insert a placeholder at the cursor (or at `insertPos` for drops),
  // POST the file, then replace the placeholder with the final
  // `<mj-image …/>` tag on success — or an inline error comment on
  // failure that the author can delete.
  async _handleImageFile(file, { insertPos } = {}) {
    if (!this.uploadUrlValue) return
    if (!file.type.startsWith("image/")) return

    const placeholderId = `uploading-${Date.now()}-${Math.floor(Math.random() * 1e6)}`
    const placeholder = `<!-- ${placeholderId}: uploading ${file.name}… -->`

    const pos = (typeof insertPos === "number")
      ? insertPos
      : this.view.state.selection.main.head
    const selection = this.view.state.selection.main
    const hasSelection = !selection.empty

    // For drag-drop we always insert at the drop position. For paste / button
    // we replace the current selection if there is one (so the user can
    // "select alt text → paste image" if they want).
    if (hasSelection && typeof insertPos !== "number") {
      this.view.dispatch({
        changes: { from: selection.from, to: selection.to, insert: placeholder },
        selection: { anchor: selection.from + placeholder.length }
      })
    } else {
      this.view.dispatch({
        changes: { from: pos, to: pos, insert: placeholder },
        selection: { anchor: pos + placeholder.length }
      })
    }

    try {
      const url = await this._uploadFile(file)
      const tag = `<mj-image src="${url}" alt="" />`
      this._replaceMarker(placeholder, tag)
    } catch (err) {
      const message = (err && err.message) ? err.message : "Upload failed."
      const errorTag = `<!-- image upload failed: ${this._escapeComment(message)} -->`
      this._replaceMarker(placeholder, errorTag)
    }
  }

  // Sweep the current document for the placeholder text and replace it
  // in-place. We don't rely on positions because the document may have
  // shifted (other uploads, typing) between insert and resolve.
  _replaceMarker(marker, replacement) {
    if (!this.view) return
    const doc = this.view.state.doc.toString()
    const idx = doc.indexOf(marker)
    if (idx === -1) return
    this.view.dispatch({
      changes: { from: idx, to: idx + marker.length, insert: replacement }
    })
  }

  _escapeComment(s) {
    return String(s).replace(/--/g, "—")
  }

  async _uploadFile(file) {
    const csrf = document.querySelector('meta[name=csrf-token]')?.content || ""
    const body = new FormData()
    body.append("file", file)

    const res = await fetch(this.uploadUrlValue, {
      method: "POST",
      headers: { "X-CSRF-Token": csrf, "Accept": "application/json" },
      body,
      credentials: "same-origin"
    })

    if (!res.ok) {
      const payload = await res.json().catch(() => ({}))
      throw new Error(payload.error || `Upload failed (${res.status})`)
    }

    const data = await res.json()
    if (!data.url) throw new Error("Upload succeeded but server didn't return a URL.")
    return data.url
  }
}
