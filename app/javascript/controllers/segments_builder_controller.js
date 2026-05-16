import { Controller } from "@hotwired/stimulus"
import TomSelect from "tom-select"

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
    this._tomSelects = []
    this.render()
    this.schedulePreview()
  }

  disconnect() {
    this.destroyTomSelects()
  }

  destroyTomSelects() {
    if (!this._tomSelects) return
    this._tomSelects.forEach(ts => { try { ts.destroy() } catch { /* ignore */ } })
    this._tomSelects = []
  }

  // ── tree helpers ─────────────────────────────────────────────────────────

  emptyGroup() {
    return {type: "group", combinator: "and", rules: [this.emptyRule()]}
  }

  emptyRule() {
    const firstGroup = Object.values(this.fieldsValue)[0] || []
    const first = firstGroup[0]
    const type = first ? first.type : "string"
    return {
      type: "rule",
      field: first ? first.key : "subscribers.email",
      value_type: type,   // shipped to server; needed for custom_attributes
      operator: this.defaultOperatorFor(type),
      value: this.defaultValueFor(type)
    }
  }

  defaultOperatorFor(type) {
    const ops = (this.operatorsValue[type] || ["equals"])
    return ops[0]
  }

  // Default rule.value for a freshly-typed slot. Empty string is fine for
  // strings + datetimes (they have a placeholder), but for booleans an empty
  // value compiles to `subscribers.foo = 0` — which silently matches the
  // "false" set without the user seeing why. Pick "true" so the visible
  // dropdown state matches the saved state.
  defaultValueFor(type) {
    if (type === "boolean") return "true"
    return ""
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
    rule.value_type = type
    rule.operator = this.defaultOperatorFor(type)
    rule.value = this.defaultValueFor(type)
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
    const sample = (data.sample || []).map(s => {
      const attrsHtml = (s.attrs || []).map(a => `
        <div class="flex items-baseline justify-between gap-3 text-xs">
          <span class="text-zinc-500 font-mono">${this.escape(a.label)}</span>
          <span class="text-zinc-800 font-mono tabular-nums truncate text-right">${this.formatValue(a.value)}</span>
        </div>`).join("")

      return `
        <li class="py-3 border-b border-zinc-100 last:border-0">
          <div class="flex items-center justify-between gap-3 mb-1">
            <div class="min-w-0">
              <div class="text-sm text-zinc-900 truncate">${this.escape(s.email)}</div>
              ${s.name ? `<div class="text-xs text-zinc-500 truncate">${this.escape(s.name)}</div>` : ""}
            </div>
            <div class="text-[10px] uppercase tracking-wider font-mono shrink-0 ${s.subscribed ? "text-emerald-600" : "text-zinc-400"}">
              ${s.subscribed ? "SUBSCRIBED" : "UNSUBSCRIBED"}
            </div>
          </div>
          ${attrsHtml ? `<div class="mt-2 space-y-1">${attrsHtml}</div>` : ""}
        </li>`
    }).join("")

    // Horizontal layout — big count on the left, sample column on the right.
    // The preview lives full-width below the rule builder; this layout makes
    // the number feel like a banner instead of a footnote.
    this.previewTarget.innerHTML = `
      <div class="border border-zinc-200 rounded-lg bg-white overflow-hidden">
        <div class="grid grid-cols-1 md:grid-cols-3 divide-y md:divide-y-0 md:divide-x divide-zinc-100">
          <div class="p-6 md:col-span-1 flex flex-col justify-center">
            <div class="text-[10px] uppercase tracking-wider text-zinc-500 font-mono mb-1">MATCHING</div>
            <div class="text-6xl font-semibold text-zinc-900 tracking-tight tabular-nums leading-none mb-1">
              ${data.count.toLocaleString()}
            </div>
            <div class="text-xs text-zinc-500 font-mono">${data.count === 1 ? "subscriber" : "subscribers"}</div>
            <details class="mt-4 text-xs text-zinc-500">
              <summary class="cursor-pointer hover:text-zinc-700 font-mono uppercase tracking-wider">SQL</summary>
              <pre class="mt-2 p-2 bg-zinc-50 rounded text-zinc-700 overflow-x-auto text-[11px]">${this.escape(data.sql || "(none)")}</pre>
            </details>
          </div>
          <div class="p-6 md:col-span-2">
            ${data.count > 0 ? `
              <div class="text-[10px] uppercase tracking-wider text-zinc-500 font-mono mb-2">SAMPLE</div>
              <ul class="divide-y divide-zinc-100">${sample}</ul>` : `
              <div class="text-sm text-zinc-400 italic h-full flex items-center justify-center">No subscribers match this filter.</div>`}
          </div>
        </div>
      </div>`
  }

  // Render a value from sample.attrs — strings get escaped, booleans get a
  // ✓/✗ glyph, nullish renders as muted "—". Long strings truncate via the
  // parent's `truncate` class.
  formatValue(v) {
    if (v === true)  return `<span class="text-emerald-600">✓ true</span>`
    if (v === false) return `<span class="text-zinc-500">✗ false</span>`
    if (v === null || v === undefined || v === "") return `<span class="text-zinc-300">—</span>`
    return this.escape(String(v))
  }

  // ── rendering ────────────────────────────────────────────────────────────

  render() {
    if (!this.hasTreeTarget) return
    this.destroyTomSelects()
    this.treeTarget.innerHTML = this.renderNode(this._tree, [])
    this.enhanceSelects()
    if (this.hasHiddenInputTarget) {
      this.hiddenInputTarget.value = JSON.stringify(this._tree)
    }
  }

  // Tom Select wraps every <select data-segments-builder-enhance> in the tree.
  // We rebuild on every render (the tree HTML is re-templated wholesale), so
  // destroy + recreate is cheap and avoids stale-instance bugs.
  enhanceSelects() {
    const selects = this.treeTarget.querySelectorAll("select[data-segments-builder-enhance]")
    selects.forEach(el => {
      const variant = el.dataset.segmentsBuilderEnhance  // "field" | "operator" | "boolean" | "value"
      const searchable = variant === "field" || variant === "value"
      const ts = new TomSelect(el, {
        controlInput: searchable ? "<input>" : null,
        maxOptions: 500,
        plugins: searchable ? ["dropdown_input"] : [],
        hideSelected: false,
        openOnFocus: true,
        // value selects allow free-form input so the user can type a value
        // we haven't seen in the data yet. Field/operator/boolean are
        // strictly enumerated.
        create: variant === "value",
        createOnBlur: variant === "value",
        persist: false,
        allowEmptyOption: variant === "value",
        sortField: variant === "field" ? null : {field: "$order"},
        // Placeholder shown when the value is empty (matches the old text
        // input's placeholder).
        placeholder: variant === "value" ? "value" : null,
        // Detach the dropdown from the rule's container so it can't be
        // clipped by parent overflow / overflow-hidden card chrome.
        dropdownParent: "body",
        // Marker class so our CSS can target body-attached dropdowns
        // without leaking into other Tom Select instances.
        dropdownClass: "ts-dropdown segments-builder__dropdown"
      })
      this._tomSelects.push(ts)
    })
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
                data-segments-builder-enhance="field"
                class="segments-builder__field-select">
          ${fieldOptions}
        </select>
        <select data-action="change->segments-builder#changeOperator"
                data-segments-builder-path-param='${pathStr}'
                data-segments-builder-enhance="operator"
                class="segments-builder__operator-select">
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
        <select ${common} data-segments-builder-enhance="boolean">
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
    // String / csv_list / array values can autocomplete from observed data.
    // We render a TomSelect with create:true so users can also type values
    // that aren't in the suggestions (e.g. a value the data hasn't seen yet).
    if ((type === "string" || type === "csv_list" || type === "array") && this.samplesFor(rule.field).length > 0) {
      const opts = this.samplesFor(rule.field)
        .map(v => `<option value="${this.escape(v)}" ${String(rule.value) === v ? "selected" : ""}>${this.escape(v)}</option>`)
        .join("")
      const currentMissing = rule.value && !this.samplesFor(rule.field).includes(String(rule.value))
        ? `<option value="${this.escape(rule.value)}" selected>${this.escape(rule.value)}</option>`
        : ""
      return `
        <select ${common} data-segments-builder-enhance="value">
          <option value=""></option>
          ${currentMissing}
          ${opts}
        </select>`
    }
    if (type === "number") {
      if (rule.operator === "between") {
        const [lo = "", hi = ""] = Array.isArray(rule.value) ? rule.value : [rule.value, ""]
        return `
          <input type="number" placeholder="min" value="${this.escape(lo)}"
                 data-action="input->segments-builder#changeBetween change->segments-builder#changeBetween"
                 data-segments-builder-path-param='${pathStr}'
                 data-segments-builder-bound-param="lo"
                 class="border border-zinc-200 rounded px-2 py-1 text-sm bg-white focus:border-orange-600 focus:ring-0 flex-1 min-w-[6rem]">
          <input type="number" placeholder="max" value="${this.escape(hi)}"
                 data-action="input->segments-builder#changeBetween change->segments-builder#changeBetween"
                 data-segments-builder-path-param='${pathStr}'
                 data-segments-builder-bound-param="hi"
                 class="border border-zinc-200 rounded px-2 py-1 text-sm bg-white focus:border-orange-600 focus:ring-0 flex-1 min-w-[6rem]">`
      }
      return `<input type="number" value="${this.escape(rule.value ?? "")}" placeholder="number" ${common}>`
    }
    // :array — single value being tested for element membership. Future:
    // could swap for a Tom Select that suggests values from observed samples.
    return `<input type="text" value="${this.escape(rule.value || "")}" placeholder="value" ${common}>`
  }

  // Two-input handler for the number `between` operator. Stores [lo, hi].
  changeBetween(event) {
    const path = this.parsePath(event.params.path)
    const rule = this.nodeAt(path)
    const bound = event.params.bound  // "lo" | "hi"
    const current = Array.isArray(rule.value) ? [...rule.value] : [rule.value, ""]
    if (bound === "lo") current[0] = event.target.value
    else current[1] = event.target.value
    rule.value = current
    this.commit({skipRender: true})
  }

  typeForField(fieldKey) {
    for (const fields of Object.values(this.fieldsValue)) {
      for (const f of fields) if (f.key === fieldKey) return f.type
    }
    return "string"  // custom_attributes fallback
  }

  // Observed-value samples for a given field key (used for value-input
  // autocomplete). Returns [] for fields we don't have suggestions for.
  samplesFor(fieldKey) {
    for (const fields of Object.values(this.fieldsValue)) {
      for (const f of fields) if (f.key === fieldKey) return f.samples || []
    }
    return []
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
