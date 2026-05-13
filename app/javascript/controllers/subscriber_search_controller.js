import { Controller } from "@hotwired/stimulus"

// Typeahead for the "Preview as" input on the campaign show page. Wraps a
// plain text input + an empty <ul> and lights it up with debounced JSON
// lookups against /account/teams/:team_id/subscribers/search.json. Keyboard
// (Arrow/Enter/Escape) and mouse navigate / select. Pure Stimulus + fetch;
// no extra deps.
export default class extends Controller {
  static targets = ["input", "results"]
  static values = { teamId: Number }

  connect() {
    this.debounceTimer = null
    this.activeIndex = -1
    this.results = []
    this.controller = null // AbortController for the in-flight fetch
    this._onDocClick = this._onDocClick.bind(this)
    document.addEventListener("click", this._onDocClick)
  }

  disconnect() {
    document.removeEventListener("click", this._onDocClick)
    if (this.debounceTimer) clearTimeout(this.debounceTimer)
    if (this.controller) this.controller.abort()
  }

  // Keep the listener bound in the markup so we don't have to special-case it.
  initialize() {
    this._boundInput = this._onInput.bind(this)
    this._boundKey = this._onKeydown.bind(this)
  }

  inputTargetConnected(el) {
    el.setAttribute("autocomplete", "off")
    el.addEventListener("input", this._boundInput)
    el.addEventListener("keydown", this._boundKey)
    el.addEventListener("focus", () => {
      if (this.results.length > 0) this._open()
    })
  }

  inputTargetDisconnected(el) {
    el.removeEventListener("input", this._boundInput)
    el.removeEventListener("keydown", this._boundKey)
  }

  _onInput() {
    const q = this.inputTarget.value.trim()
    if (this.debounceTimer) clearTimeout(this.debounceTimer)
    if (q.length === 0) {
      this._setResults([])
      this._close()
      return
    }
    this.debounceTimer = setTimeout(() => this._fetch(q), 200)
  }

  _onKeydown(e) {
    if (this._isOpen() && (e.key === "ArrowDown" || e.key === "ArrowUp" || e.key === "Enter" || e.key === "Escape")) {
      if (e.key === "ArrowDown") {
        e.preventDefault()
        this._moveActive(1)
      } else if (e.key === "ArrowUp") {
        e.preventDefault()
        this._moveActive(-1)
      } else if (e.key === "Enter") {
        if (this.activeIndex >= 0 && this.results[this.activeIndex]) {
          e.preventDefault()
          this._select(this.results[this.activeIndex])
        }
      } else if (e.key === "Escape") {
        this._close()
      }
    }
  }

  _onDocClick(e) {
    if (!this.element.contains(e.target)) this._close()
  }

  async _fetch(q) {
    if (this.controller) this.controller.abort()
    this.controller = new AbortController()
    const teamId = this.teamIdValue
    const url = `/account/teams/${teamId}/subscribers/search.json?q=${encodeURIComponent(q)}`
    try {
      const resp = await fetch(url, {
        headers: { "Accept": "application/json" },
        credentials: "same-origin",
        signal: this.controller.signal
      })
      if (!resp.ok) return
      const data = await resp.json()
      this._setResults(Array.isArray(data) ? data : [])
      if (this.results.length > 0) this._open()
      else this._close()
    } catch (err) {
      if (err.name !== "AbortError") {
        // Surface the error in dev consoles but don't break the form — the
        // input still works as a plain text field.
        console.warn("[subscriber-search] fetch failed", err)
      }
    }
  }

  _setResults(rows) {
    this.results = rows
    this.activeIndex = rows.length > 0 ? 0 : -1
    this._render()
  }

  _render() {
    const ul = this.resultsTarget
    ul.innerHTML = ""
    this.results.forEach((row, i) => {
      const li = document.createElement("li")
      li.className = [
        "px-3 py-2 cursor-pointer flex items-center gap-2 text-sm",
        i === this.activeIndex
          ? "bg-primary-50 dark:bg-base-700"
          : "hover:bg-base-50 dark:hover:bg-base-700"
      ].join(" ")
      const dot = document.createElement("span")
      dot.className = [
        "inline-block w-2 h-2 rounded-full flex-shrink-0",
        row.subscribed ? "bg-green-500" : "bg-base-400"
      ].join(" ")
      dot.setAttribute("title", row.subscribed ? "Subscribed" : "Unsubscribed")
      const email = document.createElement("span")
      email.className = "font-medium text-base-900 dark:text-base-100"
      email.textContent = row.email || ""
      const meta = document.createElement("span")
      meta.className = "text-base-500 dark:text-base-400 truncate"
      const metaBits = []
      if (row.name) metaBits.push(row.name)
      if (row.external_id) metaBits.push(row.external_id)
      meta.textContent = metaBits.length ? `· ${metaBits.join(" · ")}` : ""
      li.appendChild(dot)
      li.appendChild(email)
      li.appendChild(meta)
      li.addEventListener("mousedown", (e) => {
        // mousedown (not click) so we beat the input's blur — otherwise the
        // outside-click handler closes the panel before the click lands.
        e.preventDefault()
        this._select(row)
      })
      li.addEventListener("mouseenter", () => {
        this.activeIndex = i
        this._highlight()
      })
      ul.appendChild(li)
    })
  }

  _highlight() {
    const items = this.resultsTarget.querySelectorAll("li")
    items.forEach((el, i) => {
      el.classList.toggle("bg-primary-50", i === this.activeIndex)
      el.classList.toggle("dark:bg-base-700", i === this.activeIndex)
    })
  }

  _moveActive(delta) {
    if (this.results.length === 0) return
    this.activeIndex = (this.activeIndex + delta + this.results.length) % this.results.length
    this._highlight()
    const el = this.resultsTarget.children[this.activeIndex]
    if (el && el.scrollIntoView) el.scrollIntoView({ block: "nearest" })
  }

  _select(row) {
    this.inputTarget.value = row.email
    this._close()
  }

  _open() {
    this.resultsTarget.classList.remove("hidden")
  }

  _close() {
    this.resultsTarget.classList.add("hidden")
  }

  _isOpen() {
    return !this.resultsTarget.classList.contains("hidden")
  }
}
