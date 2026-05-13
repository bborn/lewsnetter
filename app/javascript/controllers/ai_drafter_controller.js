import { Controller } from "@hotwired/stimulus"

// Wires the "Draft with AI" panel on the campaign edit page.
//
// When the user clicks the draft button we POST the brief to the campaign
// drafts endpoint as JSON, then on response write the returned markdown body
// straight into the markdown editor and (optionally) the subject + preheader
// fields. Visible state during the request: a spinner next to the button,
// the button disabled, and any error surfaced inline under the brief box.
//
// Usage:
//   <form data-controller="ai-drafter"
//         data-ai-drafter-url-value="/account/campaigns/:id/draft"
//         data-ai-drafter-csrf-value="<%= form_authenticity_token %>"
//         data-action="submit->ai-drafter#submit">
//     <textarea data-ai-drafter-target="brief"></textarea>
//     <button type="submit" data-ai-drafter-target="submitButton">Draft with AI</button>
//     <span data-ai-drafter-target="spinner" hidden>Asking Claude…</span>
//     <p data-ai-drafter-target="errorMessage" hidden></p>
//   </form>
//
// On success, dispatches `ai-drafter:applied` so other controllers (preview)
// can refresh.
export default class extends Controller {
  static targets = ["brief", "submitButton", "spinner", "errorMessage", "subjectsList"]
  static values = { url: String, csrf: String }

  async submit(event) {
    event.preventDefault()
    if (!this.hasUrlValue || !this.urlValue) {
      this.showError("Draft endpoint is not configured.")
      return
    }

    const brief = this.hasBriefTarget ? this.briefTarget.value.trim() : ""
    if (!brief) {
      this.showError("Add a brief (a few bullets) before drafting.")
      return
    }

    this.clearError()
    this.setBusy(true)

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfValue,
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin",
        body: JSON.stringify({ brief: brief })
      })

      if (!response.ok) {
        let detail = ""
        try { detail = (await response.json()).error } catch (_e) { /* ignore */ }
        this.showError(detail || `Draft request failed (HTTP ${response.status}).`)
        return
      }

      const data = await response.json()
      this.applyDraft(data)
    } catch (e) {
      this.showError(`Draft request failed: ${e.message}`)
    } finally {
      this.setBusy(false)
    }
  }

  applyDraft(data) {
    const markdown = data.body_markdown || data.markdown_body || ""
    const subjects = Array.isArray(data.subjects) ? data.subjects : []
    const preheader = data.preheader || ""
    const stub = !!data.stub

    // Write markdown into the editor controller (which owns the textarea).
    const editorEl = document.querySelector('[data-controller~="markdown-editor"]')
    if (editorEl && markdown) {
      const ctrl = this.application.getControllerForElementAndIdentifier(editorEl, "markdown-editor")
      if (ctrl) {
        ctrl.setValue(markdown)
      } else {
        // Fallback: write directly to the underlying textarea.
        const textarea = editorEl.matches("textarea") ? editorEl : editorEl.querySelector("textarea")
        if (textarea) textarea.value = markdown
      }
    }

    // Subject + preheader are plain inputs.
    if (subjects.length > 0) {
      const subjectField = document.querySelector('input[name="campaign[subject]"]')
      if (subjectField) {
        subjectField.value = subjects[0]
        subjectField.dispatchEvent(new Event("input", { bubbles: true }))
      }
    }
    if (preheader) {
      const preheaderField = document.querySelector('input[name="campaign[preheader]"]')
      if (preheaderField) {
        preheaderField.value = preheader
        preheaderField.dispatchEvent(new Event("input", { bubbles: true }))
      }
    }

    // Surface a brief confirmation in the spinner slot (acts as a tiny toast).
    if (this.hasSpinnerTarget) {
      const original = this.spinnerTarget.dataset.busyLabel || "Asking Claude…"
      this.spinnerTarget.textContent = stub ? "Drafted (stub mode) — review and edit" : "Drafted with AI — review and edit"
      this.spinnerTarget.hidden = false
      setTimeout(() => {
        this.spinnerTarget.hidden = true
        this.spinnerTarget.textContent = original
      }, 3500)
    }

    // Notify the preview controller (and anyone else) that a fresh draft landed.
    this.dispatch("applied", { detail: { markdown, subjects, preheader } })
  }

  setBusy(busy) {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = busy
      if (busy) {
        this.submitButtonTarget.dataset.originalLabel = this.submitButtonTarget.textContent
        this.submitButtonTarget.textContent = "Drafting…"
      } else if (this.submitButtonTarget.dataset.originalLabel) {
        this.submitButtonTarget.textContent = this.submitButtonTarget.dataset.originalLabel
      }
    }
    if (this.hasSpinnerTarget) {
      this.spinnerTarget.hidden = !busy
      if (busy) this.spinnerTarget.textContent = this.spinnerTarget.dataset.busyLabel || "Asking Claude…"
    }
  }

  showError(message) {
    if (!this.hasErrorMessageTarget) return
    this.errorMessageTarget.textContent = message
    this.errorMessageTarget.hidden = false
  }

  clearError() {
    if (!this.hasErrorMessageTarget) return
    this.errorMessageTarget.textContent = ""
    this.errorMessageTarget.hidden = true
  }
}
