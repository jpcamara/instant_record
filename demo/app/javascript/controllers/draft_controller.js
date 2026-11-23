import { Controller } from "@hotwired/stimulus"
import * as Y from "yjs"

// The text lives in a Yjs document. Typing edits the document, and each save
// sends its whole state to the draft's update action, which stores it in the
// local database to sync. When the record changes (another tab, or the
// server's merge arriving), the page reads the stored state and merges it in.
export default class extends Controller {
  static targets = ["editor", "state"]
  static values = { url: String }

  connect() {
    this.doc = new Y.Doc()
    this.text = this.doc.getText("body")
    this.merge(this.stateTarget.dataset.state)
    this.editorTarget.value = this.text.toString()
    this.doc.on("update", (_update, origin) => {
      if (origin !== REMOTE) this.scheduleSave()
    })
  }

  disconnect() {
    clearTimeout(this.timer)
    if (this.dirty) this.save()
  }

  // Turns the textarea's change into one delete and one insert.
  input() {
    const before = this.text.toString()
    const after = this.editorTarget.value
    let start = 0
    while (start < before.length && start < after.length && before[start] === after[start]) start++
    let endBefore = before.length
    let endAfter = after.length
    while (endBefore > start && endAfter > start && before[endBefore - 1] === after[endAfter - 1]) {
      endBefore--
      endAfter--
    }
    this.doc.transact(() => {
      if (endBefore > start) this.text.delete(start, endBefore - start)
      if (endAfter > start) this.text.insert(start, after.slice(start, endAfter))
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
    body.set("draft[body]", this.text.toString())
    body.set("draft[body_ydoc]", toBase64(Y.encodeStateAsUpdate(this.doc)))
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
    const fresh = template.content.querySelector("[data-state]")
    if (!fresh) return
    this.merge(fresh.dataset.state)
  }

  // Merges a stored state into the document and redraws the textarea, keeping
  // the cursor on the same characters.
  merge(state) {
    if (!state) return
    const editor = this.editorTarget
    const focused = document.activeElement === editor
    const anchor = Y.createRelativePositionFromTypeIndex(this.text, editor.selectionStart)
    const head = Y.createRelativePositionFromTypeIndex(this.text, editor.selectionEnd)
    const before = this.text.toString()
    Y.applyUpdate(this.doc, fromBase64(state), REMOTE)
    const after = this.text.toString()
    if (before === after) return

    editor.value = after
    if (focused) {
      const start = Y.createAbsolutePositionFromRelativePosition(anchor, this.doc)?.index ?? after.length
      const end = Y.createAbsolutePositionFromRelativePosition(head, this.doc)?.index ?? start
      editor.setSelectionRange(start, end)
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
