class ProjectAllocationEvent < ApplicationRecord
  belongs_to :project_allocation
  belongs_to :fund
  belongs_to :allocation
  belongs_to :invitation, optional: true

  validates :event_type, presence: true
  validates :status, inclusion: { in: %w[success error pending], allow_nil: true }

  scope :errors, -> { where(status: 'error') }
  scope :successes, -> { where(status: 'success') }
  scope :for_type, ->(type) { where(event_type: type) }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_fund, ->(fund) { where(fund: fund) }
  scope :for_allocation, ->(allocation) { where(allocation: allocation) }

  ALLOCATION_EVENTS = %w[
    allocation_created
    funding_source_assigned
    funding_source_cleared
    payout_started
    payout_osc_collective
    payout_non_osc_collective
    payout_proxy_collective
    payout_expense_invite
    payout_completed
    payout_failed
    payout_skipped
    funding_rejected
    funding_accepted
  ].freeze

  INVITATION_EVENTS = %w[
    invitation_created
    invitation_email_sent
    invitation_accepted
    invitation_rejected
    expense_created
    expense_email_sent
    expense_approved
    expense_unapproved
    expense_deleted
    expense_synced
    expense_sync_failed
  ].freeze

  ALL_EVENTS = (ALLOCATION_EVENTS + INVITATION_EVENTS).freeze

  def success?
    status == 'success'
  end

  def error?
    status == 'error'
  end

  def pending?
    status == 'pending'
  end

  def project
    project_allocation.project
  end
end
