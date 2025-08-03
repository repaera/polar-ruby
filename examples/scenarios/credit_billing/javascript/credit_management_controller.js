// app/javascript/controllers/credit_management_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "balance", "purchaseButton", "autoRechargeToggle", "thresholdInput",
    "packageSelect", "costEstimate", "usageChart", "balanceWarning",
    "operationForm", "rechargeSettings"
  ]
  
  static values = {
    balance: Number,
    autoRechargeEnabled: Boolean,
    threshold: Number,
    userId: String
  }

  connect() {
    this.updateBalanceDisplay()
    this.startBalancePolling()
    this.initializeCostCalculator()
    this.checkLowBalance()
  }

  disconnect() {
    if (this.balancePollingInterval) {
      clearInterval(this.balancePollingInterval)
    }
  }

  // Balance management
  startBalancePolling() {
    // Poll balance every 10 seconds for real-time updates
    this.balancePollingInterval = setInterval(() => {
      this.fetchCurrentBalance()
    }, 10000)
  }

  async fetchCurrentBalance() {
    try {
      const response = await fetch('/credits/balance_check')
      const data = await response.json()
      
      if (data.balance !== this.balanceValue) {
        this.balanceValue = data.balance
        this.updateBalanceDisplay()
        this.checkLowBalance()
      }
    } catch (error) {
      console.error('Failed to fetch balance:', error)
    }
  }

  updateBalanceDisplay() {
    if (this.hasBalanceTarget) {
      this.balanceTarget.textContent = this.formatCredits(this.balanceValue)
      
      // Update color based on balance level
      this.balanceTarget.className = this.getBalanceClass(this.balanceValue)
    }
  }

  formatCredits(amount) {
    if (amount >= 1000000) {
      return `${(amount / 1000000).toFixed(1)}M credits`
    } else if (amount >= 1000) {
      return `${(amount / 1000).toFixed(1)}K credits`
    } else {
      return `${amount.toLocaleString()} credits`
    }
  }

  getBalanceClass(balance) {
    if (balance <= this.thresholdValue * 0.5) return 'balance critical'
    if (balance <= this.thresholdValue) return 'balance warning'
    if (balance <= this.thresholdValue * 2) return 'balance moderate'
    return 'balance normal'
  }

  checkLowBalance() {
    if (this.balanceValue <= this.thresholdValue && this.hasBalanceWarningTarget) {
      this.showLowBalanceWarning()
    } else if (this.hasBalanceWarningTarget) {
      this.hideBalanceWarning()
    }
  }

  showLowBalanceWarning() {
    this.balanceWarningTarget.innerHTML = `
      <div class="alert alert-warning">
        <strong>Low Balance:</strong> You have ${this.formatCredits(this.balanceValue)} remaining.
        <button data-action="click->credit-management#showPurchaseOptions" class="btn btn-sm btn-primary">
          Add Credits
        </button>
      </div>
    `
    this.balanceWarningTarget.classList.remove('hidden')
  }

  hideBalanceWarning() {
    this.balanceWarningTarget.classList.add('hidden')
  }

  // Credit purchasing
  async purchaseCredits(event) {
    const packageId = event.currentTarget.dataset.packageId
    
    this.purchaseButtonTarget.disabled = true
    this.purchaseButtonTarget.textContent = 'Processing...'

    try {
      const response = await fetch(`/credits/purchase/${packageId}`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': this.csrfToken
        }
      })

      const data = await response.json()
      if (data.checkout_url) {
        window.location.href = data.checkout_url
      } else {
        throw new Error('No checkout URL received')
      }
    } catch (error) {
      this.showError('Failed to initiate purchase. Please try again.')
    } finally {
      this.purchaseButtonTarget.disabled = false
      this.purchaseButtonTarget.textContent = 'Purchase Credits'
    }
  }

  showPurchaseOptions() {
    const modal = document.getElementById('purchase-modal')
    if (modal) {
      modal.classList.add('show')
      this.loadRecommendedPackage()
    }
  }

  async loadRecommendedPackage() {
    try {
      const response = await fetch('/credits/recommended_package')
      const data = await response.json()
      
      if (data.package) {
        this.highlightRecommendedPackage(data.package.id)
      }
    } catch (error) {
      console.error('Failed to load recommendation:', error)
    }
  }

  highlightRecommendedPackage(packageId) {
    document.querySelectorAll('.credit-package').forEach(pkg => {
      if (pkg.dataset.packageId === packageId.toString()) {
        pkg.classList.add('recommended')
        pkg.querySelector('.package-badge').textContent = 'Recommended'
      }
    })
  }

  // Auto-recharge management
  toggleAutoRecharge(event) {
    const enabled = event.currentTarget.checked
    this.autoRechargeEnabledValue = enabled
    
    this.updateAutoRechargeSettings()
  }

  updateThreshold(event) {
    const threshold = parseFloat(event.currentTarget.value)
    this.thresholdValue = threshold
    
    this.updateAutoRechargeSettings()
  }

  async updateAutoRechargeSettings() {
    try {
      const response = await fetch('/credits/auto_recharge', {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfToken
        },
        body: JSON.stringify({
          auto_recharge_enabled: this.autoRechargeEnabledValue,
          auto_recharge_threshold: this.thresholdValue,
          auto_recharge_package_id: this.getSelectedPackageId()
        })
      })

      if (response.ok) {
        this.showSuccess('Auto-recharge settings updated')
      } else {
        throw new Error('Update failed')
      }
    } catch (error) {
      this.showError('Failed to update auto-recharge settings')
    }
  }

  getSelectedPackageId() {
    if (this.hasPackageSelectTarget) {
      return this.packageSelectTarget.value
    }
    return null
  }

  // Cost estimation
  initializeCostCalculator() {
    if (this.hasOperationFormTarget) {
      this.operationFormTarget.addEventListener('input', this.calculateCost.bind(this))
    }
  }

  async calculateCost() {
    const formData = new FormData(this.operationFormTarget)
    const operationType = formData.get('operation_type')
    
    if (!operationType) return
    
    const parameters = {
      file_size: formData.get('file_size'),
      complexity: formData.get('complexity'),
      quantity: formData.get('quantity'),
      priority: formData.get('priority')
    }

    try {
      const response = await fetch('/credits/cost_estimator', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfToken
        },
        body: JSON.stringify({
          operation_type: operationType,
          parameters: parameters
        })
      })

      const data = await response.json()
      this.displayCostEstimate(data)
    } catch (error) {
      console.error('Failed to calculate cost:', error)
    }
  }

  displayCostEstimate(costData) {
    if (this.hasCostEstimateTarget) {
      const canAfford = costData.can_afford
      const balanceAfter = costData.balance_after
      
      this.costEstimateTarget.innerHTML = `
        <div class="cost-breakdown">
          <div class="cost-amount ${canAfford ? 'affordable' : 'unaffordable'}">
            ${costData.cost} credits
          </div>
          <div class="cost-details">
            <small>Balance after: ${balanceAfter} credits</small>
          </div>
          ${!canAfford ? '<div class="insufficient-warning">Insufficient credits</div>' : ''}
        </div>
      `
    }
  }

  // Usage analytics
  async loadUsageChart() {
    try {
      const period = document.querySelector('#usage-period')?.value || '30_days'
      const response = await fetch(`/credits/usage_analytics?period=${period}`)
      const data = await response.json()
      
      this.renderUsageChart(data)
    } catch (error) {
      console.error('Failed to load usage data:', error)
    }
  }

  renderUsageChart(data) {
    if (!this.hasUsageChartTarget) return
    
    // Simple bar chart implementation
    // In a real app, you'd use Chart.js or similar
    const chartHtml = Object.entries(data.usage_by_operation || {})
      .map(([operation, credits]) => `
        <div class="usage-bar-container">
          <label>${operation.replace('_', ' ').toUpperCase()}</label>
          <div class="usage-bar">
            <div class="usage-fill" style="width: ${this.calculateBarWidth(credits, data)}%"></div>
          </div>
          <span class="usage-amount">${credits} credits</span>
        </div>
      `).join('')
    
    this.usageChartTarget.innerHTML = `
      <div class="usage-chart">
        <h4>Usage by Operation Type</h4>
        ${chartHtml}
      </div>
    `
  }

  calculateBarWidth(credits, data) {
    const maxCredits = Math.max(...Object.values(data.usage_by_operation || {}))
    return maxCredits > 0 ? (credits / maxCredits) * 100 : 0
  }

  // Operation execution with credit validation
  async executeOperation(event) {
    const button = event.currentTarget
    const operationType = button.dataset.operationType
    const operationId = button.dataset.operationId
    
    // Estimate cost first
    const cost = await this.getOperationCost(operationType)
    
    if (cost > this.balanceValue) {
      this.showInsufficientCreditsModal(cost)
      return
    }
    
    if (!this.confirmOperation(operationType, cost)) {
      return
    }
    
    button.disabled = true
    button.textContent = 'Processing...'
    
    try {
      const response = await fetch(`/api/operations/${operationType}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfToken
        },
        body: JSON.stringify({
          operation_id: operationId,
          parameters: this.gatherOperationParameters()
        })
      })
      
      if (response.ok) {
        const result = await response.json()
        this.handleOperationSuccess(result)
        
        // Update balance after successful operation
        this.balanceValue -= cost
        this.updateBalanceDisplay()
      } else {
        throw new Error('Operation failed')
      }
    } catch (error) {
      this.showError('Operation failed. Credits have not been deducted.')
    } finally {
      button.disabled = false
      button.textContent = 'Execute'
    }
  }

  async getOperationCost(operationType) {
    try {
      const response = await fetch(`/api/operations/${operationType}/cost`)
      const data = await response.json()
      return data.cost
    } catch (error) {
      return 0
    }
  }

  confirmOperation(operationType, cost) {
    return confirm(`Execute ${operationType.replace('_', ' ')} for ${cost} credits?`)
  }

  showInsufficientCreditsModal(requiredCredits) {
    const shortage = requiredCredits - this.balanceValue
    
    const modal = document.createElement('div')
    modal.className = 'modal show'
    modal.innerHTML = `
      <div class="modal-dialog">
        <div class="modal-content">
          <div class="modal-header">
            <h5>Insufficient Credits</h5>
          </div>
          <div class="modal-body">
            <p>You need ${requiredCredits} credits but only have ${this.balanceValue}.</p>
            <p>You need ${shortage} more credits to perform this operation.</p>
          </div>
          <div class="modal-footer">
            <button type="button" class="btn btn-secondary" data-action="click->credit-management#closeModal">Cancel</button>
            <button type="button" class="btn btn-primary" data-action="click->credit-management#showPurchaseOptions">Add Credits</button>
          </div>
        </div>
      </div>
    `
    
    document.body.appendChild(modal)
  }

  closeModal(event) {
    const modal = event.currentTarget.closest('.modal')
    if (modal) {
      modal.remove()
    }
  }

  gatherOperationParameters() {
    // Gather parameters from form or data attributes
    const form = this.operationFormTarget
    if (form) {
      return Object.fromEntries(new FormData(form))
    }
    return {}
  }

  handleOperationSuccess(result) {
    this.showSuccess(`Operation completed successfully. ${result.credits_used} credits used.`)
  }

  // Utility methods
  showSuccess(message) {
    // Implement your success notification
    const notification = document.createElement('div')
    notification.className = 'alert alert-success'
    notification.textContent = message
    document.body.appendChild(notification)
    
    setTimeout(() => notification.remove(), 3000)
  }

  showError(message) {
    // Implement your error notification
    const notification = document.createElement('div')
    notification.className = 'alert alert-danger'
    notification.textContent = message
    document.body.appendChild(notification)
    
    setTimeout(() => notification.remove(), 5000)
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
  }
}