// app/javascript/controllers/subscription_management_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "tierSelect", "billingInterval", "upgradeButton", "downgradeButton",
    "cancelButton", "reactivateButton", "usageBar", "quotaWarning",
    "trialBanner", "upgradeModal", "confirmationModal"
  ]
  
  static values = {
    currentTier: String,
    trialDaysRemaining: Number,
    trialActive: Boolean,
    subscriptionId: String,
    userId: String
  }

  connect() {
    this.updateUI()
    this.startUsagePolling()
    this.checkTrialStatus()
  }

  disconnect() {
    if (this.usagePollingInterval) {
      clearInterval(this.usagePollingInterval)
    }
  }

  // Tier selection and upgrading
  selectTier(event) {
    const selectedTier = event.currentTarget.dataset.tier
    const billingInterval = this.billingIntervalTarget.value
    
    this.showUpgradePreview(selectedTier, billingInterval)
  }

  async showUpgradePreview(newTier, billingInterval) {
    try {
      const response = await fetch('/subscriptions/upgrade_preview', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfToken
        },
        body: JSON.stringify({
          current_tier: this.currentTierValue,
          new_tier: newTier,
          billing_interval: billingInterval
        })
      })

      const data = await response.json()
      this.displayUpgradePreview(data, newTier)
    } catch (error) {
      console.error('Failed to get upgrade preview:', error)
    }
  }

  displayUpgradePreview(previewData, newTier) {
    const modal = this.upgradeModalTarget
    const content = modal.querySelector('.preview-content')
    
    content.innerHTML = `
      <h3>Upgrade to ${newTier.charAt(0).toUpperCase() + newTier.slice(1)}</h3>
      <div class="pricing-breakdown">
        <p>Prorated cost today: ${previewData.formatted_cost}</p>
        <p>Next billing date: ${new Date(previewData.next_billing_date).toLocaleDateString()}</p>
        <p>New monthly cost: $${previewData.new_monthly_cost}</p>
      </div>
      <div class="upgrade-benefits">
        <h4>You'll get immediate access to:</h4>
        <ul id="upgrade-benefits-list"></ul>
      </div>
    `
    
    this.showModal(modal)
  }

  async confirmUpgrade(event) {
    const newTier = event.currentTarget.dataset.tier
    const billingInterval = this.billingIntervalTarget.value
    
    this.upgradeButtonTarget.disabled = true
    this.upgradeButtonTarget.textContent = 'Processing...'

    try {
      const response = await fetch(`/subscriptions/${this.subscriptionIdValue}/change_tier`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfToken
        },
        body: JSON.stringify({
          new_tier: newTier,
          billing_interval: billingInterval
        })
      })

      if (response.ok) {
        window.location.reload()
      } else {
        throw new Error('Upgrade failed')
      }
    } catch (error) {
      this.showError('Failed to upgrade subscription. Please try again.')
    } finally {
      this.upgradeButtonTarget.disabled = false
      this.upgradeButtonTarget.textContent = 'Upgrade'
    }
  }

  // Subscription management
  async cancelSubscription(event) {
    const immediate = event.currentTarget.dataset.immediate === 'true'
    const message = immediate 
      ? 'Are you sure you want to cancel immediately? You will lose access right away.'
      : 'Are you sure? Your subscription will remain active until the end of your billing period.'
    
    if (!confirm(message)) return

    try {
      const response = await fetch(`/subscriptions/${this.subscriptionIdValue}/cancel`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfToken
        },
        body: JSON.stringify({ immediate: immediate })
      })

      if (response.ok) {
        window.location.reload()
      } else {
        throw new Error('Cancellation failed')
      }
    } catch (error) {
      this.showError('Failed to cancel subscription. Please try again.')
    }
  }

  async reactivateSubscription() {
    try {
      const response = await fetch(`/subscriptions/${this.subscriptionIdValue}/reactivate`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': this.csrfToken
        }
      })

      if (response.ok) {
        window.location.reload()
      } else {
        throw new Error('Reactivation failed')
      }
    } catch (error) {
      this.showError('Failed to reactivate subscription. Please try again.')
    }
  }

  // Usage monitoring
  startUsagePolling() {
    this.updateUsageDisplay()
    
    // Poll every 30 seconds for usage updates
    this.usagePollingInterval = setInterval(() => {
      this.updateUsageDisplay()
    }, 30000)
  }

  async updateUsageDisplay() {
    try {
      const response = await fetch('/api/usage/current')
      const data = await response.json()
      
      this.displayUsageData(data)
    } catch (error) {
      console.error('Failed to update usage:', error)
    }
  }

  displayUsageData(usageData) {
    this.usageBarTargets.forEach(bar => {
      const resource = bar.dataset.resource
      const usage = usageData[resource]
      
      if (usage) {
        const percentage = Math.min((usage.used / usage.limit) * 100, 100)
        bar.style.width = `${percentage}%`
        
        // Update color based on usage level
        bar.className = this.getUsageBarClass(percentage)
        
        // Update text
        const text = bar.parentElement.querySelector('.usage-text')
        if (text) {
          text.textContent = `${usage.used} / ${usage.limit} ${resource.replace('_', ' ')}`
        }
        
        // Show warnings if approaching limits
        if (percentage > 80) {
          this.showUsageWarning(resource, percentage)
        }
      }
    })
  }

  getUsageBarClass(percentage) {
    if (percentage >= 90) return 'usage-bar critical'
    if (percentage >= 80) return 'usage-bar warning'
    if (percentage >= 60) return 'usage-bar moderate'
    return 'usage-bar normal'
  }

  showUsageWarning(resource, percentage) {
    if (this.hasQuotaWarningTarget) {
      this.quotaWarningTarget.innerHTML = `
        <div class="alert alert-warning">
          <strong>Usage Warning:</strong> You've used ${percentage.toFixed(1)}% of your ${resource.replace('_', ' ')} quota.
          <a href="/pricing" class="alert-link">Upgrade now</a> to increase your limits.
        </div>
      `
      this.quotaWarningTarget.classList.remove('hidden')
    }
  }

  // Trial management
  checkTrialStatus() {
    if (!this.trialActiveValue) return
    
    this.updateTrialBanner()
    
    // Update trial banner every hour
    setInterval(() => {
      this.updateTrialBanner()
    }, 3600000)
  }

  updateTrialBanner() {
    if (!this.hasTrialBannerTarget) return
    
    const daysRemaining = this.trialDaysRemainingValue
    let message, urgency = ''
    
    if (daysRemaining <= 0) {
      message = 'Your trial has expired. Upgrade now to continue access.'
      urgency = 'critical'
    } else if (daysRemaining <= 1) {
      message = 'Your trial expires today! Upgrade now to avoid interruption.'
      urgency = 'critical'
    } else if (daysRemaining <= 3) {
      message = `Your trial expires in ${daysRemaining} days. Upgrade now to continue.`
      urgency = 'warning'
    } else if (daysRemaining <= 7) {
      message = `Your trial expires in ${daysRemaining} days.`
      urgency = 'info'
    }
    
    if (message) {
      this.trialBannerTarget.innerHTML = `
        <div class="trial-banner ${urgency}">
          <div class="trial-message">${message}</div>
          <a href="/pricing" class="btn btn-primary btn-sm">Choose Plan</a>
        </div>
      `
      this.trialBannerTarget.classList.remove('hidden')
    }
  }

  extendTrial() {
    // This would typically be an admin-only action or special promotion
    if (confirm('Request a trial extension? This will contact our support team.')) {
      this.contactSupport('trial_extension')
    }
  }

  // Billing interval switching
  switchBillingInterval(event) {
    const interval = event.currentTarget.value
    const tierCards = document.querySelectorAll('.tier-card')
    
    tierCards.forEach(card => {
      const monthlyPrice = card.dataset.monthlyPrice
      const yearlyPrice = card.dataset.yearlyPrice
      const priceElement = card.querySelector('.tier-price')
      
      if (interval === 'yearly') {
        priceElement.textContent = `$${yearlyPrice}/year`
        card.querySelector('.billing-note').textContent = `$${(yearlyPrice / 12).toFixed(0)}/month`
      } else {
        priceElement.textContent = `$${monthlyPrice}/month`
        card.querySelector('.billing-note').textContent = 'Billed monthly'
      }
    })
  }

  // Customer portal
  async openCustomerPortal() {
    try {
      const response = await fetch('/subscriptions/portal', {
        method: 'POST',
        headers: {
          'X-CSRF-Token': this.csrfToken
        }
      })
      
      const data = await response.json()
      if (data.url) {
        window.open(data.url, '_blank', 'noopener,noreferrer')
      }
    } catch (error) {
      this.showError('Failed to open customer portal. Please try again.')
    }
  }

  // Utility methods
  showModal(modal) {
    modal.classList.add('show')
    document.body.classList.add('modal-open')
  }

  hideModal(modal) {
    modal.classList.remove('show')
    document.body.classList.remove('modal-open')
  }

  showError(message) {
    // Implement your error display logic here
    alert(message)
  }

  contactSupport(reason) {
    // Implement support contact logic
    window.open(`mailto:support@yourapp.com?subject=Support Request: ${reason}`)
  }

  updateUI() {
    // Update UI based on current subscription state
    const tier = this.currentTierValue
    const trialActive = this.trialActiveValue
    
    // Highlight current tier
    document.querySelectorAll('.tier-card').forEach(card => {
      if (card.dataset.tier === tier) {
        card.classList.add('current-tier')
      } else {
        card.classList.remove('current-tier')
      }
    })
    
    // Show/hide appropriate buttons
    if (trialActive) {
      this.element.classList.add('trial-active')
    } else {
      this.element.classList.remove('trial-active')
    }
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
  }
}