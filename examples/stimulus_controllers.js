// app/javascript/controllers/polar_checkout_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "spinner", "error"]
  static values = { 
    productId: String,
    successUrl: String,
    cancelUrl: String,
    customerId: String
  }

  connect() {
    this.buttonTarget.addEventListener("click", this.createCheckout.bind(this))
  }

  async createCheckout(event) {
    event.preventDefault()
    
    this.showLoading()
    this.clearError()

    try {
      const response = await fetch("/api/polar/checkouts", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({
          product_id: this.productIdValue,
          success_url: this.successUrlValue,
          cancel_url: this.cancelUrlValue,
          customer_id: this.customerIdValue
        })
      })

      const data = await response.json()

      if (response.ok) {
        window.location.href = data.url
      } else {
        this.showError(data.error || "Failed to create checkout session")
      }
    } catch (error) {
      this.showError("Network error occurred")
    } finally {
      this.hideLoading()
    }
  }

  showLoading() {
    this.buttonTarget.disabled = true
    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.remove("hidden")
    }
    this.buttonTarget.textContent = "Creating checkout..."
  }

  hideLoading() {
    this.buttonTarget.disabled = false
    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.add("hidden")
    }
    this.buttonTarget.textContent = "Subscribe Now"
  }

  showError(message) {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = message
      this.errorTarget.classList.remove("hidden")
    }
  }

  clearError() {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = ""
      this.errorTarget.classList.add("hidden")
    }
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")
  }
}

// app/javascript/controllers/polar_customer_portal_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button"]
  static values = { 
    customerId: String,
    returnUrl: String
  }

  async openPortal(event) {
    event.preventDefault()
    
    this.buttonTarget.disabled = true
    this.buttonTarget.textContent = "Opening portal..."

    try {
      const response = await fetch("/api/polar/customer-portal", {
        method: "POST", 
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({
          customer_id: this.customerIdValue,
          return_url: this.returnUrlValue
        })
      })

      const data = await response.json()

      if (response.ok) {
        window.open(data.url, "_blank", "noopener,noreferrer")
      } else {
        alert(data.error || "Failed to open customer portal")
      }
    } catch (error) {
      alert("Network error occurred")
    } finally {
      this.buttonTarget.disabled = false
      this.buttonTarget.textContent = "Manage Subscription"
    }
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")
  }
}

// app/javascript/controllers/polar_subscription_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cancelButton", "reactivateButton", "status", "cancelModal"]
  static values = { subscriptionId: String }

  async cancelSubscription(event) {
    event.preventDefault()
    
    const confirmed = confirm("Are you sure you want to cancel your subscription?")
    if (!confirmed) return

    this.cancelButtonTarget.disabled = true
    this.cancelButtonTarget.textContent = "Cancelling..."

    try {
      const response = await fetch(`/api/polar/subscriptions/${this.subscriptionIdValue}/cancel`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json", 
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({
          cancel_at_period_end: true
        })
      })

      const data = await response.json()

      if (response.ok) {
        this.updateSubscriptionStatus(data.status)
        this.showCancelledState()
      } else {
        alert(data.error || "Failed to cancel subscription")
      }
    } catch (error) {
      alert("Network error occurred")
    } finally {
      this.cancelButtonTarget.disabled = false
      this.cancelButtonTarget.textContent = "Cancel Subscription"
    }
  }

  async reactivateSubscription(event) {
    event.preventDefault()
    
    this.reactivateButtonTarget.disabled = true
    this.reactivateButtonTarget.textContent = "Reactivating..."

    try {
      const response = await fetch(`/api/polar/subscriptions/${this.subscriptionIdValue}/reactivate`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken
        }
      })

      const data = await response.json()

      if (response.ok) {
        this.updateSubscriptionStatus(data.status)
        this.showActiveState()
      } else {
        alert(data.error || "Failed to reactivate subscription")
      }
    } catch (error) {
      alert("Network error occurred")
    } finally {
      this.reactivateButtonTarget.disabled = false
      this.reactivateButtonTarget.textContent = "Reactivate"
    }
  }

  updateSubscriptionStatus(status) {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = status.charAt(0).toUpperCase() + status.slice(1)
      this.statusTarget.className = `status ${status}`
    }
  }

  showCancelledState() {
    this.cancelButtonTarget.classList.add("hidden")
    if (this.hasReactivateButtonTarget) {
      this.reactivateButtonTarget.classList.remove("hidden")
    }
  }

  showActiveState() {
    this.cancelButtonTarget.classList.remove("hidden")
    if (this.hasReactivateButtonTarget) {
      this.reactivateButtonTarget.classList.add("hidden")
    }
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")
  }
}

// app/javascript/controllers/polar_pricing_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["plan", "selectedPlan"]
  static values = { selectedPlanId: String }

  connect() {
    this.selectPlan(this.selectedPlanIdValue)
  }

  planSelected(event) {
    const planId = event.currentTarget.dataset.planId
    this.selectPlan(planId)
  }

  selectPlan(planId) {
    this.planTargets.forEach(plan => {
      plan.classList.remove("selected")
      if (plan.dataset.planId === planId) {
        plan.classList.add("selected")
      }
    })

    this.selectedPlanIdValue = planId
    this.updateSelectedPlanDisplay(planId)
  }

  updateSelectedPlanDisplay(planId) {
    const planElement = this.planTargets.find(plan => plan.dataset.planId === planId)
    if (planElement && this.hasSelectedPlanTarget) {
      const planName = planElement.dataset.planName
      const planPrice = planElement.dataset.planPrice
      this.selectedPlanTarget.textContent = `${planName} - ${planPrice}`
    }
  }

  getSelectedPlanId() {
    return this.selectedPlanIdValue
  }
}