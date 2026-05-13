import { Controller } from "@hotwired/stimulus"

// "Insert variable" picker for the campaign edit page. Click the trigger
// button → fetches /account/teams/:team_id/variables.json once → renders a
// filterable list of variables (built-in + custom). Click a row to splice
// `{{name}}` into the markdown editor at the current cursor position.
//
// The associated markdown editor controller is discovered via Stimulus'
// `getControllerForElementAndIdentifier`, looked up either via a
// `data-variable-picker-editor-selector-value` CSS selector or by walking
// up to the form and finding the first `[data-controller~="markdown-editor"]`
// inside it.
export default class extends Controller {
  static targets = ["button", "panel", "search", "list"]
  static values = {
    url: String,
    editorSelector: { type: String, default: "" }
  }

  connect() {
    this.loaded = false
    this.variables = []
    this._onDocClick = this._onDocClick.bind(this)
    document.addEventListener("click", this._onDocClick)
  }

  disconnect() {
    document.removeEventListener("click", this._onDocClick)
  }

  toggle(e) {
    if (e) e.preventDefault()
    if (this._isOpen()) {
      this._close()
    } else {
      this._open()
    }
  }

  async _open() {
    this.panelTarget.classList.remove("hidden")
    if (!this.loaded) {
      await this._fetchVariables()
      this.loaded = true
    }
    this._render()
    if (this.hasSearchTarget) {
      this.searchTarget.value = ""
      // Defer focus so the open animation / click handler don't steal it back.
      setTimeout(() => this.searchTarget.focus(), 0)
    }
  }

  _close() {
    this.panelTarget.classList.add("hidden")
  }

  _isOpen() {
    return !this.panelTarget.classList.contains("hidden")
  }

  _onDocClick(e) {
    if (!this.element.contains(e.target)) this._close()
  }

  async _fetchVariables() {
    try {
      const resp = await fetch(this.urlValue, {
        headers: { "Accept": "application/json" },
        credentials: "same-origin"
      })
      if (!resp.ok) {
        this.variables = []
        return
      }
      const data = await resp.json()
      this.variables = Array.isArray(data) ? data : []
    } catch (err) {
      console.warn("[variable-picker] fetch failed", err)
      this.variables = []
    }
  }

  filter() {
    this._render()
  }

  _render() {
    const list = this.hasListTarget ? this.listTarget : this.panelTarget.querySelector("[data-list]")
    if (!list) return
    const q = (this.hasSearchTarget ? this.searchTarget.value : "").trim().toLowerCase()
    const visible = q.length === 0
      ? this.variables
      : this.variables.filter(v => v.name.toLowerCase().includes(q))

    list.innerHTML = ""
    if (visible.length === 0) {
      const empty = document.createElement("li")
      empty.className = "px-3 py-2 text-sm text-gray-500"
      empty.textContent = this.variables.length === 0 ? "No variables available yet." : "No matches."
      list.appendChild(empty)
      return
    }

    visible.forEach((v) => {
      const li = document.createElement("li")
      li.className = "px-3 py-2 cursor-pointer flex items-center justify-between gap-3 text-sm hover:bg-base-50 dark:hover:bg-base-700"
      const left = document.createElement("span")
      left.className = "font-mono text-xs text-base-900 dark:text-base-100"
      left.textContent = `{{${v.name}}}`
      const right = document.createElement("span")
      right.className = "text-xs text-gray-500 truncate ml-2"
      const sampleText = v.sample !== null && v.sample !== undefined && String(v.sample).length > 0
        ? String(v.sample)
        : (v.category === "built-in" ? "built-in" : "")
      right.textContent = sampleText
      li.appendChild(left)
      li.appendChild(right)
      li.addEventListener("mousedown", (e) => {
        // mousedown so we beat the outside-click + blur sequence.
        e.preventDefault()
        this._insert(v)
      })
      list.appendChild(li)
    })
  }

  _insert(variable) {
    const editorController = this._findEditorController()
    const token = `{{${variable.name}}}`
    if (editorController && typeof editorController.insertAtCursor === "function") {
      editorController.insertAtCursor(token)
    } else {
      // Fallback: append the token to the underlying textarea so the author
      // still gets a hint of what to paste, then surface a console warning.
      const ta = this._findFallbackTextarea()
      if (ta) {
        ta.value = (ta.value || "") + token
        ta.dispatchEvent(new Event("input", { bubbles: true }))
      }
      console.warn("[variable-picker] markdown-editor controller not found; appended to textarea instead")
    }
    this._close()
  }

  _findEditorController() {
    if (!window.Stimulus) return null
    let editorEl = null
    if (this.editorSelectorValue) {
      editorEl = document.querySelector(this.editorSelectorValue)
    }
    if (!editorEl) {
      const scope = this.element.closest("form") || document
      editorEl = scope.querySelector('[data-controller~="markdown-editor"]')
    }
    if (!editorEl) return null
    return window.Stimulus.getControllerForElementAndIdentifier(editorEl, "markdown-editor")
  }

  _findFallbackTextarea() {
    const scope = this.element.closest("form") || document
    return scope.querySelector('textarea[name$="[body_markdown]"]') || scope.querySelector('textarea')
  }
}
