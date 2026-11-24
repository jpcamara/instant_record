import { Controller } from "@hotwired/stimulus"
import * as Y from "yjs"

// Each field (the title, the text) lives in its own Yjs document. Typing edits
// the document, and each save sends every document's whole state to the
// draft's update action, which stores them in the local database to sync. When
// the record changes (another tab, or the server's merge arriving), the page
// reads the stored states and merges them in.
export default class extends Controller {
  static targets = ["field", "state"]
  static values = { url: String }

  connect() {
    this.fields = this.fieldTargets.map((element) => {
      const doc = new Y.Doc()
      const field = { element, column: element.dataset.column, doc, text: doc.getText(element.dataset.column) }
      this.merge(field, this.stateTarget.dataset[`${field.column}State`])
      element.value = field.text.toString()
      doc.on("update", (_update, origin) => {
        if (origin !== REMOTE) this.scheduleSave()
      })
      return field
    })
  }

  disconnect() {
    clearTimeout(this.timer)
    if (this.dirty) this.save()
  }

  // Turns the field's change into one delete and one insert.
  input({ target }) {
    const field = this.fields.find((field) => field.element === target)
    const before = field.text.toString()
    const after = target.value
    let start = 0
    while (start < before.length && start < after.length && before[start] === after[start]) start++
    let endBefore = before.length
    let endAfter = after.length
    while (endBefore > start && endAfter > start && before[endBefore - 1] === after[endAfter - 1]) {
      endBefore--
      endAfter--
    }
    field.doc.transact(() => {
      if (endBefore > start) field.text.delete(start, endBefore - start)
      if (endAfter > start) field.text.insert(start, after.slice(start, endAfter))
    })
  }

  scheduleSave() {
    this.dirty = true
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.save(), 300)
  }

  async save() {
    this.dirty = false
    const body = new URLSearchParams()
    body.set("_method", "patch")
    for (const field of this.fields) {
      body.set(`draft[${field.column}]`, field.text.toString())
      body.set(`draft[${field.column}_ydoc]`, toBase64(Y.encodeStateAsUpdate(field.doc)))
    }
    const token = document.querySelector("meta[name='csrf-token']")?.content
    const response = await fetch(this.urlValue, { method: "POST", body, headers: token ? { "X-CSRF-Token": token } : {} })
    if (response.ok) this.read(await response.text())
  }

  // instant-record:records-changed@window
  async pull() {
    const response = await fetch(`${this.urlValue}?fragment=1`)
    if (response.ok) this.read(await response.text())
  }

  read(html) {
    const template = document.createElement("template")
    template.innerHTML = html.trim()
    const fresh = template.content.querySelector("[data-draft-target=state]")
    if (!fresh) return
    for (const field of this.fields) this.merge(field, fresh.dataset[`${field.column}State`])
  }

  // Merges a stored state into the field's document and redraws the field,
  // keeping the cursor on the same characters.
  merge(field, state) {
    if (!state) return
    const { element, doc, text } = field
    const focused = document.activeElement === element
    const anchor = Y.createRelativePositionFromTypeIndex(text, element.selectionStart ?? 0)
    const head = Y.createRelativePositionFromTypeIndex(text, element.selectionEnd ?? 0)
    const before = text.toString()
    Y.applyUpdate(doc, fromBase64(state), REMOTE)
    const after = text.toString()
    if (before === after) return

    element.value = after
    if (focused) {
      const start = Y.createAbsolutePositionFromRelativePosition(anchor, doc)?.index ?? after.length
      const end = Y.createAbsolutePositionFromRelativePosition(head, doc)?.index ?? start
      element.setSelectionRange(start, end)
    }
  }
}

const REMOTE = "remote"

const toBase64 = (bytes) => {
  let binary = ""
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary)
}

const fromBase64 = (text) => Uint8Array.from(atob(text), (c) => c.charCodeAt(0))
