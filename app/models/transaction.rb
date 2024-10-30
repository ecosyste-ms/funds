class Transaction < ApplicationRecord
  belongs_to :fund
  validates :uuid, uniqueness: true

  counter_culture :fund, execute_after_commit: true

  scope :donations, -> { where(transaction_type: 'CREDIT') }
  scope :expenses, -> { where(transaction_type: 'DEBIT') }
  scope :host_fees, -> { where(transaction_kind: ['PAYMENT_PROCESSOR_FEE', 'PAYMENT_PROCESSOR_COVER', 'HOST_FEE'])}
  scope :not_host_fees, -> { where.not(transaction_kind: ['PAYMENT_PROCESSOR_FEE', 'PAYMENT_PROCESSOR_COVER', 'HOST_FEE'])}  
end
