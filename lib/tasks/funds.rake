namespace :funds do
  task sync_least_recent: :environment do
    Fund.sync_least_recently_synced
  end

  task sync_transactions: :environment do
    Fund.with_project.find_each(&:sync_transactions)
  end
end