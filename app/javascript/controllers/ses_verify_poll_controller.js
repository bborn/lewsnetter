import { Controller } from "@hotwired/stimulus"

// Polls the SES wizard's sender_status endpoint every 4 seconds while the
// user is on the "verify sender" step, waiting for them to click the
// AWS-sent verification link. As soon as the server reports the sender
// as verified, reload the page so the wizard advances to the test step.
//
// Backs off after 5 minutes of polling (probably the user closed the tab
// or hit a snag) — they can refresh to resume.
export default class extends Controller {
  static targets = ["spinner", "status"]
  static values = { url: String, reloadUrl: String }

  connect() {
    this._tries = 0
    this._poll()
    this._timer = setInterval(() => this._poll(), 4000)
  }

  disconnect() {
    clearInterval(this._timer)
  }

  async _poll() {
    this._tries++
    if (this._tries > 75) {  // ~5 minutes
      this._stop("Waiting timed out — refresh the page once you've clicked the link.")
      return
    }
    try {
      const res = await fetch(this.urlValue, {headers: {Accept: "application/json"}})
      if (!res.ok) return
      const data = await res.json()
      if (data.state === "verified") {
        this.statusTarget.textContent = "Verified — advancing to the next step…"
        clearInterval(this._timer)
        setTimeout(() => { window.location.href = this.reloadUrlValue }, 500)
      }
    } catch (e) {
      // Network blip — silently retry next tick.
    }
  }

  _stop(message) {
    clearInterval(this._timer)
    if (this.hasSpinnerTarget) this.spinnerTarget.classList.add("hidden")
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }
}
