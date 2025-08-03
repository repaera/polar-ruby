// app/javascript/controllers/repository_access_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "purchaseButton", "accessStatus", "repositoryList", "invitationStatus",
    "connectButton", "disconnectButton", "githubUsername", "accessExpiry",
    "packageSelect", "bulkActions"
  ]
  
  static values = {
    githubConnected: Boolean,
    githubUsername: String,
    userId: String
  }

  connect() {
    this.updateConnectionStatus()
    this.pollInvitationStatus()
    this.checkAccessExpiration()
  }

  disconnect() {
    if (this.statusPollingInterval) {
      clearInterval(this.statusPollingInterval)
    }
  }

  // GitHub connection management
  async connectGitHub() {
    window.location.href = '/auth/github'
  }

  async disconnectGitHub() {
    if (!confirm('Are you sure? This will revoke access to all repositories and cannot be undone.')) {
      return
    }

    try {
      const response = await fetch('/github/disconnect', {
        method: 'DELETE',
        headers: {
          'X-CSRF-Token': this.csrfToken
        }
      })

      if (response.ok) {
        this.githubConnectedValue = false
        this.updateConnectionStatus()
        window.location.reload()
      } else {
        throw new Error('Disconnection failed')
      }
    } catch (error) {
      this.showError('Failed to disconnect GitHub account')
    }
  }

  updateConnectionStatus() {
    const statusElements = document.querySelectorAll('.github-status')
    
    statusElements.forEach(element => {
      if (this.githubConnectedValue) {
        element.classList.add('connected')
        element.classList.remove('disconnected')
      } else {
        element.classList.add('disconnected')
        element.classList.remove('connected')
      }
    })

    // Show/hide username
    if (this.hasGithubUsernameTarget) {
      this.githubUsernameTarget.textContent = this.githubConnectedValue 
        ? `@${this.githubUsernameValue}` 
        : 'Not connected'
    }
  }

  // Repository purchasing
  async purchaseRepository(event) {
    const repositoryId = event.currentTarget.dataset.repositoryId
    const packageId = event.currentTarget.dataset.packageId
    
    if (!this.githubConnectedValue) {
      this.showGitHubConnectionRequired()
      return
    }

    const button = event.currentTarget
    button.disabled = true
    button.textContent = 'Processing...'

    try {
      const endpoint = packageId ? `/packages/${packageId}/purchase` : `/repositories/${repositoryId}/purchase`
      
      const response = await fetch(endpoint, {
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
      button.disabled = false
      button.textContent = 'Purchase Access'
    }
  }

  showGitHubConnectionRequired() {
    const modal = this.createModal('GitHub Connection Required', `
      <p>You need to connect your GitHub account before purchasing repository access.</p>
      <p>This allows us to automatically grant you access to the purchased repositories.</p>
    `, [
      { text: 'Cancel', class: 'btn-secondary', action: 'closeModal' },
      { text: 'Connect GitHub', class: 'btn-primary', action: 'connectGitHub' }
    ])
    
    document.body.appendChild(modal)
  }

  // Access management
  async checkRepositoryAccess(repositoryId) {
    try {
      const response = await fetch(`/repositories/${repositoryId}/access_status`)
      const data = await response.json()
      
      this.updateAccessStatus(repositoryId, data)
    } catch (error) {
      console.error('Failed to check access status:', error)
    }
  }

  updateAccessStatus(repositoryId, statusData) {
    const statusElement = document.querySelector(`[data-repository-id="${repositoryId}"] .access-status`)
    if (!statusElement) return
    
    const { status, expires_at, invitation_pending } = statusData
    
    let statusHtml = ''
    let statusClass = ''
    
    switch (status) {
      case 'active':
        statusHtml = `
          <span class="status-badge active">✓ Active Access</span>
          ${expires_at ? `<div class="expiry-info">Expires: ${this.formatDate(expires_at)}</div>` : ''}
        `
        statusClass = 'access-active'
        break
        
      case 'pending':
        statusHtml = `
          <span class="status-badge pending">⏳ Invitation Pending</span>
          <div class="invitation-info">Check your GitHub notifications</div>
        `
        statusClass = 'access-pending'
        break
        
      case 'expired':
        statusHtml = `
          <span class="status-badge expired">⚠️ Access Expired</span>
          <button class="btn btn-sm btn-primary" data-action="click->repository-access#renewAccess" data-repository-id="${repositoryId}">
            Renew Access
          </button>
        `
        statusClass = 'access-expired'
        break
        
      default:
        statusHtml = `
          <span class="status-badge none">No Access</span>
          <button class="btn btn-sm btn-primary" data-action="click->repository-access#purchaseRepository" data-repository-id="${repositoryId}">
            Purchase Access
          </button>
        `
        statusClass = 'access-none'
    }
    
    statusElement.innerHTML = statusHtml
    statusElement.className = `access-status ${statusClass}`
  }

  // Invitation management
  pollInvitationStatus() {
    // Check invitation status every 30 seconds
    this.statusPollingInterval = setInterval(() => {
      this.checkPendingInvitations()
    }, 30000)
    
    // Initial check
    this.checkPendingInvitations()
  }

  async checkPendingInvitations() {
    try {
      const response = await fetch('/repositories/pending_invitations')
      const data = await response.json()
      
      this.updateInvitationDisplay(data.invitations)
    } catch (error) {
      console.error('Failed to check invitations:', error)
    }
  }

  updateInvitationDisplay(invitations) {
    if (!this.hasInvitationStatusTarget) return
    
    if (invitations.length === 0) {
      this.invitationStatusTarget.classList.add('hidden')
      return
    }
    
    const invitationHtml = invitations.map(inv => `
      <div class="invitation-item">
        <div class="repo-info">
          <strong>${inv.repository_name}</strong>
          <span class="invitation-date">Invited ${this.timeAgo(inv.invited_at)}</span>
        </div>
        <div class="invitation-actions">
          <a href="${inv.github_invitation_url}" target="_blank" class="btn btn-sm btn-primary">
            Accept on GitHub
          </a>
          <button class="btn btn-sm btn-secondary" data-action="click->repository-access#refreshInvitationStatus" data-invitation-id="${inv.id}">
            Refresh
          </button>
        </div>
      </div>
    `).join('')
    
    this.invitationStatusTarget.innerHTML = `
      <div class="pending-invitations">
        <h4>Pending GitHub Invitations</h4>
        ${invitationHtml}
        <div class="invitation-help">
          <small>
            Accept these invitations on GitHub to activate your repository access.
            <a href="https://github.com/notifications" target="_blank">Check GitHub notifications</a>
          </small>
        </div>
      </div>
    `
    this.invitationStatusTarget.classList.remove('hidden')
  }

  async refreshInvitationStatus(event) {
    const invitationId = event.currentTarget.dataset.invitationId
    
    try {
      const response = await fetch(`/repositories/invitations/${invitationId}/refresh`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': this.csrfToken
        }
      })
      
      if (response.ok) {
        this.checkPendingInvitations()
      }
    } catch (error) {
      console.error('Failed to refresh invitation status:', error)
    }
  }

  // Access expiration monitoring
  checkAccessExpiration() {
    setInterval(() => {
      this.updateExpirationWarnings()
    }, 3600000) // Check every hour
    
    this.updateExpirationWarnings()
  }

  async updateExpirationWarnings() {
    try {
      const response = await fetch('/repositories/expiring_access')
      const data = await response.json()
      
      if (data.expiring_repositories.length > 0) {
        this.showExpirationWarning(data.expiring_repositories)
      }
    } catch (error) {
      console.error('Failed to check expiration status:', error)
    }
  }

  showExpirationWarning(repositories) {
    const warningHtml = repositories.map(repo => `
      <div class="expiring-repo">
        <strong>${repo.name}</strong> expires in ${repo.days_until_expiry} days
        <button class="btn btn-sm btn-primary" data-action="click->repository-access#renewAccess" data-repository-id="${repo.id}">
          Renew
        </button>
      </div>
    `).join('')
    
    const notification = document.createElement('div')
    notification.className = 'alert alert-warning expiration-warning'
    notification.innerHTML = `
      <h5>Repository Access Expiring Soon</h5>
      ${warningHtml}
    `
    
    // Show at top of page
    document.body.insertBefore(notification, document.body.firstChild)
    
    // Auto-hide after 10 seconds
    setTimeout(() => notification.remove(), 10000)
  }

  // Bulk operations
  selectAllRepositories(event) {
    const checkboxes = document.querySelectorAll('.repository-checkbox')
    checkboxes.forEach(cb => cb.checked = event.currentTarget.checked)
    
    this.updateBulkActions()
  }

  toggleRepositorySelection() {
    this.updateBulkActions()
  }

  updateBulkActions() {
    const selectedRepos = document.querySelectorAll('.repository-checkbox:checked')
    const bulkActions = this.bulkActionsTarget
    
    if (selectedRepos.length > 0) {
      bulkActions.classList.remove('hidden')
      bulkActions.querySelector('.selection-count').textContent = selectedRepos.length
    } else {
      bulkActions.classList.add('hidden')
    }
  }

  async bulkRevokeAccess() {
    const selectedRepos = Array.from(document.querySelectorAll('.repository-checkbox:checked'))
      .map(cb => cb.value)
    
    if (selectedRepos.length === 0) return
    
    if (!confirm(`Revoke access to ${selectedRepos.length} repositories?`)) return
    
    try {
      const response = await fetch('/repositories/bulk_revoke', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfToken
        },
        body: JSON.stringify({ repository_ids: selectedRepos })
      })
      
      if (response.ok) {
        window.location.reload()
      } else {
        throw new Error('Bulk revocation failed')
      }
    } catch (error) {
      this.showError('Failed to revoke access to some repositories')
    }
  }

  // Package management
  selectPackage(event) {
    const packageId = event.currentTarget.dataset.packageId
    const repositories = JSON.parse(event.currentTarget.dataset.repositories || '[]')
    
    this.highlightPackageRepositories(repositories)
    this.updatePackageDetails(packageId)
  }

  highlightPackageRepositories(repositoryIds) {
    document.querySelectorAll('.repository-card').forEach(card => {
      const repoId = card.dataset.repositoryId
      if (repositoryIds.includes(parseInt(repoId))) {
        card.classList.add('included-in-package')
      } else {
        card.classList.remove('included-in-package')
      }
    })
  }

  async updatePackageDetails(packageId) {
    try {
      const response = await fetch(`/packages/${packageId}/details`)
      const data = await response.json()
      
      const detailsElement = document.getElementById('package-details')
      if (detailsElement) {
        detailsElement.innerHTML = this.renderPackageDetails(data)
      }
    } catch (error) {
      console.error('Failed to load package details:', error)
    }
  }

  renderPackageDetails(packageData) {
    return `
      <div class="package-info">
        <h3>${packageData.name}</h3>
        <p>${packageData.description}</p>
        <div class="package-stats">
          <span class="repo-count">${packageData.repository_count} repositories</span>
          <span class="price">${packageData.formatted_price}</span>
        </div>
        <div class="package-features">
          ${packageData.features.map(feature => `<span class="feature-tag">${feature}</span>`).join('')}
        </div>
      </div>
    `
  }

  // Utility methods
  createModal(title, body, buttons = []) {
    const modal = document.createElement('div')
    modal.className = 'modal show'
    
    const buttonHtml = buttons.map(btn => 
      `<button type="button" class="btn ${btn.class}" data-action="click->repository-access#${btn.action}">
        ${btn.text}
      </button>`
    ).join('')
    
    modal.innerHTML = `
      <div class="modal-dialog">
        <div class="modal-content">
          <div class="modal-header">
            <h5>${title}</h5>
          </div>
          <div class="modal-body">${body}</div>
          <div class="modal-footer">${buttonHtml}</div>
        </div>
      </div>
    `
    
    return modal
  }

  closeModal(event) {
    const modal = event.currentTarget.closest('.modal')
    if (modal) {
      modal.remove()
    }
  }

  formatDate(dateString) {
    return new Date(dateString).toLocaleDateString()
  }

  timeAgo(dateString) {
    const date = new Date(dateString)
    const now = new Date()
    const diffInHours = Math.floor((now - date) / (1000 * 60 * 60))
    
    if (diffInHours < 1) return 'less than an hour ago'
    if (diffInHours < 24) return `${diffInHours} hours ago`
    
    const diffInDays = Math.floor(diffInHours / 24)
    if (diffInDays < 7) return `${diffInDays} days ago`
    
    return date.toLocaleDateString()
  }

  showError(message) {
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