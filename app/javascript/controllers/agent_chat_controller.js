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

  // Event types from ChatChannel:
  //   message_full    {message_id, role, html}                    — render whole bubble (user msg, errors, no-LLM fallback)
  //   message_start   {message_id, role}                          — open a streaming bubble for chunks
  //   chunk           {message_id, content_delta}                 — append text to the streaming bubble
  //   message_end     {message_id, html}                          — replace bubble with final markdown-rendered HTML
  //   tool_call       {tool_call_id, name, arguments}             — "→ Calling foo({…})"
  //   tool_result     {result_excerpt}                            — "← result"
  handleEvent(event) {
    if (!this.hasMessagesTarget) return

    switch (event.type) {
      case "message_full":
        this.appendHtml(event.html)
        break
      case "message_start":
        this.openStreamingBubble(event.message_id)
        break
      case "chunk":
        this.appendChunk(event.message_id, event.content_delta)
        break
      case "message_end":
        this.finalizeBubble(event.message_id, event.html)
        break
      case "tool_call":
        this.appendHtml(this.toolCallHtml(event.name, event.arguments))
        break
      case "tool_result":
        this.appendHtml(this.toolResultHtml(event.result_excerpt))
        break
      case "error":
        this.appendHtml(event.html || `<div class="text-rose-700 text-sm">error</div>`)
        break
      default:
        // Unknown event — render as a small debug line so we don't silently
        // drop something the server is sending.
        this.appendHtml(`<div class="text-xs text-zinc-400 px-2">[${event.type}]</div>`)
    }
    this.scrollToBottom()
  }

  appendHtml(html) {
    const wrapper = document.createElement("div")
    wrapper.innerHTML = html
    this.messagesTarget.appendChild(wrapper)
  }

  // Stream tracking: only one bubble is "currently streaming" at a time.
  // The server's message_id might shift between message_start and message_end
  // (because the persisted assistant message gets its id assigned after the
  // streaming completes), so we track by a single reference, not by id.
  openStreamingBubble() {
    if (this.suppressStreaming) return
    if (this.streamingBubble) return
    const wrapper = document.createElement("div")
    wrapper.className = "flex justify-start"
    wrapper.dataset.streaming = "true"
    wrapper.innerHTML = `<div data-stream-content class="bg-white border border-zinc-200 text-zinc-900 rounded-lg px-4 py-2 max-w-[85%] text-sm whitespace-pre-wrap"></div>`
    this.messagesTarget.appendChild(wrapper)
    this.streamingBubble = wrapper
    this.streamingContent = ""
  }

  appendChunk(_messageId, delta) {
    if (this.suppressStreaming) return
    if (!this.streamingBubble) this.openStreamingBubble()
    if (!this.streamingBubble) return
    this.streamingContent = (this.streamingContent || "") + (delta || "")
    const target = this.streamingBubble.querySelector("[data-stream-content]")
    if (target) target.textContent = this.streamingContent
  }

  finalizeBubble(_messageId, html) {
    // Cable broadcast ordering isn't strictly FIFO — by the time message_end
    // arrives the streaming bubble may not exist yet (chunks pending) or may
    // already exist. Strategy: append the final markdown-rendered HTML, then
    // sweep any orphan streaming bubble. Net result is one bubble showing
    // the formatted final reply.
    if (html) this.appendHtml(html)
    // Drop any streaming-bubble references AND any DOM nodes still flagged
    // as streaming (handles the case where chunks arrive after message_end).
    this.streamingBubble = null
    this.streamingContent = ""
    this.suppressStreaming = true
    this.messagesTarget.querySelectorAll('[data-streaming="true"]').forEach(n => n.remove())
    // Clear the suppression after a short window — long enough to cover
    // any stragglers from the just-finished turn but short enough that the
    // next user turn isn't blocked.
    if (this.suppressTimer) clearTimeout(this.suppressTimer)
    this.suppressTimer = setTimeout(() => { this.suppressStreaming = false }, 1500)
  }

  // Pretty tool call line. Argument hash gets compact JSON; long lists truncated.
  toolCallHtml(name, args) {
    const argsStr = (args && Object.keys(args).length) ? this.escapeHtml(JSON.stringify(args)) : ""
    return `<div class="flex items-center gap-2 text-xs text-zinc-500 font-mono px-2 py-1">
      <span class="text-orange-500">→</span>
      <span class="text-zinc-700">${this.escapeHtml(name)}</span><span>(${argsStr})</span>
    </div>`
  }

  toolResultHtml(excerpt) {
    return `<div class="flex items-start gap-2 text-xs text-zinc-500 font-mono px-2 py-1">
      <span class="text-emerald-500">←</span>
      <span class="break-all">${this.escapeHtml(excerpt || "")}</span>
    </div>`
  }

  escapeHtml(s) {
    const div = document.createElement("div")
    div.textContent = String(s)
    return div.innerHTML
  }

  scrollToBottom() {
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }
}
