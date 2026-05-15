import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// Wires the agent chat panel (right-side floating + dedicated show page).
// Subscribes to ChatChannel for the given chat_id; submit perform sends a
// `send_message` action; received events render styled bubbles via the
// server-rendered HTML in the payload.
export default class extends Controller {
  static targets = ["messages", "input", "panel"]
  static values = { chatId: Number }

  connect() {
    if (!this.hasChatIdValue || !this.chatIdValue) {
      console.debug("[agent-chat] no chat id; subscription skipped")
      return
    }
    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      { channel: "ChatChannel", chat_id: this.chatIdValue },
      {
        received: (event) => this.handleEvent(event),
        connected: () => console.debug("[agent-chat] connected"),
        rejected: () => console.warn("[agent-chat] subscription rejected — auth?")
      }
    )
  }

  disconnect() {
    this.subscription?.unsubscribe()
    this.consumer?.disconnect()
  }

  toggle() {
    if (this.hasPanelTarget) this.panelTarget.toggleAttribute("hidden")
  }

  submit(e) {
    e.preventDefault()
    const text = this.inputTarget.value.trim()
    if (!text || !this.subscription) return
    this.subscription.perform("send_message", { content: text })
    this.inputTarget.value = ""
  }

  // ⌘+Enter (mac) / Ctrl+Enter (everyone else) submits. Plain Enter inserts
  // a newline so multi-line prompts still work. Wired via:
  //   data-action="keydown->agent-chat#keydown"
  // on the textarea.
  keydown(e) {
    if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
      this.submit(e)
    }
  }

  handleEvent(event) {
    if (!this.hasMessagesTarget) return

    const wrapper = document.createElement("div")
    if (event.html) {
      // Server-rendered partial — already styled to match the page-load
      // render. Just splice it in.
      wrapper.innerHTML = event.html
    } else {
      // Fallback path (no rendered HTML in event payload — e.g. an old
      // server build, or an event the runner doesn't know how to render).
      // Render bare text so at least nothing is silently lost.
      wrapper.className = `text-xs text-zinc-500 px-2`
      wrapper.textContent = `[${event.type}] ${event.content || JSON.stringify(event)}`
    }
    this.messagesTarget.appendChild(wrapper)
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }
}
