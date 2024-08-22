require "test_helper"

class AllocationsControllerTest < ActionDispatch::IntegrationTest
  test "should get show" do
    get fund_allocation_url(funds(:one), allocations(:one))
    assert_response :success
  end
end
