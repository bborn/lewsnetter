import { Controller } from "@hotwired/stimulus"

// Visual segment builder — Intercom-style nested rule groups with AND/OR
// combinators. The state is a recursive tree of {type, combinator, rules} for
// groups and {type, field, operator, value} for rules.
//
// Usage:
//   <div data-controller="segments-builder"
//        data-segments-builder-tree-value='<%= raw segment.rules.to_json %>'
//        data-segments-builder-fields-value='<%= raw fields_json %>'
//        data-segments-builder-operators-value='<%= raw operators_json %>'
//        data-segments-builder-preview-url-value="<%= preview_path %>"
//        data-segments-builder-csrf-value="<%= form_authenticity_token %>">
//     <div data-segments-builder-target="tree"></div>
//     <div data-segments-builder-target="preview"></div>
//     <input type="hidden" name="segment[rules]"
//            data-segments-builder-target="hiddenInput">
//   </div>
//
// Tree shape (recursive):
//   {type:"group", combinator:"and"|"or", rules:[Rule|Group]}
//   {type:"rule",  field:"subscribers.email", operator:"contains", value:"@x"}
export default class extends Controller {
  static targets = ["tree", "preview", "hiddenInput"]
  static values = {
    tree: Object,
    fields: Object,
    operators: Object,
    previewUrl: String,
    csrf: String
  }

  connect() {
    // IMPORTANT: Stimulus Object values are JSON in a data attribute, parsed
    // fresh on every read. Mutating nested objects of `this.treeValue`
    // doesn't stick. We keep the working state in `this._tree` (plain JS
    // object, mutable) and only sync to `this.treeValue` on commit (so the
    // attribute stays in sync for inspection / debugging).
    const initial = this.treeValue && Object.keys(this.treeValue).length ? this.treeValue : this.emptyGroup()
    this._tree = JSON.parse(JSON.stringify(initial))  // deep clone so we own the references
    this.render()
    this.schedulePreview()
  }

  // ── tree helpers ─────────────────────────────────────────────────────────

  emptyGroup() {
    return {type: "group", combinator: "and", rules: [this.emptyRule()]}
  }

  emptyRule() {
    const firstGroup = Object.values(this.fieldsValue)[0] || []
    const first = firstGroup[0]
    return {
      type: "rule",
      field: first ? first.key : "subscribers.email",
      operator: this.defaultOperatorFor(first ? first.type : "string"),
      value: ""
    }
  }

  defaultOperatorFor(type) {
    const ops = (this.operatorsValue[type] || ["equals"])
    return ops[0]
  }

  // Walk the tree to the node at `path` (array of indices into rules).
  nodeAt(path) {
    let node = this._tree
    for (const i of path) node = node.rules[i]
    return node
  }

  parentAt(path) {
    if (path.length === 0) return null
    return this.nodeAt(path.slice(0, -1))
  }

  // ── mutations ────────────────────────────────────────────────────────────

  addRule(event) {
    const path = this.parsePath(event.params.path)
    const group = this.nodeAt(path)
    group.rules.push(this.emptyRule())
    this.commit()
  }

  addGroup(event) {
    const path = this.parsePath(event.params.path)
    const group = this.nodeAt(path)
    group.rules.push({type: "group", combinator: "and", rules: [this.emptyRule()]})
    this.commit()
  }

  removeNode(event) {
    const path = this.parsePath(event.params.path)
    if (path.length === 0) return // can't remove root
    const parent = this.parentAt(path)
    const idx = path[path.length - 1]
    parent.rules.splice(idx, 1)
    // If the group is now empty, give it back a starter rule.
    if (parent.rules.length === 0) parent.rules.push(this.emptyRule())
    this.commit()
  }

  toggleCombinator(event) {
    const path = this.parsePath(event.params.path)
    const group = this.nodeAt(path)
    group.combinator = group.combinator === "and" ? "or" : "and"
    this.commit()
  }

  changeField(event) {
    const path = this.parsePath(event.params.path)
    const rule = this.nodeAt(path)
    rule.field = event.target.value
    // Reset operator + value when the field changes (the new field may have
    // a different value type).
    const type = this.typeForField(rule.field)
    rule.operator = this.defaultOperatorFor(type)
    rule.value = ""
    this.commit()
  }

  changeOperator(event) {
    const path = this.parsePath(event.params.path)
    const rule = this.nodeAt(path)
    rule.operator = event.target.value
    this.commit()
  }

  changeValue(event) {
    const path = this.parsePath(event.params.path)
    const rule = this.nodeAt(path)
    rule.value = event.target.type === "checkbox" ? event.target.checked : event.target.value
    this.commit({skipRender: true})  // don't re-render on every keystroke
  }

