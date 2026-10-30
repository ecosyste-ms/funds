# frozen_string_literal: true

require 'test_helper'

module Api
  module V1
    class AllocationsControllerTest < ActionDispatch::IntegrationTest
      setup do
        # a fund Django is created
        @fund = create(
          :fund,
          name: 'Django Fund',
          description: 'Django is a web application framework for Python.',
          slug: 'django',
          primary_topic: 'python',
          registry_name: 'pypi'
        )

        # 3 donation transactions to the fund
        create(
          :transaction,
          fund: @fund,
          legacy_id: '1',
          uuid: SecureRandom.uuid,
          amount: 16_875.00,
          net_amount: 16_875.00,
          transaction_type: 'CREDIT',
          transaction_kind: 'DONATION',
          currency: 'USD',
          account: 'sentry',
          account_name: 'Sentry',
          created_at: Time.zone.now
        )
        create(
          :transaction,
          fund: @fund,
          legacy_id: '2',
          uuid: SecureRandom.uuid,
          amount: 650.00,
          net_amount: 650.00,
          transaction_type: 'CREDIT',
          transaction_kind: 'DONATION',
          currency: 'USD',
          account: 'thibaudcolas',
          account_name: 'Thibaud Colas',
          created_at: Time.zone.now
        )
        create(
          :transaction,
          fund: @fund,
          legacy_id: '3',
          uuid: SecureRandom.uuid,
          amount: 51.00,
          net_amount: 51.00,
          transaction_type: 'CREDIT',
          transaction_kind: 'DONATION',
          currency: 'USD',
          account: 'chris-adams',
          account_name: 'Chris Adams',
          account_image_url: nil,
          created_at: Time.zone.now
        )

        @fs_github = create(
          :funding_source,
          url: 'https://github.com/ecosyste-ms',
          platform: 'github.com'
        )
        @fs_opencollective = create(
          :funding_source,
          url: 'https://opencollective.com/ecosystems',
          platform: 'opencollective.com'
        )

        # 3 out of 5 projects in the fund are allocated
        @project0 = create(
          :project,
          name: 'Requests',
          url: 'https://github.com/psf/requests',
          licenses: ['apache'],
          registry_names: ['pypi'],
          keywords: ['python'],
          funding_rejected: false,
          total_downloads: 100_000_000,
          total_dependent_repos: 50_000,
          total_dependent_packages: 10_000
        )
        @project1 = create(
          :project,
          name: 'Django',
          url: 'https://github.com/django/django',
          licenses: ['bsd'],
          registry_names: ['pypi'],
          keywords: ['python'],
          funding_rejected: false,
          total_downloads: 542_000_000,
          total_dependent_repos: 604_000,
          total_dependent_packages: 8_240
        )
        @project2 = create(
          :project,
          name: 'Wagtail',
          url: 'https://github.com/wagtail/wagtail',
          licenses: ['bsd'],
          registry_names: ['pypi'],
          keywords: ['python'],
          funding_rejected: false,
          total_downloads: 1_000_000,
          total_dependent_repos: 100,
          total_dependent_packages: 50
        )
        2.times do
          create(
            :project,
            registry_names: ['pypi'],
            keywords: ['python'],
            funding_rejected: false,
            total_downloads: 1_000_000,
            total_dependent_repos: 100,
            total_dependent_packages: 50
          )
        end

        @allocation = create(
          :allocation,
          fund: @fund,
          year: Time.zone.now.year,
          month: Time.zone.now.month,
          total_cents: 17_736_00,
          funded_projects_count: 1
        )

        # project allocation with no invite
        create(
          :project_allocation,
          fund: @fund,
          allocation: @allocation,
          project: @project0,
          amount_cents: 202_00,
          paid_at: Time.zone.now,
          funding_source: @fs_opencollective
        )

        # project allocation with rejected invite
        pa_rejected = create(
          :project_allocation,
          fund: @fund,
          allocation: @allocation,
          project: @project1,
          amount_cents: 201_00,
          paid_at: Time.zone.now,
          funding_source: @fs_opencollective
        )
        create(:invitation, project_allocation: pa_rejected).reject!

        # project allocation with accepted invite
        pa_accepted = create(
          :project_allocation,
          fund: @fund,
          allocation: @allocation,
          project: @project2,
          amount_cents: 101_00,
          paid_at: Time.zone.now,
          funding_source: @fs_github
        )
        inv_accepted = create(:invitation, project_allocation: pa_accepted)
        inv_accepted.accept!

        # Mocking the invitation status to approved to skip calling OC API.
        inv_accepted.update!(data: { 'status' => 'APPROVED' })

        @fund.update_stats
      end

      test 'project index matches openapi spec' do
        month_year = @allocation.created_at.strftime('%B-%Y').downcase
        get api_v1_fund_allocations_path(fund_slug: 'django', month_year: month_year)
        assert_response :success

        json = JSON.parse(response.body)
        assert_equal 'Django Fund', json['fund_name']
        assert_equal @allocation.created_at.strftime('%B-%Y'), json['allocation_month_year']

        allocation_details = json['allocation_details']
        assert_not_nil allocation_details
        assert allocation_details['total_funded_amount']['value'].positive?
        assert_equal 'USD', allocation_details['total_funded_amount']['currency']
        assert_equal 3, allocation_details['funders_count']
        assert_equal 1, allocation_details['projects_count']

        # Distribution details here include every allocated project because
        # the allocation isn't complete yet.
        distribution_details = json['distribution_details']
        assert_equal 2, distribution_details['open_collective_projects']
        assert_equal 1, distribution_details['github_sponsored_projects']
        assert_equal 0, distribution_details['other_projects']
        assert_equal 0, distribution_details['invited_projects']

        funders = json['funders']
        funder0 = funders[0]
        funder1 = funders[1]
        funder2 = funders[2]
        assert_equal 'Sentry', funder0['name']
        assert_equal 16_875.00, funder0['total_funded']['value']
        assert_equal 'USD', funder0['total_funded']['currency']
        assert funder0['profile'].end_with? 'opencollective.com/sentry'
        assert_equal 'Thibaud Colas', funder1['name']
        assert_equal 650.00, funder1['total_funded']['value']
        assert_equal 'USD', funder1['total_funded']['currency']
        assert funder1['profile'].end_with? 'opencollective.com/thibaudcolas'
        assert_equal 'Chris Adams', funder2['name']
        assert_equal 51.00, funder2['total_funded']['value']
        assert_equal 'USD', funder2['total_funded']['currency']
        assert funder2['profile'].end_with? 'opencollective.com/chris-adams'

        funding_allocations = json['funding_allocations']
        assert_equal 3, funding_allocations.length

        # Pending
        alloc0 = funding_allocations[0]
        assert_equal 'Requests', alloc0['project_name']
        assert_equal 'https://github.com/psf/requests', alloc0['project_repo_link']
        assert_equal 202.0, alloc0['allocated_amount']['value']
        assert_equal 'USD', alloc0['allocated_amount']['currency']
        assert_equal 100_000_000, alloc0['project_downloads']
        assert_equal 50_000, alloc0['project_dependent_repos']
        assert_equal 10_000, alloc0['project_dependent_packages']
        assert_equal false, alloc0['is_funding_rejected']
        assert_equal false, alloc0['is_funding_allocation_success']
        assert_equal 'https://opencollective.com/ecosystems', alloc0['project_funding_source']['url']
        assert_equal true, alloc0['project_funding_source']['is_approved']
        assert_nil alloc0['funding_invitation']

        # Rejected invite
        alloc1 = funding_allocations[1]
        assert_equal 'Django', alloc1['project_name']
        assert_equal 'https://github.com/django/django', alloc1['project_repo_link']
        assert_equal 201.0, alloc1['allocated_amount']['value']
        assert_equal 'USD', alloc1['allocated_amount']['currency']
        assert_equal 542_000_000, alloc1['project_downloads']
        assert_equal 604_000, alloc1['project_dependent_repos']
        assert_equal 8_240, alloc1['project_dependent_packages']
        assert_equal true, alloc1['is_funding_rejected']
        assert_equal false, alloc1['is_funding_allocation_success']
        assert_equal 'https://opencollective.com/ecosystems', alloc1['project_funding_source']['url']
        assert_equal true, alloc1['project_funding_source']['is_approved']
        assert_nil alloc1['funding_invitation']['invitation_accepted_at']
        assert_not_nil alloc1['funding_invitation']['invitation_rejected_at']

        # Accepted invite
        alloc2 = funding_allocations[2]
        assert_equal 'Wagtail', alloc2['project_name']
        assert_equal 'https://github.com/wagtail/wagtail', alloc2['project_repo_link']
        assert_equal 101.0, alloc2['allocated_amount']['value']
        assert_equal 'USD', alloc2['allocated_amount']['currency']
        assert_equal 1_000_000, alloc2['project_downloads']
        assert_equal 100, alloc2['project_dependent_repos']
        assert_equal 50, alloc2['project_dependent_packages']
        assert_equal false, alloc2['is_funding_rejected']
        assert_equal true, alloc2['is_funding_allocation_success']
        assert_equal 'https://github.com/ecosyste-ms', alloc2['project_funding_source']['url']
        assert_equal true, alloc2['project_funding_source']['is_approved']
        assert_not_nil alloc2['funding_invitation']['invitation_accepted_at']
        assert_nil alloc2['funding_invitation']['invitation_rejected_at']
      end

      test 'project index returns only completed funding allocations' do
        @allocation.complete!

        month_year = @allocation.created_at.strftime('%B-%Y').downcase
        get api_v1_fund_allocations_path(fund_slug: 'django', month_year: month_year)
        assert_response :success

        json = JSON.parse(response.body)
        assert_equal 'Django Fund', json['fund_name']
        assert_equal @allocation.created_at.strftime('%B-%Y'), json['allocation_month_year']

        allocation_details = json['allocation_details']
        assert_not_nil allocation_details
        assert_equal 101.0, allocation_details['total_funded_amount']['value']
        assert_equal 'USD', allocation_details['total_funded_amount']['currency']
        assert_equal 3, allocation_details['funders_count']
        assert_equal 1, allocation_details['projects_count']

        # Distribution details here include only successfully allocated projects
        # because it's a completed allocation.
        distribution_details = json['distribution_details']
        assert_equal 0, distribution_details['open_collective_projects']
        assert_equal 1, distribution_details['github_sponsored_projects']
        assert_equal 0, distribution_details['other_projects']
        assert_equal 0, distribution_details['invited_projects']

        funders = json['funders']
        funder0 = funders[0]
        funder1 = funders[1]
        funder2 = funders[2]
        assert_equal 'Sentry', funder0['name']
        assert_equal 16_875.00, funder0['total_funded']['value']
        assert_equal 'USD', funder0['total_funded']['currency']
        assert funder0['profile'].end_with? 'opencollective.com/sentry'
        assert_equal 'Thibaud Colas', funder1['name']
        assert_equal 650.00, funder1['total_funded']['value']
        assert_equal 'USD', funder1['total_funded']['currency']
        assert funder1['profile'].end_with? 'opencollective.com/thibaudcolas'
        assert_equal 'Chris Adams', funder2['name']
        assert_equal 51.00, funder2['total_funded']['value']
        assert_equal 'USD', funder2['total_funded']['currency']
        assert funder2['profile'].end_with? 'opencollective.com/chris-adams'

        funding_allocations = json['funding_allocations']
        assert_equal 1, funding_allocations.length

        alloc0 = funding_allocations[0]
        assert_equal 'Wagtail', alloc0['project_name']
        assert_equal 'https://github.com/wagtail/wagtail', alloc0['project_repo_link']
        assert_equal 101.0, alloc0['allocated_amount']['value']
        assert_equal 'USD', alloc0['allocated_amount']['currency']
        assert_equal 1_000_000, alloc0['project_downloads']
        assert_equal 100, alloc0['project_dependent_repos']
        assert_equal 50, alloc0['project_dependent_packages']
        assert_equal false, alloc0['is_funding_rejected']
        assert_equal true, alloc0['is_funding_allocation_success']
        assert_equal 'https://github.com/ecosyste-ms', alloc0['project_funding_source']['url']
        assert_equal true, alloc0['project_funding_source']['is_approved']
        assert_not_nil alloc0['funding_invitation']['invitation_accepted_at']
        assert_nil alloc0['funding_invitation']['invitation_rejected_at']
      end

      test 'project index returns null funding source when absent' do
        @allocation.project_allocations.find_by(project: @project0).update!(funding_source: nil)

        month_year = @allocation.created_at.strftime('%B-%Y').downcase
        get api_v1_fund_allocations_path(fund_slug: 'django', month_year: month_year)
        assert_response :success

        alloc = JSON.parse(response.body)['funding_allocations'].find { |a| a['project_name'] == 'Requests' }
        assert alloc.key?('project_funding_source')
        assert_nil alloc['project_funding_source']
      end

      test 'index with empty params returns not found' do
        get api_v1_fund_allocations_path(fund_slug: '', month_year: '')
        assert_response :not_found
        assert_empty response.body
      end

      test 'index with empty month_year returns bad request' do
        get api_v1_fund_allocations_path(fund_slug: 'django', month_year: '')
        assert_response :bad_request
        assert_empty response.body
      end

      test 'index with params having just whitespaces returns bad request' do
        get api_v1_fund_allocations_path(fund_slug: '     ', month_year: '     ')
        assert_response :bad_request
        assert_empty response.body
      end

      test 'index with month_year having just whitespaces returns bad request' do
        get api_v1_fund_allocations_path(fund_slug: 'django', month_year: '     ')
        assert_response :bad_request
        assert_empty response.body
      end

      test 'index with slug not matching a fund returns not found' do
        get api_v1_fund_allocations_path(fund_slug: 'non-existent-fund', month_year: 'october-2025')
        assert_response :not_found
        assert_empty response.body
      end

      test 'index with month_year not matching an allocation returns not found' do
        get api_v1_fund_allocations_path(fund_slug: 'django', month_year: 'january-2000')
        assert_response :not_found
        assert_empty response.body
      end

      test 'index with slug param exceeding 100 characters returns bad request' do
        get api_v1_fund_allocations_path(fund_slug: 'a' * 101, month_year: 'october-2025')
        assert_response :bad_request
        assert_empty response.body
      end

      test 'index with month_year param exceeding 100 characters returns bad request' do
        get api_v1_fund_allocations_path(fund_slug: 'django', month_year: 'a' * 101)
        assert_response :bad_request
        assert_empty response.body
      end

      test 'index handles hostile query strings for fund slug param' do
        get api_v1_fund_allocations_path(fund_slug: "') THEN 0 ELSE (SELECT 1) END --", month_year: 'october-2025')
        assert_response :not_found
        assert_empty response.body
      end

      test 'index handles hostile query strings for month year param' do
        get api_v1_fund_allocations_path(fund_slug: 'django', month_year: "') THEN 0 ELSE (SELECT 1) END --")
        assert_response :not_found
        assert_empty response.body
      end
    end
  end
end
