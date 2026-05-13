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

    this.editor = new EasyMDE({
      element: textarea,
      spellChecker: true,
      autosave: { enabled: false },
      forceSync: true,
      status: false,
      minHeight: "360px",
      // We don't have hosted image upload yet — hide the image button to avoid
      // dead UI. Authors who need an image can paste raw markdown ![alt](url).
      hideIcons: ["image", "side-by-side"],
      showIcons: ["code", "table", "horizontal-rule"],
      toolbar: [
        "bold", "italic", "heading", "|",
        "quote", "unordered-list", "ordered-list", "|",
        "link", "code", "table", "horizontal-rule", "|",
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
}
