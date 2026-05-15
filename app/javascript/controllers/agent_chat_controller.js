import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// Wires the right-side agent chat panel.
//
// Usage (rendered by _panel.html.erb):
//   <aside data-controller="agent-chat"
//          data-agent-chat-conversation-id-value="<%= conv.id %>">
//     <button data-action="click->agent-chat#toggle">Chat</button>
//     <div data-agent-chat-target="panel" hidden>
//       <div data-agent-chat-target="messages"></div>
//       <form data-action="submit->agent-chat#submit">
//         <textarea data-agent-chat-target="input"></textarea>
//         <button type="submit">Send</button>
//       </form>
//     </div>
//   </aside>
export default class extends Controller {
  static targets = ["messages", "input", "panel"]
  static values = { conversationId: Number }

  connect() {
    if (!this.hasConversationIdValue || !this.conversationIdValue) {
      console.debug("[agent-chat] no conversation id; subscription skipped")
      return
    }
    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      { channel: "AgentChannel", conversation_id: this.conversationIdValue },
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
