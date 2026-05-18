import { Controller } from "@hotwired/stimulus"

// Global Cmd+K (Ctrl+K on Windows/Linux) command palette. Listens for the
// keyboard shortcut anywhere in the signed-in app, opens a <dialog>, debounces
// JSON fetches to the team-scoped search endpoint, and renders grouped
// results with full keyboard navigation.
//
// Wired up in app/views/account/shared/_search_palette.html.erb which is
// included once in the account layout.
export default class extends Controller {
  static targets = ["input", "results", "empty", "panel"]
  static values = { url: String }

  connect() {
    this.debounceTimer = null
    this.fetchController = null      // AbortController for the in-flight fetch
    this.flatItems = []              // flat list of selectable items (for arrow nav)
    this.activeIndex = -1
    this.lastQuery = null            // dedupe duplicate fetches

    this._boundGlobalKey = this._onGlobalKey.bind(this)
    this._boundOpen = () => this.open()
    document.addEventListener("keydown", this._boundGlobalKey)
    document.addEventListener("search-palette:open", this._boundOpen)

    // Swap the keycap glyph based on platform so non-mac users see "Ctrl K"
    // instead of an unfamiliar ⌘. Cheap one-shot at boot; no observers.
    const isMac = /Mac|iPhone|iPad/.test(navigator.platform || "") || /Mac/.test(navigator.userAgent || "")
    document.querySelectorAll("[data-search-palette-keycap]").forEach((el) => {
      el.textContent = isMac ? "⌘K" : "Ctrl K"
    })

    // Native <dialog> fires `cancel` on Esc; reuse our close so we also
    // reset state. Without this, Esc closes the dialog but the next open
    // shows stale results.
    this.element.addEventListener("cancel", (e) => {
      e.preventDefault()
      this.close()
    })

    // Clicking the backdrop closes the dialog. We stop propagation inside
    // the panel (via data-action in the markup) so only true backdrop
    // clicks reach here.
    this.element.addEventListener("click", (e) => {
      if (e.target === this.element) this.close()
    })
  }

  disconnect() {
    document.removeEventListener("keydown", this._boundGlobalKey)
    document.removeEventListener("search-palette:open", this._boundOpen)
    if (this.debounceTimer) clearTimeout(this.debounceTimer)
    if (this.fetchController) this.fetchController.abort()
  }

  // Action hook: a click handler on the panel calls this so clicks inside
  // the card don't bubble up and trigger the backdrop close.
  stopPropagation(e) {
    e.stopPropagation()
  }

  // Listens for Cmd+K / Ctrl+K anywhere. Also forwards `/` as a shortcut
  // when the user isn't typing in a form field (industry-standard).
  _onGlobalKey(e) {
    const isCmdK = (e.metaKey || e.ctrlKey) && (e.key === "k" || e.key === "K")
    if (isCmdK) {
      e.preventDefault()
      this.toggle()
    }
  }

  open() {
    if (this.element.open) return
    // Reset state so reopens don't show stale results from the prior query.
    this.inputTarget.value = ""
    this.lastQuery = null
    this.flatItems = []
    this.activeIndex = -1
    this._showEmpty("Loading recent items…")
    this.element.showModal()
    // Focus the input on the next frame so the dialog has finished its
    // open transition and the focus actually lands in the field.
    requestAnimationFrame(() => this.inputTarget.focus())
    // Pre-fetch recent items so the palette is useful with zero typing.
    this._fetch("")
  }

  close() {
    if (!this.element.open) return
    if (this.fetchController) this.fetchController.abort()
    if (this.debounceTimer) clearTimeout(this.debounceTimer)
    this.element.close()
  }

  toggle() {
    if (this.element.open) this.close()
    else this.open()
  }

  onInput() {
    const q = this.inputTarget.value.trim()
    if (this.debounceTimer) clearTimeout(this.debounceTimer)
    // 150ms debounce per spec — fast enough to feel live, slow enough
    // not to spam the API on every keystroke.
    this.debounceTimer = setTimeout(() => this._fetch(q), 150)
  }

