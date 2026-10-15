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
end
