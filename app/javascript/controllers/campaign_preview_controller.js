import { Controller } from "@hotwired/stimulus"

// Live, no-save preview of the campaign body. Listens for changes on the
// markdown editor + the subject/preheader/template fields, POSTs the current
// in-memory form values to the `preview_frame` endpoint, and swaps the
// returned HTML into the iframe via `srcdoc` (no extra navigation).
//
// Usage (root element wraps the iframe + the listenable inputs):
//   <div data-controller="campaign-preview"
//        data-campaign-preview-url-value="/account/campaigns/:id/preview_frame"
//        data-campaign-preview-csrf-value="<%= form_authenticity_token %>"
//        data-action="markdown-editor:change@window->campaign-preview#schedule
//                     ai-drafter:applied@window->campaign-preview#schedule
//                     input->campaign-preview#scheduleFromInput
//                     change->campaign-preview#scheduleFromInput">
//     <iframe data-campaign-preview-target="iframe" ...></iframe>
//   </div>
//
// The manual "Refresh" button (kept for when authors want to force a sync)
// calls `refresh` directly.
export default class extends Controller {
  static targets = ["iframe", "status"]
  static values = {
    url: String,
    csrf: String,
    debounceMs: { type: Number, default: 500 },
    // Watched form field selectors that contribute to a preview render.
    bodySelector: { type: String, default: 'textarea[name="campaign[body_markdown]"]' },
    mjmlSelector: { type: String, default: 'textarea[name="campaign[body_mjml]"]' },
    subjectSelector: { type: String, default: 'input[name="campaign[subject]"]' },
    preheaderSelector: { type: String, default: 'input[name="campaign[preheader]"]' },
    templateSelector: { type: String, default: 'select[name="campaign[email_template_id]"]' }
  }

  connect() {
    this._timer = null
    // Run one initial fetch so the preview reflects unsaved local edits made
    // before the controller connected (e.g. a Turbo navigation revisit).
    // Skip if we have no URL configured.
    if (this.hasUrlValue && this.urlValue) {
      this.schedule()
    }
  }

  disconnect() {
    if (this._timer) clearTimeout(this._timer)
    this._timer = null
  }

  // Debounced refresh — every keystroke calls this; only the last call wins.
  schedule() {
    if (!this.hasUrlValue || !this.urlValue) return
    if (this._timer) clearTimeout(this._timer)
    this._timer = setTimeout(() => this.refresh(), this.debounceMsValue)
  }

  // Lighter wrapper for native input/change events so we can still call
  // schedule from element actions without DOM-event leakage.
  scheduleFromInput(_event) {
    this.schedule()
  }

  // Forced (immediate) refresh — bypasses debounce. Used by the manual
  // "Refresh" button.
  async refresh(event) {
    if (event && event.preventDefault) event.preventDefault()
    if (!this.hasUrlValue || !this.urlValue) return
    if (!this.hasIframeTarget) return

    const payload = this.collectPayload()
    this.setStatus("Updating preview…")

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Accept": "text/html",
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfValue,
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin",
        body: JSON.stringify(payload)
      })

      if (!response.ok) {
        this.setStatus(`Preview failed (HTTP ${response.status})`, true)
        return
      }

      const html = await response.text()
      // srcdoc gives us isolation + same-origin (so JS in the email can't
      // touch the parent page) without round-tripping a URL.
      this.iframeTarget.srcdoc = html
      this.setStatus("")
    } catch (e) {
      this.setStatus(`Preview failed: ${e.message}`, true)
    }
  }

  collectPayload() {
    const get = (sel) => {
      const el = sel ? document.querySelector(sel) : null
      return el ? el.value : ""
    }
    return {
      body_markdown: get(this.bodySelectorValue),
      body_mjml: get(this.mjmlSelectorValue),
      subject: get(this.subjectSelectorValue),
      preheader: get(this.preheaderSelectorValue),
      email_template_id: get(this.templateSelectorValue)
    }
  }

  setStatus(text, isError) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text
    this.statusTarget.classList.toggle("text-red-500", !!isError)
  }
}
