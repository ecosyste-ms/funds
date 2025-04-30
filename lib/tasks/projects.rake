namespace :projects do
  task sync_least_recent: :environment do
    Project.sync_least_recently_synced
  end

  task sync_projects_with_allocations: :environment do
    Project.sync_projects_with_allocations
  end
end