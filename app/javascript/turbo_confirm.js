// Beautiful Turbo confirm dialogs.
//
// Replaces window.confirm() (the ugly browser-native dialog) with our own
// styled <dialog id="turbo-confirm"> element. Every link / button with
// `data-turbo-confirm="…"` flows through this on click. The destructive
// styling kicks in automatically when the triggering element looks like a
// delete (data-turbo-method="delete" or method=delete form, OR the
// rendered text matches /delete|remove|destroy/i).
//
// Pattern from https://boringrails.com/articles/data-turbo-confirm-beautiful-dialog/

import { Turbo } from "@hotwired/turbo-rails"

const DIALOG_ID = "turbo-confirm"
const DESTRUCTIVE_TEXT = /\b(delete|destroy|remove|unsubscribe|purge|cancel\s+account|sign\s+out|logout)\b/i

function isDestructive(element) {
  if (!element) return false
  const m = element.dataset?.turboMethod || element.getAttribute?.("method") || ""
  if (m.toLowerCase() === "delete") return true
  // Forms with method=post but a hidden _method=delete (Rails button_to)
  const hidden = element.querySelector?.('input[name="_method"][value="delete"]')
  if (hidden) return true
  const label = (element.innerText || element.value || "").trim()
  return DESTRUCTIVE_TEXT.test(label)
}

Turbo.setConfirmMethod((message, element) => {
  const dialog = document.getElementById(DIALOG_ID)
  if (!dialog) {
    // Fallback to native confirm if the dialog isn't on the page.
    return Promise.resolve(window.confirm(message))
  }

  const destructive = isDestructive(element)
  dialog.classList.toggle("is-destructive", destructive)
  dialog.querySelector("[data-eyebrow]").textContent = destructive ? "Confirm" : "Confirm"
  dialog.querySelector("[data-message]").textContent = message
  const confirmBtn = dialog.querySelector("[data-confirm]")
  confirmBtn.textContent = destructive ? "Yes, delete" : "Yes, continue"

  dialog.returnValue = ""
  dialog.showModal()
  // Move focus to Cancel so a stray Enter doesn't auto-confirm.
  dialog.querySelector("[data-cancel]")?.focus()

  return new Promise((resolve) => {
    dialog.addEventListener("close", () => {
      resolve(dialog.returnValue === "confirm")
    }, { once: true })
  })
})

// Close on backdrop click.
document.addEventListener("click", (event) => {
  const dialog = document.getElementById(DIALOG_ID)
  if (!dialog || !dialog.open) return
  // event.target is the dialog itself when the user clicks the backdrop
  // (because <form method=dialog> children stop propagation).
  if (event.target === dialog) {
    dialog.returnValue = "cancel"
    dialog.close()
  }
})
