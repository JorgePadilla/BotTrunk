import { Controller } from "@hotwired/stimulus"

// ⌘K / Ctrl-K focuses the catalog search; Esc clears and blurs it.
export default class extends Controller {
  static targets = ["input"]

  connect() {
    this.onKey = (event) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault()
        this.inputTarget.focus()
        this.inputTarget.select()
      }
    }
    document.addEventListener("keydown", this.onKey)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKey)
  }

  clear(event) {
    if (event.key !== "Escape") return
    this.inputTarget.value = ""
    this.inputTarget.blur()
  }
}
