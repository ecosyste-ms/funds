namespace :funding_sources do
  task sync_least_recent: :environment do
    FundingSource.sync_least_recently_synced
  end

  task update_project_allocation_funding_sources: :environment do
    ProjectAllocation.update_funding_sources
  end

  task sync_all: :environment do
    FundingSource.sync_all
  end
end