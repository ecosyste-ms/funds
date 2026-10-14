# frozen_string_literal: true

require 'test_helper'

module Api
  module V1
    class FundersControllerTest < ActionDispatch::IntegrationTest
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
        create(
          :transaction,
          fund: @fund,
          legacy_id: '4',
          uuid: SecureRandom.uuid,
          amount: 50.00,
          net_amount: 50.00,
          transaction_type: 'CREDIT',
          transaction_kind: 'DONATION',
          currency: 'USD',
          account: 'chris-adams',
          account_name: 'Chris Adams',
          account_image_url: nil,
          created_at: Time.zone.now
        )
      end

      test 'funder index matches openapi spec' do
        get api_v1_fund_funders_path(fund_slug: 'django')
        assert_response :success

        json = JSON.parse(response.body)
        assert_equal 3, json['funders'].length
        assert_equal 'Django Fund', json['fund_name']
        assert_equal 3, json['total_funders_count']
        assert_equal 1, json['repeat_funders_count']
        assert_equal 2, json['one_time_funders_count']
        assert_equal 1, json['current_page']
        assert_equal 1, json['total_pages']

        funders = json['funders']
        funder0 = funders[0]
        funder1 = funders[1]
        funder2 = funders[2]

        assert_equal 'Sentry', funder0['name']
        assert_equal 16_875.00, funder0['total_funded']['value']
        assert_equal 'USD', funder0['total_funded']['currency']
        assert_equal 1, funder0['donations_count']
        assert funder0['profile'].end_with? 'opencollective.com/sentry'

        assert_equal 'Thibaud Colas', funder1['name']
        assert_equal 650.00, funder1['total_funded']['value']
        assert_equal 'USD', funder1['total_funded']['currency']
        assert_equal 1, funder1['donations_count']
        assert funder1['profile'].end_with? 'opencollective.com/thibaudcolas'

        assert_equal 'Chris Adams', funder2['name']
        assert_equal 101.00, funder2['total_funded']['value']
        assert_equal 'USD', funder2['total_funded']['currency']
        assert_equal 2, funder2['donations_count']
        assert funder2['profile'].end_with? 'opencollective.com/chris-adams'
      end

      test 'index with empty slug param returns not found' do
        get api_v1_fund_funders_path(fund_slug: '')
        assert_response :not_found
        assert_empty response.body
      end

      test 'index with slug having just whitespaces returns bad request' do
        get api_v1_fund_funders_path(fund_slug: '     ')
        assert_response :bad_request
        assert_empty response.body
      end

      test 'index with slug not matching a fund returns not found' do
        get api_v1_fund_funders_path(fund_slug: 'non-existent-fund')
        assert_response :not_found
        assert_empty response.body
      end

      test 'index with slug param exceeding 100 characters returns bad request' do
        get api_v1_fund_funders_path(fund_slug: 'a' * 101)
        assert_response :bad_request
        assert_empty response.body
      end

      test 'index with invalid page param returns bad request' do
        get api_v1_fund_funders_path(fund_slug: 'django'), params: { page: 'hello' }
        assert_response :bad_request
        assert_empty response.body

        get api_v1_fund_funders_path(fund_slug: 'django'), params: { page: -1 }
        assert_response :bad_request
        assert_empty response.body

        get api_v1_fund_funders_path(fund_slug: 'django'), params: { page: 100_001 }
        assert_response :bad_request
        assert_empty response.body
      end

      test 'index with invalid limit param returns bad request' do
        get api_v1_fund_funders_path(fund_slug: 'django'), params: { limit: 'hello' }
        assert_response :bad_request
        assert_empty response.body

        get api_v1_fund_funders_path(fund_slug: 'django'), params: { limit: -1 }
        assert_response :bad_request
        assert_empty response.body

        get api_v1_fund_funders_path(fund_slug: 'django'), params: { limit: 1001 }
        assert_response :bad_request
        assert_empty response.body
      end

      test 'index handles hostile query strings' do
        get api_v1_fund_funders_path(fund_slug: "') THEN 0 ELSE (SELECT 1) END --")
        assert_response :not_found
        assert_empty response.body
      end

      test 'index is paginated with configurable limit of 20 items per page' do
        # Allocating 55 new funders
        num_funders = 55
        test_fund = create(:fund, name: 'Test Fund', slug: 'test-fund')
        num_funders.times do |i|
          create(
            :transaction,
            fund: test_fund,
            uuid: SecureRandom.uuid,
            amount: 1000 - i,
            net_amount: 1000 - i,
            transaction_type: 'CREDIT',
            transaction_kind: 'DONATION',
            currency: 'USD',
            account: "test_funder_#{i + 1}",
            account_name: "Test Funder #{i + 1}",
            created_at: Time.zone.now
          )
        end

        slug = 'test-fund'

        # get all 55 items in single page by increasing limit
        get api_v1_fund_funders_path(fund_slug: slug), params: { page: 1, limit: 55 }
        assert_response :success
        json = JSON.parse(response.body)
        assert_equal 55, json['funders'].length
        assert_equal 1, json['current_page']
        assert_equal 1, json['total_pages']
        assert_equal 'Test Funder 1', json['funders'][0]['name']
        assert_equal 'Test Funder 55', json['funders'][54]['name']

        # page 1
        get api_v1_fund_funders_path(fund_slug: slug), params: { page: 1 }
        assert_response :success
        json = JSON.parse(response.body)
        assert_equal 20, json['funders'].length
        assert_equal 1, json['current_page']
        assert_equal 3, json['total_pages']
        assert_equal 'Test Funder 1', json['funders'][0]['name']
        assert_equal 'Test Funder 20', json['funders'][19]['name']

        # page 2 with new limit of 30 per page (page1=30, page2=25)
        get api_v1_fund_funders_path(fund_slug: slug), params: { page: 2, limit: 30 }
        assert_response :success
        json = JSON.parse(response.body)
        assert_equal 25, json['funders'].length
        assert_equal 2, json['current_page']
        assert_equal 2, json['total_pages']
        assert_equal 'Test Funder 31', json['funders'][0]['name']
        assert_equal 'Test Funder 55', json['funders'][24]['name']

        # page 3 for default limit of 20 per page (page1=20, page2=20, page3=15)
        get api_v1_fund_funders_path(fund_slug: slug), params: { page: 3 }
        assert_response :success
        json = JSON.parse(response.body)
        assert_equal 15, json['funders'].length
        assert_equal 3, json['current_page']
        assert_equal 3, json['total_pages']
        assert_equal 'Test Funder 41', json['funders'][0]['name']
        assert_equal 'Test Funder 55', json['funders'][14]['name']
      end
    end
  end
end
