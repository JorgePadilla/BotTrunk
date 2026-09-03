import { Controller } from "@hotwired/stimulus"

// Minimal tabs: buttons carry data-tabs-index-param, panels are targets in the same order.
export default class extends Controller {
  static targets = ["tab", "panel"]
  static classes = ["active"]

  select(event) {
    const index = Number(event.params.index)
    this.tabTargets.forEach((tab, i) => tab.classList.toggle(this.activeClass, i === index))
    this.panelTargets.forEach((panel, i) => (panel.hidden = i !== index))
  }
}
