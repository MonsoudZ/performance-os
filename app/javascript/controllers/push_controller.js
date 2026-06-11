import { Controller } from "@hotwired/stimulus"

// Subscribes/unsubscribes the browser to Web Push check-in reminders.
export default class extends Controller {
  static targets = ["button"]

  async connect() {
    if (!("serviceWorker" in navigator) || !("PushManager" in window) || !this.vapidKey()) {
      this.element.hidden = true
      return
    }
    this.registration = await navigator.serviceWorker.ready
    const subscription = await this.registration.pushManager.getSubscription()
    this.element.hidden = false
    this.render(Boolean(subscription))
  }

  async toggle() {
    const subscription = await this.registration.pushManager.getSubscription()
    if (subscription) {
      await this.disable(subscription)
    } else {
      await this.enable()
    }
  }

  async enable() {
    if ((await Notification.requestPermission()) !== "granted") return

    const subscription = await this.registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: this.vapidKey()
    })
    const keys = subscription.toJSON().keys
    await this.send("POST", {
      push_subscription: { endpoint: subscription.endpoint, p256dh_key: keys.p256dh, auth_key: keys.auth }
    })
    this.render(true)
  }

  async disable(subscription) {
    await subscription.unsubscribe()
    await this.send("DELETE", { endpoint: subscription.endpoint })
    this.render(false)
  }

  render(enabled) {
    if (this.hasButtonTarget) {
      this.buttonTarget.textContent = enabled ? "Disable check-in reminders" : "Enable check-in reminders"
    }
  }

  async send(method, body) {
    await fetch("/push_subscriptions", {
      method,
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfToken() },
      body: JSON.stringify(body)
    })
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  vapidKey() {
    const encoded = document.querySelector('meta[name="vapid-public-key"]')?.content
    if (!encoded) return null

    const padding = "=".repeat((4 - (encoded.length % 4)) % 4)
    const base64 = (encoded + padding).replace(/-/g, "+").replace(/_/g, "/")
    const raw = atob(base64)
    return Uint8Array.from([...raw].map((char) => char.charCodeAt(0)))
  }
}
