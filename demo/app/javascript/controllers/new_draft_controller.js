import { Controller } from "@hotwired/stimulus"
import * as Y from "yjs"

// A new draft's title starts as a Yjs document, so the server can merge later
// edits to it. The form sends the document's state with the title.
export default class extends Controller {
  static targets = ["title", "state"]

  submit() {
    const doc = new Y.Doc()
    doc.getText("title").insert(0, this.titleTarget.value)
    let binary = ""
    for (const byte of Y.encodeStateAsUpdate(doc)) binary += String.fromCharCode(byte)
    this.stateTarget.value = btoa(binary)
  }
}
