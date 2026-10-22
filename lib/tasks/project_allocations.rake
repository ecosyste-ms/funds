namespace :project_allocations do
  desc 'Refresh stored funded flags for existing project allocations'
  task backfill_funded: :environment do
    ProjectAllocation.find_each(&:refresh_funded!)
  end
end
