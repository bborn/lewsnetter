import { Controller } from "@hotwired/stimulus"

// Copy-to-clipboard for the Assets list on the campaign + email template
// edit forms. Click "Copy URL" → reads the URL out of the `source` target
// (a <code> element holding the rails_storage_proxy_url) → writes it to
// the OS clipboard via the async Clipboard API → briefly swaps the
// button label to "Copied!" for visible feedback.
//
// Falls back to a synchronous selection+execCommand path on the rare
// browsers (mostly older mobile WebKit) where `navigator.clipboard` is
// undefined. We deliberately don't pull in a clipboard.js dep — the
// native API has been available everywhere we care about for years.
export default class extends Controller {
  static targets = ["source", "button"]

  copy(event) {
    if (event) event.preventDefault()
    if (!this.hasSourceTarget) return

    const text = (this.sourceTarget.textContent || "").trim()
    if (!text) return

    const onSuccess = () => this._flash("Copied!")
    const onFailure = (err) => {
      console.warn("[clipboard] copy failed", err)
      this._flash("Copy failed", { error: true })
    }

    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(onSuccess, onFailure)
    } else {
      // Legacy fallback. Build a hidden textarea, select its contents,
      // run document.execCommand("copy"), then clean up. Works on
      // http:// localhost and ancient browsers.
      try {
        const helper = document.createElement("textarea")
        helper.value = text
        helper.setAttribute("readonly", "")
        helper.style.position = "absolute"
        helper.style.left = "-9999px"
        document.body.appendChild(helper)
        helper.select()
        document.execCommand("copy")
        document.body.removeChild(helper)
        onSuccess()
      } catch (err) {
        onFailure(err)
      }
    }
  }

  // Swap the button label briefly, then restore the original. Stored in a
  // closure-bound timeout so successive clicks don't stack restorations
  // — we cancel any pending restore before scheduling the next one.
  _flash(label, { error = false } = {}) {
    if (!this.hasButtonTarget) return
    const btn = this.buttonTarget

    if (this._restoreTimer) {
      clearTimeout(this._restoreTimer)
      this._restoreTimer = null
    }

    if (this._originalLabel === undefined) {
      this._originalLabel = btn.textContent
    }

    btn.textContent = label
    btn.dataset.copyState = error ? "error" : "copied"

    this._restoreTimer = setTimeout(() => {
      btn.textContent = this._originalLabel
      delete btn.dataset.copyState
      this._restoreTimer = null
    }, 1500)
  }
}
