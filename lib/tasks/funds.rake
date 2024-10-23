namespace :funds do
  task sync_least_recent: :environment do
    Fund.sync_least_recently_synced
  end
end