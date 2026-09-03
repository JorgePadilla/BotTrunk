import { Controller } from "@hotwired/stimulus"

// Copies `textValue` (or the content of the `source` target) and flips the
// button label to "Copied" for a moment.
export default class extends Controller {
  static targets = ["source", "label"]
  static values = { text: String }

  async copy() {
    const text = this.hasTextValue ? this.textValue : this.sourceTarget.innerText
    await navigator.clipboard.writeText(text)
    if (this.hasLabelTarget) {
      const original = this.labelTarget.textContent
      this.labelTarget.textContent = "Copied"
      setTimeout(() => (this.labelTarget.textContent = original), 1500)
    }
  }
}
