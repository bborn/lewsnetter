import { Controller } from "@hotwired/stimulus"

// Refreshes the campaign preview iframe when the user clicks "Refresh preview".
// Adds a cache-busting query param so the browser doesn't serve a stale render
// from disk, and toggles the button label briefly to confirm the action fired.
//
// Usage:
//   <button data-controller="campaign-preview"
//           data-action="click->campaign-preview#refresh"
//           data-campaign-preview-src-value="/account/campaigns/123/preview_frame">
//     Refresh preview
//   </button>
//
// The iframe must have id="campaign_preview_frame".
export default class extends Controller {
  static values = { src: String }

  refresh(event) {
    event.preventDefault()
    const iframe = document.getElementById("campaign_preview_frame")
    if (!iframe) return

    const separator = this.srcValue.includes("?") ? "&" : "?"
    iframe.src = `${this.srcValue}${separator}t=${Date.now()}`

    const button = this.element
    const originalLabel = button.textContent
    button.textContent = "Refreshing…"
    button.disabled = true
    setTimeout(() => {
      button.textContent = originalLabel
      button.disabled = false
    }, 600)
  }
}
