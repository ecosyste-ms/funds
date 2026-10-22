require 'test_helper'
require 'rake'

class ProjectAllocationsTaskTest < ActiveSupport::TestCase
  test 'backfill restores existing funded flags and can be rerun' do
    paid = create(:project_allocation, paid_at: Time.current)
    pending = create(:project_allocation, paid_at: Time.current)
    create(:invitation, project_allocation: pending, status: 'DRAFT')
    allocation = create(:allocation)
    first, second = Array.new(2) { create(:project_allocation, allocation: allocation) }
    create(:invitation, project_allocation: first, member_invitation_id: 'shared', status: 'APPROVED',
      data: { 'aggregated_allocation_ids' => [first.id, second.id] })
    ProjectAllocation.where(id: [paid.id, pending.id, first.id, second.id]).update_all(funded: false)
    pending.update_column(:funded, true)

    Rails.application.load_tasks unless Rake::Task.task_defined?('project_allocations:backfill_funded')
    task = Rake::Task['project_allocations:backfill_funded']
    2.times do
      task.reenable
      task.invoke
      assert paid.reload.funded?
      assert_not pending.reload.funded?
      assert first.reload.funded?
      assert second.reload.funded?
    end
  end
end
