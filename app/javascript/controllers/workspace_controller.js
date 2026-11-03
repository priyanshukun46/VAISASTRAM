import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["prompt", "model"]

  setPrompt(event) {
    const text = event.currentTarget.dataset.promptText
    if (this.hasPromptTarget && text) {
      this.promptTarget.value = text
      this.promptTarget.focus()
      // Scroll smoothly to prompt card if needed
      this.promptTarget.scrollIntoView({ behavior: 'smooth', block: 'center' })
    }
  }
}
