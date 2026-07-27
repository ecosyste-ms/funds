require "test_helper"

class FactoriesTest < ActiveSupport::TestCase
  test "all factories are valid" do
    assert_nothing_raised { FactoryBot.lint }
  end

  test "factories with unique constraints support create_list" do
    assert_equal 25, create_list(:fund, 25).count
    assert_equal 25, create_list(:project, 25).count
    assert_equal 25, create_list(:transaction, 25).count
  end
end
