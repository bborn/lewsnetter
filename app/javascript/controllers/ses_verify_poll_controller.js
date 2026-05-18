import { Controller } from "@hotwired/stimulus"

// Polls a status endpoint every 4 seconds while the user is on a "wait
// for SES" wizard step. Used by the domain DKIM-verify step today; the
// success state is configurable via `success-state-value` so the same
// controller works for any future poll-then-advance flow.
//
// As soon as the server reports state === successStateValue, we replace
// the spinner with a confirmation message and reload the wizard so it
// re-computes its step.
//
// Backs off after 5 minutes of polling (the user probably closed the tab
// or hit a DNS-propagation snag) — they can refresh to resume.
export default class extends Controller {
  static targets = ["spinner", "status"]
  static values = {
    url: String,
    reloadUrl: String,
    successState: { type: String, default: "verified" }
  }

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
      this._stop("Still waiting — refresh the page once your DNS has propagated.")
      return
    }
    try {
      const res = await fetch(this.urlValue, {headers: {Accept: "application/json"}})
      if (!res.ok) return
      const data = await res.json()
      if (data.state === this.successStateValue) {
        if (this.hasStatusTarget) this.statusTarget.textContent = "Verified — advancing to the next step…"
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