  commit({skipRender = false} = {}) {
    this.treeValue = this._tree   // sync the Stimulus value (for inspection)
    if (this.hasHiddenInputTarget) {
      this.hiddenInputTarget.value = JSON.stringify(this._tree)
    }
    if (!skipRender) this.render()
    this.schedulePreview()
  }

  // ── preview ──────────────────────────────────────────────────────────────

  schedulePreview() {
    if (!this.hasPreviewTarget || !this.previewUrlValue) return
    clearTimeout(this._previewTimer)
    this._previewTimer = setTimeout(() => this.fetchPreview(), 400)
  }

  async fetchPreview() {
    this.previewTarget.innerHTML = `<div class="text-xs text-zinc-500 font-mono">previewing…</div>`
    try {
      const res = await fetch(this.previewUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": this.csrfValue,
          "Accept": "application/json"
        },
        body: `rules=${encodeURIComponent(JSON.stringify(this._tree))}`
      })
      const data = await res.json()
      if (!res.ok) {
        this.previewTarget.innerHTML = `<div class="text-rose-600 text-sm">${this.escape(data.error || "preview failed")}</div>`
        return
      }
      this.renderPreview(data)
    } catch (e) {
      this.previewTarget.innerHTML = `<div class="text-rose-600 text-sm">${this.escape(e.message)}</div>`
    }
  }

  renderPreview(data) {
    const sample = (data.sample || []).map(s => `
      <li class="py-2 flex items-center justify-between border-b border-zinc-100 last:border-0">
        <div>
          <div class="text-sm text-zinc-900">${this.escape(s.email)}</div>
          ${s.name ? `<div class="text-xs text-zinc-500">${this.escape(s.name)}</div>` : ""}
        </div>
        <div class="text-[10px] uppercase tracking-wider font-mono ${s.subscribed ? "text-emerald-600" : "text-zinc-400"}">
          ${s.subscribed ? "SUBSCRIBED" : "UNSUBSCRIBED"}
        </div>
      </li>`).join("")

    this.previewTarget.innerHTML = `
      <div class="border border-zinc-200 rounded-lg p-4 bg-white">
        <div class="text-[10px] uppercase tracking-wider text-zinc-500 font-mono mb-2">MATCHING</div>
        <div class="text-3xl font-semibold text-zinc-900 mb-3">${data.count.toLocaleString()}</div>
        ${data.count > 0 ? `
          <div class="text-[10px] uppercase tracking-wider text-zinc-500 font-mono mt-4 mb-1">SAMPLE</div>
          <ul class="divide-y divide-zinc-100">${sample}</ul>` : ""}
        <details class="mt-4 text-xs text-zinc-500">
          <summary class="cursor-pointer hover:text-zinc-700">SQL</summary>
          <pre class="mt-2 p-2 bg-zinc-50 rounded text-zinc-700 overflow-x-auto">${this.escape(data.sql || "(none)")}</pre>
        </details>
      </div>`
  }

  // ── rendering ────────────────────────────────────────────────────────────

  render() {
    if (!this.hasTreeTarget) return
    this.treeTarget.innerHTML = this.renderNode(this._tree, [])
    if (this.hasHiddenInputTarget) {
      this.hiddenInputTarget.value = JSON.stringify(this._tree)
    }
  }

  renderNode(node, path) {
    if (node.type === "group") return this.renderGroup(node, path)
    if (node.type === "rule")  return this.renderRule(node, path)
    return ""
  }

  renderGroup(group, path) {
    const pathStr = JSON.stringify(path)
    const childrenHtml = group.rules.map((child, i) => this.renderNode(child, [...path, i])).join(
      `<div class="flex items-center gap-2 py-1 pl-2">
         <button type="button"
                 data-action="click->segments-builder#toggleCombinator"
                 data-segments-builder-path-param='${pathStr}'
                 class="text-[10px] uppercase tracking-wider font-mono text-zinc-500 hover:text-orange-600 border border-zinc-200 rounded px-2 py-0.5">
           ${group.combinator.toUpperCase()}
         </button>
       </div>`
    )

    const removeBtn = path.length > 0 ? `
      <button type="button"
              data-action="click->segments-builder#removeNode"
              data-segments-builder-path-param='${pathStr}'
              class="text-zinc-400 hover:text-rose-600 text-sm px-2"
              title="Remove group">✕</button>` : ""

    return `
      <div class="border border-zinc-200 rounded-lg p-3 ${path.length > 0 ? "bg-zinc-50" : "bg-white"}">
        <div class="flex items-center justify-between mb-2">
          <div class="text-[10px] uppercase tracking-wider text-zinc-500 font-mono">
            ${path.length === 0 ? "WHEN" : "GROUP"} · ${group.combinator.toUpperCase()}
          </div>
          ${removeBtn}
        </div>
        <div class="space-y-1">${childrenHtml}</div>
        <div class="flex items-center gap-2 mt-3 pt-2 border-t border-zinc-100">
          <button type="button"
                  data-action="click->segments-builder#addRule"
                  data-segments-builder-path-param='${pathStr}'
                  class="text-xs text-orange-600 hover:text-orange-700">+ Add rule</button>
          <span class="text-zinc-300">·</span>
          <button type="button"
                  data-action="click->segments-builder#addGroup"
                  data-segments-builder-path-param='${pathStr}'
                  class="text-xs text-zinc-500 hover:text-zinc-700">+ Add group</button>
        </div>
      </div>`
  }

  renderRule(rule, path) {
    const pathStr = JSON.stringify(path)
    const type = this.typeForField(rule.field)
    const ops = this.operatorsValue[type] || ["equals"]
    const fieldOptions = Object.entries(this.fieldsValue).map(([groupLabel, fields]) => {
      const opts = fields.map(f =>
        `<option value="${this.escape(f.key)}" ${f.key === rule.field ? "selected" : ""}>${this.escape(f.label)}</option>`
      ).join("")
      return `<optgroup label="${this.escape(groupLabel)}">${opts}</optgroup>`
    }).join("")

    const opOptions = ops.map(o =>
      `<option value="${o}" ${o === rule.operator ? "selected" : ""}>${this.humanizeOp(o)}</option>`
    ).join("")

    const needsValue = !["is_set", "is_not_set"].includes(rule.operator)
    const valueInput = needsValue ? this.renderValueInput(rule, type, pathStr) : ""

    return `
      <div class="flex items-center gap-2 flex-wrap py-1">
        <select data-action="change->segments-builder#changeField"
                data-segments-builder-path-param='${pathStr}'
                class="border border-zinc-200 rounded px-2 py-1 text-sm bg-white focus:border-orange-600 focus:ring-0">
          ${fieldOptions}
        </select>
        <select data-action="change->segments-builder#changeOperator"
                data-segments-builder-path-param='${pathStr}'
                class="border border-zinc-200 rounded px-2 py-1 text-sm bg-white focus:border-orange-600 focus:ring-0">
          ${opOptions}
        </select>
        ${valueInput}
        <button type="button"
                data-action="click->segments-builder#removeNode"
                data-segments-builder-path-param='${pathStr}'
                class="text-zinc-400 hover:text-rose-600 text-sm px-1"
                title="Remove rule">✕</button>
      </div>`
  }

  renderValueInput(rule, type, pathStr) {
    const common = `data-action="input->segments-builder#changeValue change->segments-builder#changeValue"
                    data-segments-builder-path-param='${pathStr}'
                    class="border border-zinc-200 rounded px-2 py-1 text-sm bg-white focus:border-orange-600 focus:ring-0 flex-1 min-w-[12rem]"`
    if (type === "boolean") {
      return `
        <select ${common}>
          <option value="true"  ${String(rule.value) === "true"  ? "selected" : ""}>true</option>
          <option value="false" ${String(rule.value) === "false" ? "selected" : ""}>false</option>
        </select>`
    }
    if (type === "datetime") {
      if (["within_last_days", "more_than_days_ago"].includes(rule.operator)) {
        return `<input type="number" min="1" placeholder="days" value="${this.escape(rule.value || "")}" ${common}>`
      }
      return `<input type="datetime-local" value="${this.escape(rule.value || "")}" ${common}>`
    }
    return `<input type="text" value="${this.escape(rule.value || "")}" placeholder="value" ${common}>`
  }

  typeForField(fieldKey) {
    for (const fields of Object.values(this.fieldsValue)) {
      for (const f of fields) if (f.key === fieldKey) return f.type
    }
    return "string"  // custom_attributes fallback
  }

  humanizeOp(op) {
    return op.replace(/_/g, " ")
  }

  escape(s) {
    const div = document.createElement("div")
    div.textContent = s == null ? "" : String(s)
    return div.innerHTML
  }

  // Stimulus auto-parses params that look like JSON. So `data-…-path-param='[0]'`
  // arrives here as an array, but `'[]'` is sometimes returned as a string.
  // Normalize both.
  parsePath(raw) {
    if (Array.isArray(raw)) return raw
    if (typeof raw === "string") {
      try { return JSON.parse(raw) } catch { return [] }
    }
    return []
  }
}
