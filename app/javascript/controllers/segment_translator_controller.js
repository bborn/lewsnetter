import { Controller } from "@hotwired/stimulus"

// Posts the natural-language input from the segment form to
// /account/teams/:team_id/segments/translate and renders the resulting
// predicate / count / sample subscribers into the inline result panel.
// This is THE AI moment in the product — keep it loud + obvious.
//
// Wired to the wrapping <form> via the `_form.html.erb`. The form's submit
// button triggers `translate`. The controller takes over with fetch + JSON
// so we get an inline UI update without a full page reload (the original
// Turbo Frame approach silently failed to communicate progress).
//
// Markup contract:
//   <form data-controller="segment-translator"
//         data-action="submit->segment-translator#translate"
//         data-segment-translator-url-value="/account/teams/123/segments/translate">
//     <textarea data-segment-translator-target="input"></textarea>
//     <button data-segment-translator-target="submit">Translate to predicate</button>
//   </form>
//   <div data-segment-translator-target="panel" hidden></div>
//   <input type="hidden" name="segment[predicate]" data-segment-translator-target="predicateInput" />
//   <textarea name="segment[natural_language_source]" data-segment-translator-target="nlInput"></textarea>
export default class extends Controller {
  static targets = ["input", "submit", "panel", "predicateInput", "nlInput"]
  static values = { url: String }

