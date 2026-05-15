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

  handleEvent(event) {
    if (!this.hasMessagesTarget) return
    const node = document.createElement("div")
    node.className = `agent-chat-msg agent-chat-msg--${event.type}`
    if (event.type === "user_message" || event.type === "assistant_message") {
      node.textContent = event.content
    } else if (event.type === "tool_call") {
      const args = event.arguments ? JSON.stringify(event.arguments) : "{}"
      node.textContent = `→ ${event.tool_name}(${args})`
    } else if (event.type === "tool_result") {
      const r = event.result ? JSON.stringify(event.result).slice(0, 200) : ""
      node.textContent = `← ${event.tool_name}: ${r}`
    } else if (event.type === "error") {
      node.textContent = `error: ${event.message}`
    } else {
      node.textContent = JSON.stringify(event)
    }
    this.messagesTarget.appendChild(node)
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }
}
