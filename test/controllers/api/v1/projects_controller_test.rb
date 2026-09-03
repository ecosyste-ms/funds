# frozen_string_literal: true

require 'test_helper'

module Api
  module V1
    class ProjectsControllerTest < ActionDispatch::IntegrationTest
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

        # 2 out of 5 projects in the fund are allocated
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
        3.times do
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
          funded_projects_count: 2
        )
        3.times do
          create(
            :project_allocation,
            fund: @fund,
            allocation: @allocation,
            project: @project1,
            paid_at: Time.zone.now
          )
        end
        7.times do
          create(
            :project_allocation,
            fund: @fund,
            allocation: @allocation,
            project: @project2,
            paid_at: Time.zone.now
          )
        end

        @fund.update_stats
      end

      test 'project index matches openapi spec' do
        get api_v1_fund_projects_path(fund_slug: 'django')
        assert_response :success

        json = JSON.parse(response.body)
        assert_equal 2, json['projects'].length
        assert_equal 'Django Fund', json['fund_name']
        assert json['projects_count'].positive?
        assert_equal 2, json['funded_projects_count']
        assert json.key?('completed_allocations_total')
        assert_equal 1, json['current_page']
        assert_equal 1, json['total_pages']

        projects = json['projects']
        wagtail = projects[0]
        django = projects[1]
        wagtail_allocated_amt = wagtail['allocated_amount']['value']
        django_allocated_amount = django['allocated_amount']['value']

        assert_equal 'Wagtail', wagtail['name']
        assert_equal 'Django', django['name']
        assert wagtail_allocated_amt.positive?
        assert django_allocated_amount < wagtail_allocated_amt # to check descending order
        assert_equal 'https://github.com/wagtail/wagtail', wagtail['repo_link']
        assert_equal 'https://github.com/django/django', django['repo_link']
        assert_equal 1_000_000, wagtail['downloads']
        assert_equal 542_000_000, django['downloads']
        assert_equal 100, wagtail['dependent_repos']
        assert_equal 604_000, django['dependent_repos']
        assert_equal 50, wagtail['dependent_packages']
        assert_equal 8240, django['dependent_packages']
      end

      test 'index with empty slug param returns not found' do
        get api_v1_fund_projects_path(fund_slug: '')
        assert_response :not_found
        assert_empty response.body
      end

      test 'index with slug having just whitespaces returns bad request' do
        get api_v1_fund_projects_path(fund_slug: '     ')
        assert_response :bad_request
        assert_empty response.body
      end

      test 'index with slug not matching a fund returns bad request' do
        get api_v1_fund_projects_path(fund_slug: 'non-existent-fund')
        assert_response :not_found
        assert_empty response.body
      end

      test 'index with slug param exceeding 100 characters returns bad request' do
        get api_v1_fund_projects_path(fund_slug: 'a' * 101)
        assert_response :bad_request
        assert_empty response.body
      end

      test 'index with invalid page param returns bad request' do
        get api_v1_fund_projects_path(fund_slug: 'django'), params: { page: 'hello' }
        assert_response :bad_request
        assert_empty response.body

        get api_v1_fund_projects_path(fund_slug: 'django'), params: { page: -1 }
        assert_response :bad_request
        assert_empty response.body

        get api_v1_fund_projects_path(fund_slug: 'django'), params: { page: 100_001 }
        assert_response :bad_request
        assert_empty response.body
      end

      test 'index with invalid limit param returns bad request' do
        get api_v1_fund_projects_path(fund_slug: 'django'), params: { limit: 'hello' }
        assert_response :bad_request
        assert_empty response.body

        get api_v1_fund_projects_path(fund_slug: 'django'), params: { limit: -1 }
        assert_response :bad_request
        assert_empty response.body

        get api_v1_fund_projects_path(fund_slug: 'django'), params: { limit: 1001 }
        assert_response :bad_request
        assert_empty response.body
      end

      test 'index handles hostile query strings' do
        get api_v1_fund_projects_path(fund_slug: "') THEN 0 ELSE (SELECT 1) END --")
        assert_response :not_found
        assert_empty response.body
      end

      test 'index is paginated with configurable limit of 20 items per page' do
        # Allocating 42 new projects
        num_projects = 42
        test_fund = create(:fund, name: 'Test Fund', slug: 'test-fund')
        test_allocation = create(
          :allocation,
          fund: test_fund,
          year: Time.zone.now.year,
          month: Time.zone.now.month,
          total_cents: 10_499_00,
          funded_projects_count: num_projects
        )
        num_projects.times do |_i|
          project = create(
            :project,
            registry_names: ['pypi'],
            keywords: ['python'],
            funding_rejected: false,
            total_downloads: 1_000_000,
            total_dependent_repos: 100,
            total_dependent_packages: 50
          )
          create(
            :project_allocation,
            fund: test_fund,
            allocation: test_allocation,
            project: project,
            paid_at: Time.zone.now
          )
          test_fund.update_stats
        end

        slug = 'test-fund'

        # get all 42 items in single page by increasing limit
        get api_v1_fund_projects_path(fund_slug: slug), params: { page: 1, limit: 50 }
        assert_response :success
        json = JSON.parse(response.body)
        assert_equal 42, json['projects'].length
        assert_equal 1, json['current_page']
        assert_equal 1, json['total_pages']

        # page 1
        get api_v1_fund_projects_path(fund_slug: slug), params: { page: 1 }
        assert_response :success
        json = JSON.parse(response.body)
        assert_equal 20, json['projects'].length
        assert_equal 1, json['current_page']
        assert_equal 3, json['total_pages']

        # page 2 with new limit of 21 per page (page1=22, page2=20)
        get api_v1_fund_projects_path(fund_slug: slug), params: { page: 2, limit: 22 }
        assert_response :success
        json = JSON.parse(response.body)
        assert_equal 20, json['projects'].length
        assert_equal 2, json['current_page']
        assert_equal 2, json['total_pages']

        # page 3 for default limit of 20 per page (page1=20, page2=20, page3=2)
        get api_v1_fund_projects_path(fund_slug: slug), params: { page: 3 }
        assert_response :success
        json = JSON.parse(response.body)
        assert_equal 2, json['projects'].length
        assert_equal 3, json['current_page']
        assert_equal 3, json['total_pages']
      end

      test 'index returns project allocated amount converted from cents to dollars' do
        test_fund = create(:fund, name: 'Test Fund', slug: 'test-fund-cents')
        test_fund_2 = create(:fund, name: 'Test Fund 2', slug: 'test-fund-cents-2')
        test_allocation = create(
          :allocation,
          fund: test_fund,
          year: Time.zone.now.year,
          month: Time.zone.now.month,
          total_cents: 123_45,
          funded_projects_count: 1
        )
        test_allocation_2 = create(
          :allocation,
          fund: test_fund_2,
          year: Time.zone.now.year,
          month: Time.zone.now.month,
          total_cents: 678_90,
          funded_projects_count: 1
        )
        project = create(
          :project,
          registry_names: ['pypi'],
          keywords: ['python'],
          funding_rejected: false,
          total_downloads: 1_000_000,
          total_dependent_repos: 100,
          total_dependent_packages: 50
        )
        create(
          :project_allocation,
          fund: test_fund,
          allocation: test_allocation,
          project: project,
          paid_at: Time.zone.now,
          amount_cents: 123_45
        )
        create(
          :project_allocation,
          fund: test_fund_2,
          allocation: test_allocation_2,
          project: project,
          paid_at: Time.zone.now,
          amount_cents: 678_90
        )
        test_fund.update_stats
        test_fund_2.update_stats

        # project funding from test fund 1
        get api_v1_fund_projects_path(fund_slug: 'test-fund-cents')
        assert_response :success
        json = JSON.parse(response.body)
        assert_equal 123.45, json['projects'][0]['allocated_amount']['value']

        # project funding from test fund 2
        get api_v1_fund_projects_path(fund_slug: 'test-fund-cents-2')
        assert_response :success
        json = JSON.parse(response.body)
        assert_equal 678.90, json['projects'][0]['allocated_amount']['value']
      end

      test 'index orders equal totals consistently across pages' do
        test_fund = create(:fund, name: 'Stable Project Order', slug: 'stable-project-order')
        test_allocation = create(
          :allocation,
          fund: test_fund,
          year: Time.zone.now.year,
          month: Time.zone.now.month,
          total_cents: 300,
          funded_projects_count: 3
        )
        projects = 3.times.map do |index|
          project = create(:project, name: "Equal Total #{index}", funding_rejected: false)
          create(
            :project_allocation,
            fund: test_fund,
            allocation: test_allocation,
            project: project,
            paid_at: Time.zone.now,
            amount_cents: 100
          )
          project
        end

        project_names = [1, 2].flat_map do |page|
          get api_v1_fund_projects_path(fund_slug: test_fund.slug), params: { page: page, limit: 2 }
          assert_response :success
          JSON.parse(response.body)['projects'].map { |project| project['name'] }
        end

        assert_equal projects.map(&:name), project_names
      end
    end
  end
end
