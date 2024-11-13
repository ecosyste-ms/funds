class FundingSourceWorker
  include Sidekiq::Worker
  include Sidekiq::Status::Worker

  sidekiq_options unique: :until_executed

  def perform(funding_source_id)
    FundingSource.find_by_id(funding_source_id).try(:sync)
  end
end