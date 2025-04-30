namespace :funds do
  task sync_least_recent: :environment do
    Fund.sync_least_recently_synced
  end

  task sync_transactions: :environment do
    Fund.with_project.find_each(&:sync_transactions)
  end

  task run_allocations: :environment do
    Fund.all.find_each(&:allocate_to_projects)
    Allocation.not_completed.find_each(&:send_invitations)
  end

  task payout: :environment do
    Allocation.not_completed.find_each(&:payout)
    AllocationMailer.github_sponsors_csv("benjam@opencollective.com").deliver_now
  end

  task complete_allocations: :environment do
    Invitation.delete_expired
    Allocation.not_completed.each(&:complete!)
  end
end