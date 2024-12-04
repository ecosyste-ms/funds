class Transaction < ApplicationRecord
  belongs_to :fund
  validates :uuid, uniqueness: true

  counter_culture :fund, execute_after_commit: true

  scope :donations, -> { where(transaction_type: 'CREDIT') }
  scope :expenses, -> { where(transaction_type: 'DEBIT') }
  scope :host_fees, -> { where(transaction_kind: ['PAYMENT_PROCESSOR_FEE', 'PAYMENT_PROCESSOR_COVER', 'HOST_FEE'])}
  scope :not_host_fees, -> { where.not(transaction_kind: ['PAYMENT_PROCESSOR_FEE', 'PAYMENT_PROCESSOR_COVER', 'HOST_FEE'])}  

  scope :created_after, ->(date) { where('transactions.created_at > ?', date) }
  scope :created_before, ->(date) { where('transactions.created_at < ?', date) }
  scope :between, ->(start_date, end_date) { where('transactions.created_at > ?', start_date).where('transactions.created_at < ?', end_date) }

  def html_url
    return unless order.present?

    if transaction_kind == 'CONTRIBUTION'
      "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}/#{fund.oc_project_slug}/contributions/#{order['legacyId']}"  
    elsif transaction_kind == 'BALANCE_TRANSFER'
      "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}/#{account}/contributions/#{order['legacyId']}"  
    elsif transaction_kind == 'EXPENSE' 
      "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}/#{account}/expenses/#{order['legacyId']}"  
    else
      nil
    end
    
  end
end