  onKeydown(e) {
    if (e.key === "ArrowDown") {
      e.preventDefault()
      this._moveActive(1)
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      this._moveActive(-1)
    } else if (e.key === "Enter") {
      e.preventDefault()
      this._activateSelected()
    } else if (e.key === "Escape") {
      e.preventDefault()
      this.close()
    }
  }

  async _fetch(q) {
    if (q === this.lastQuery) return
    this.lastQuery = q

    if (this.fetchController) this.fetchController.abort()
    this.fetchController = new AbortController()

    const url = `${this.urlValue}.json?q=${encodeURIComponent(q)}`
    try {
      const resp = await fetch(url, {
        headers: { "Accept": "application/json" },
        credentials: "same-origin",
        signal: this.fetchController.signal
      })
      if (!resp.ok) {
        this._showEmpty("Search failed. Try again.")
        return
      }
      const data = await resp.json()
      this._render(data.groups || [])
    } catch (err) {
      if (err.name !== "AbortError") {
        console.warn("[search-palette] fetch failed", err)
        this._showEmpty("Search failed. Try again.")
      }
    }
  }

  _render(groups) {
    this.flatItems = []
    this.activeIndex = -1
    const container = this.resultsTarget
    container.innerHTML = ""

    if (!groups.length) {
      const q = this.inputTarget.value.trim()
      this._showEmpty(q.length ? `No results for "${q}".` : "Nothing here yet.")
      return
    }

    groups.forEach((group) => {
      const header = document.createElement("div")
      header.className = "search-palette__group-label"
      header.textContent = group.label
      container.appendChild(header)

      const ul = document.createElement("ul")
      ul.className = "search-palette__group"
      group.items.forEach((item) => {
        const li = document.createElement("li")
        li.className = "search-palette__row"
        li.setAttribute("role", "option")
        li.setAttribute("data-url", item.url)

        const title = document.createElement("span")
        title.className = "search-palette__title"
        title.textContent = item.title || "Untitled"

        const subtitle = document.createElement("span")
        subtitle.className = "search-palette__subtitle"
        subtitle.textContent = item.subtitle || ""

        li.appendChild(title)
        if (item.subtitle) li.appendChild(subtitle)

        const idx = this.flatItems.length
        this.flatItems.push({ el: li, url: item.url })
        li.addEventListener("mouseenter", () => this._setActive(idx))
        li.addEventListener("mousedown", (e) => {
          // mousedown beats blur so we don't lose focus before navigation.
          e.preventDefault()
          this._setActive(idx)
          this._activateSelected()
        })
        ul.appendChild(li)
      })
      container.appendChild(ul)
    })

    if (this.flatItems.length) this._setActive(0)
  }

  _showEmpty(text) {
    this.resultsTarget.innerHTML = ""
    const div = document.createElement("div")
    div.className = "search-palette__empty"
    const span = document.createElement("span")
    span.className = "search-palette__empty-text"
    span.textContent = text
    div.appendChild(span)
    this.resultsTarget.appendChild(div)
    this.flatItems = []
    this.activeIndex = -1
  }

  _setActive(idx) {
    if (idx < 0 || idx >= this.flatItems.length) return
    this.flatItems.forEach((item, i) => {
      item.el.classList.toggle("is-active", i === idx)
      if (i === idx) item.el.setAttribute("aria-selected", "true")
      else item.el.removeAttribute("aria-selected")
    })
    this.activeIndex = idx
    const el = this.flatItems[idx].el
    if (el.scrollIntoView) el.scrollIntoView({ block: "nearest" })
  }

  _moveActive(delta) {
    if (!this.flatItems.length) return
    const next = (this.activeIndex + delta + this.flatItems.length) % this.flatItems.length
    this._setActive(next)
  }

  _activateSelected() {
    if (this.activeIndex < 0 || !this.flatItems[this.activeIndex]) return
    const url = this.flatItems[this.activeIndex].url
    if (!url) return
    this.close()
    // Use Turbo if available so navigations stay in-app; fall back to a
    // standard navigation otherwise. The optional chain covers test
    // environments where Turbo isn't on window.
    if (window.Turbo && typeof window.Turbo.visit === "function") {
      window.Turbo.visit(url)
    } else {
      window.location.href = url
    }
  }
}
