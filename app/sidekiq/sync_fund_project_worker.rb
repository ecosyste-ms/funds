class SyncFundProjectWorker
  include Sidekiq::Worker
  include Sidekiq::Status::Worker

  sidekiq_options queue: :funds

  def perform(fund_id)
    Fund.find_by_id(fund_id).try(:sync_opencollective_project)
  end
end