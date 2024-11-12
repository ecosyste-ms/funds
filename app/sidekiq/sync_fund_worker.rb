class SyncFundWorker
  include Sidekiq::Worker

  sidekiq_options queue: :funds

  def perform(fund_id)
    Fund.find_by_id(fund_id).try(:sync)
  end
end