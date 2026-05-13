import { Controller } from "@hotwired/stimulus"
import { EditorView, basicSetup } from "codemirror"
import { EditorState } from "@codemirror/state"
import { xml } from "@codemirror/lang-xml"

// Wraps a <textarea> in a CodeMirror 6 editor with XML/MJML syntax
// highlighting, line numbers, bracket matching, and search. The original
// textarea is kept in the DOM but visually hidden — its value is synced on
// every CodeMirror update so form submits capture the current contents.
//
// Usage:
//   <textarea data-controller="code-editor"
//             data-code-editor-language-value="xml"
//             data-code-editor-min-height-value="500px"
//             ...></textarea>
//
// The element being decorated MUST be a <textarea> (Stimulus controllers
// here attach directly to the element so the form picks up the form field
// name + id automatically). The CodeMirror view is inserted as a sibling
// right after the textarea.
export default class extends Controller {
  static values = {
    language: { type: String, default: "xml" },
    minHeight: { type: String, default: "400px" }
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

    this.view = new EditorView({
      state: EditorState.create({
        doc: textarea.value,
        extensions: [
          basicSetup,
          langExtension,
          updateListener,
          sizingTheme
        ]
      })
    })

    textarea.insertAdjacentElement("afterend", this.view.dom)
  }

  disconnect() {
    if (this.view) {
      this.view.destroy()
      this.view = null
    }
    if (this.element) {
      this.element.style.display = ""
    }
  }
}
