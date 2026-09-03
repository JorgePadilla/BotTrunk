import { Controller } from "@hotwired/stimulus"

// Toggles between the two daisyUI themes and remembers the choice in a cookie,
// so the server can render the right `data-theme` on the next request (no flash).
//
//   <html data-theme="bottrunk-light" data-controller="theme">
//   <button data-action="theme#toggle">…</button>
export default class extends Controller {
  static values = { light: { type: String, default: "bottrunk-light" },
                    dark:  { type: String, default: "bottrunk-dark" } }

  toggle() {
    const next = this.current === this.darkValue ? this.lightValue : this.darkValue
    this.apply(next)
  }

  apply(theme) {
    document.documentElement.setAttribute("data-theme", theme)
    document.cookie = `theme=${theme}; path=/; max-age=31536000; samesite=lax`
    this.dispatch("changed", { detail: { theme } })
  }

  get current() {
    return document.documentElement.getAttribute("data-theme") || this.lightValue
  }
}
