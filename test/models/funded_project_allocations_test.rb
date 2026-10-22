require 'test_helper'

class FundedProjectAllocationsTest < ActiveSupport::TestCase
  test 'funded allocations use the effective expense status even when paid_at is set' do
    project = create(:project)
    fund = create(:fund)
    allocation = create(:allocation, fund: fund)
    cases = [
      ['APPROVED', 'PENDING', nil, true],
      ['PAID', 'PENDING', nil, true],
      ['DRAFT', 'PAID', nil, true],
      [nil, 'APPROVED', nil, true],
      ['', 'PAID', nil, true],
      ['DRAFT', 'PENDING', nil, false],
      ['PENDING', 'PAID', nil, false],
      ['REJECTED', 'PAID', nil, false],
      ['DELETED', 'DRAFT', nil, false],
      ['PAID', 'PAID', Time.current, false],
      ['DRAFT', nil, nil, false],
      [nil, nil, nil, false]
    ]
    expected = cases.filter_map do |status, snapshot, deleted_at, funded|
      pa = create(:project_allocation, project: project, fund: fund, allocation: allocation, paid_at: Time.current)
      create(:invitation, project_allocation: pa, member_invitation_id: "expense-#{pa.id}",
        status: status, data: { 'status' => snapshot }, deleted_at: deleted_at)
      assert_equal funded, pa.reload.funded?
      pa.id if funded
    end

    assert_equal expected.sort, project.project_allocations.funded.order(:id).pluck(:id)
    project.update!(funding_rejected: true)
    assert_empty project.project_allocations.funded
  end

  test 'latest expense takes precedence over older expenses and local invitations' do
    pa = create(:project_allocation, paid_at: Time.current)
    create(:invitation, project_allocation: pa, member_invitation_id: 'older', status: 'PAID')
    latest = create(:invitation, project_allocation: pa, member_invitation_id: 'newer', status: 'DELETED')
    create(:invitation, project_allocation: pa)

    assert_empty ProjectAllocation.where(id: pa.id).funded
    latest.update!(status: 'APPROVED')
    assert_equal [pa.id], ProjectAllocation.where(id: pa.id).funded.pluck(:id)
  end

  test 'shared expense status governs each allocation without multiplying amounts' do
    fund = create(:fund)
    allocation = create(:allocation, fund: fund)
    source = create(:funding_source)
    first = create(:project_allocation, fund: fund, allocation: allocation, funding_source: source,
      paid_at: Time.current, amount_cents: 1200)
    second = create(:project_allocation, fund: fund, allocation: allocation, funding_source: source,
      paid_at: Time.current, amount_cents: 3400)
    create(:invitation, project_allocation: second)
    invitation = create(:invitation, project_allocation: first, member_invitation_id: 'shared', status: 'APPROVED',
      data: { 'status' => 'PENDING', 'aggregated_allocation_ids' => [first.id, second.id] })

    assert_equal 4600, fund.project_allocations.funded.sum(:amount_cents)
    assert_equal 1200, first.project.total_funded
    assert_equal 3400, second.project.total_funded

    invitation.update!(status: 'REJECTED')
    assert_equal 0, fund.project_allocations.funded.sum(:amount_cents)
    invitation.update!(status: 'PAID', deleted_at: Time.current)
    assert_equal 0, fund.project_allocations.funded.sum(:amount_cents)
  end

  test 'shared expenses cannot supply status to an allocation in another round' do
    pa = create(:project_allocation, paid_at: Time.current)
    unrelated = create(:project_allocation)
    create(:invitation, project_allocation: unrelated, member_invitation_id: 'unrelated', status: 'DELETED',
      data: { 'aggregated_allocation_ids' => [pa.id] })

    assert_equal [pa.id], ProjectAllocation.where(id: pa.id).funded.pluck(:id)
  end

  test 'paid at changes refresh the flag while invitations take precedence' do
    pa = create(:project_allocation)
    assert_not pa.reload.funded?

    pa.update!(paid_at: Time.current)
    assert pa.reload.funded?
    pa.update!(paid_at: nil)
    assert_not pa.reload.funded?

    create(:invitation, project_allocation: pa, status: 'DRAFT')
    pa.update!(paid_at: Time.current)
    assert_not pa.reload.funded?
  end

  test 'changing shared expense members refreshes both old and new members' do
    allocation = create(:allocation)
    first, second, third = Array.new(3) { create(:project_allocation, allocation: allocation) }
    invitation = create(:invitation, project_allocation: first, member_invitation_id: 'shared', status: 'PAID',
      data: { 'aggregated_allocation_ids' => [first.id, second.id] })
    assert first.reload.funded?
    assert second.reload.funded?
    assert_not third.reload.funded?

    invitation.update!(data: { 'aggregated_allocation_ids' => [first.id, third.id] })
    assert first.reload.funded?
    assert_not second.reload.funded?
    assert third.reload.funded?
  end

  test 'snapshot status changes and soft deletion refresh stored flags' do
    pa = create(:project_allocation)
    invitation = create(:invitation, project_allocation: pa, status: 'DRAFT', data: { 'status' => 'PAID' })
    assert pa.reload.funded?

    invitation.update!(data: { 'status' => 'PENDING' })
    assert_not pa.reload.funded?
    invitation.update!(data: { 'status' => 'APPROVED' })
    assert pa.reload.funded?
    invitation.update!(deleted_at: Time.current)
    assert_not pa.reload.funded?
  end

  test 'destroying the latest invitation restores the previous expense or paid at fallback' do
    pa = create(:project_allocation, paid_at: Time.current)
    older = create(:invitation, project_allocation: pa, member_invitation_id: 'older', status: 'PAID')
    latest = create(:invitation, project_allocation: pa, member_invitation_id: 'latest', status: 'REJECTED')
    assert_not pa.reload.funded?

    latest.destroy!
    assert pa.reload.funded?
    older.update!(status: 'PENDING')
    assert_not pa.reload.funded?
    older.destroy!
    assert pa.reload.funded?
  end

  test 'moving an invitation refreshes its old and new allocations' do
    first = create(:project_allocation)
    second = create(:project_allocation)
    invitation = create(:invitation, project_allocation: first, status: 'PAID')
    assert first.reload.funded?
    assert_not second.reload.funded?

    invitation.update!(project_allocation: second)
    assert_not first.reload.funded?
    assert second.reload.funded?
  end

  test 'expense id changes refresh invitation precedence' do
    pa = create(:project_allocation)
    older = create(:invitation, project_allocation: pa, member_invitation_id: 'older', status: 'PAID')
    create(:invitation, project_allocation: pa, status: 'PENDING')
    assert pa.reload.funded?

    older.update!(member_invitation_id: nil)
    assert_not pa.reload.funded?
  end
end
