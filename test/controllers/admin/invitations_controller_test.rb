require "test_helper"

class Admin::InvitationsControllerTest < ActionDispatch::IntegrationTest
  test "index renders stored funding links without http requests" do
    project = create(:project, repository: { 'metadata' => { 'funding' => { 'github' => 'someone' } } }, funding_links: ['https://github.com/sponsors/someone'])
    project_allocation = create(:project_allocation, project: project)
    create(:invitation, project_allocation: project_allocation)

    get admin_invitations_url

    assert_response :success
    assert_select "span[title='https://github.com/sponsors/someone']"
  end
end
