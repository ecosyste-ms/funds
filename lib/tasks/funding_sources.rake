namespace :funding_sources do
  task sync_least_recent: :environment do
    FundingSource.sync_least_recently_synced
  end
end