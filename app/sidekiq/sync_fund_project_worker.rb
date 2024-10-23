class SyncFundProjectWorker
  include Sidekiq::Worker
  include Sidekiq::Status::Worker

  def perform(fund_id)
    fund = Fund.find_by_id(fund_id)
    fund.sync_opencollective_project
  end
end