  // Bound to form submit. We post the form via fetch and render the result
  // inline instead of letting Turbo navigate.
  async translate(event) {
    event.preventDefault()
    const text = this.inputTarget.value.trim()
    if (!text) {
      this.renderPanel({
        errors: ["Please describe your audience first."],
      })
      return
    }

    this.setLoading(true)

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken(),
        },
        credentials: "same-origin",
        body: JSON.stringify({ natural_language: text }),
      })

      if (!response.ok) {
        this.renderPanel({
          errors: [`Translation failed (HTTP ${response.status}). Please try again.`],
        })
        return
      }

      const data = await response.json()
      this.renderPanel(data)
    } catch (err) {
      this.renderPanel({
        errors: [`Network error: ${err.message || err}`],
      })
    } finally {
      this.setLoading(false)
    }
  }

  // Click handler on the "Use this predicate" button inside the panel.
  // Writes the displayed predicate into the segment form's hidden input
  // and scrolls the page to the form's save button.
  usePredicate(event) {
    event.preventDefault()
    const predicate = event.currentTarget.dataset.predicate || ""
    const description = event.currentTarget.dataset.description || ""
    this.writePredicate(predicate)
    if (this.hasNlInputTarget && description) {
      this.nlInputTarget.value = description
    }
    // Confirmation pulse on the panel.
    const panel = this.panelTarget.querySelector("[data-translation-status]")
    if (panel) {
      panel.textContent = "Predicate copied into the form below — review and save."
      panel.classList.remove("hidden")
    }
    // Scroll the segment form's save button into view.
    const saveBtn = document.querySelector("form.form .buttons .button")
    if (saveBtn) {
      saveBtn.scrollIntoView({ behavior: "smooth", block: "center" })
    }
  }

  // Click handler on the "Edit predicate" button. Replaces the read-only
  // <pre><code> block with an editable textarea so the user can tweak the
  // SQL before saving. Saving the form picks up whatever is in the textarea
  // via writePredicate (called on each input).
  editPredicate(event) {
    event.preventDefault()
    const wrapper = this.panelTarget.querySelector("[data-predicate-wrapper]")
    if (!wrapper) return
    const current = wrapper.dataset.predicate || ""

    wrapper.innerHTML = `
      <textarea data-translation-predicate-edit
                rows="4"
                class="w-full p-2 border rounded-md font-mono text-xs bg-gray-50 dark:bg-sky-950 dark:border-sky-800">${this.escapeHtml(current)}</textarea>
      <p class="text-xs text-gray-500 mt-1">Edits here are saved into the segment when you click Save below.</p>
    `

    const textarea = wrapper.querySelector("textarea")
    this.writePredicate(current)
    textarea.addEventListener("input", (e) => this.writePredicate(e.target.value))
    textarea.focus()
  }

  // -- internals -------------------------------------------------------

  setLoading(loading) {
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = loading
      if (loading) {
        this.submitTarget.dataset.originalLabel = this.submitTarget.textContent
        this.submitTarget.textContent = "Translating…"
      } else if (this.submitTarget.dataset.originalLabel) {
        this.submitTarget.textContent = this.submitTarget.dataset.originalLabel
      }
    }
    if (loading) {
      this.renderPanel({ loading: true })
    }
  }

  renderPanel(result) {
    if (!this.hasPanelTarget) return
    this.panelTarget.hidden = false

    if (result.loading) {
      this.panelTarget.innerHTML = `
        <div class="p-4 my-4 border rounded-md bg-gray-50 dark:bg-sky-950 dark:border-sky-800">
          <p class="text-sm text-gray-600 dark:text-gray-300 flex items-center gap-2">
            <span class="inline-block w-3 h-3 border-2 border-blue-500 border-t-transparent rounded-full animate-spin" aria-hidden="true"></span>
            Translating…
          </p>
        </div>
      `
      return
    }

    const errors = Array.isArray(result.errors) ? result.errors : []
    const errorsHtml = errors.length
      ? `
        <div class="mb-3 p-2 border border-red-300 bg-red-50 text-red-700 rounded-md text-sm dark:bg-red-950 dark:border-red-800 dark:text-red-200">
          <strong class="block mb-1">Couldn't translate that:</strong>
          <ul class="list-disc list-inside">
            ${errors.map((e) => `<li>${this.escapeHtml(e)}</li>`).join("")}
          </ul>
        </div>`
      : ""

    const predicate = result.sql_predicate || ""
    const description = result.human_description || ""
    const count = (typeof result.estimated_count === "number") ? result.estimated_count : 0
    const samples = Array.isArray(result.sample_subscribers) ? result.sample_subscribers : []
    const stub = !!result.stub

    const samplesHtml = samples.length
      ? `
        <table class="w-full text-sm mt-2 border-collapse">
          <thead>
            <tr class="text-left border-b border-gray-200 dark:border-sky-800">
              <th class="py-1 pr-3 font-medium">Name</th>
              <th class="py-1 font-medium">Email</th>
            </tr>
          </thead>
          <tbody>
            ${samples.map((s) => `
              <tr class="border-b border-gray-100 dark:border-sky-900">
                <td class="py-1 pr-3">${this.escapeHtml(s.name || "—")}</td>
                <td class="py-1 font-mono text-xs">${this.escapeHtml(s.email || "")}</td>
              </tr>
            `).join("")}
          </tbody>
        </table>`
      : `<p class="text-sm text-gray-500 mt-2">No subscribers match yet.</p>`

    const predicateHtml = predicate
      ? `
        <div class="mb-3" data-predicate-wrapper data-predicate="${this.escapeAttr(predicate)}">
          <pre class="bg-gray-100 dark:bg-sky-950 dark:border dark:border-sky-800 rounded-md p-2 overflow-x-auto whitespace-pre-wrap break-words"><code class="font-mono text-xs">${this.escapeHtml(predicate)}</code></pre>
        </div>`
      : ""

    const actionsHtml = (predicate && errors.length === 0)
      ? `
        <div class="flex flex-wrap gap-2 mt-3">
          <button type="button"
                  class="button"
                  data-action="click->segment-translator#usePredicate"
                  data-predicate="${this.escapeAttr(predicate)}"
                  data-description="${this.escapeAttr(description)}">
            Use this predicate
          </button>
          <button type="button"
                  class="button-secondary"
                  data-action="click->segment-translator#editPredicate">
            Edit predicate
          </button>
        </div>`
      : ""

    this.panelTarget.innerHTML = `
      <div class="p-4 my-4 border rounded-md bg-gray-50 dark:bg-sky-950 dark:border-sky-800" data-translation-result>
        <h3 class="text-lg font-semibold mb-2">
          AI Segment Preview
          ${stub ? `<span class="text-xs font-normal text-gray-500 ml-2">(stub mode — no LLM call)</span>` : ""}
        </h3>

        ${errorsHtml}

        ${description ? `<p class="text-sm mb-2"><strong>Description:</strong> ${this.escapeHtml(description)}</p>` : ""}

        ${predicate ? `<p class="text-sm mb-1"><strong>Predicate:</strong></p>` : ""}
        ${predicateHtml}

        <p class="text-sm mb-1">
          <strong>Matches ${count} subscribers right now.</strong>
        </p>

        ${samplesHtml}

        ${actionsHtml}

        <p class="hidden text-xs text-green-700 dark:text-green-300 mt-2" data-translation-status></p>

        <p class="text-xs text-gray-500 mt-3">
          Powered by Claude. Predicates are scoped to your subscribers' columns + custom_attributes; never any other table.
        </p>
      </div>
    `

    // Write the freshly-translated predicate into the hidden form input so
    // the user can immediately click the segment form's Save button.
    if (predicate && errors.length === 0) {
      this.writePredicate(predicate)
    }
  }

  writePredicate(value) {
    if (!this.hasPredicateInputTarget) return
    this.predicateInputTarget.value = value
  }

  csrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ""
  }

  escapeHtml(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;")
  }

  escapeAttr(str) {
    return this.escapeHtml(str)
  }
}
