namespace :projects do
  task sync_least_recent: :environment do
    Project.sync_least_recently_synced
  end
end