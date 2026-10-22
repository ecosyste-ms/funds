require 'test_helper'

class ProjectContactsTest < ActiveSupport::TestCase
  test 'candidates preserve identity namespaces and package provenance' do
    project = build(:project, owner: { 'login' => 'websockets', 'email' => 'owner@example.com' }, packages: [
      { 'name' => '@someone/ws', 'registry' => { 'name' => 'npmjs.org' }, 'maintainers' => [
        { 'login' => 'lpinca', 'email' => 'package@example.com' }
      ] }
    ], commits: { 'committers' => [
      { 'name' => 'Luigi Pinca', 'login' => 'lpinca', 'email' => 'luigi@example.com', 'count' => 762 }
    ] })

    candidates = project.contact_candidates

    assert_includes candidates, { email: 'owner@example.com', source: 'owner', login: 'websockets', identity_host: 'github.com' }
    assert_includes candidates, { email: 'package@example.com', source: 'package_maintainer', login: 'lpinca', identity_host: 'npmjs.org', package: '@someone/ws' }
    assert_includes candidates, { email: 'luigi@example.com', source: 'committer', login: 'lpinca', identity_host: 'github.com' }
  end

  test 'named recipient matches GitHub evidence ahead of the repository owner and package order' do
    project = build(:project, owner: { 'login' => 'websockets', 'email' => 'einar@example.com' }, packages: [
      { 'name' => '@someone/ws', 'maintainers' => [{ 'login' => 'someone', 'email' => 'someone@example.com' }] },
      { 'name' => 'ws', 'maintainers' => [{ 'login' => 'lpinca', 'email' => 'package@example.com' }] }
    ], commits: { 'committers' => [
      { 'name' => 'Luigi Pinca', 'login' => 'lpinca', 'email' => 'luigi@example.com', 'count' => 762 },
      { 'name' => 'Einar', 'login' => 'einaros', 'email' => 'einar@example.com', 'count' => 391 }
    ] })

    assert_equal 'luigi@example.com', project.contact_email(recipient_url: 'https://github.com/sponsors/LPINCA/')
    project.packages.reverse!
    assert_equal 'luigi@example.com', project.contact_email(recipient_url: 'https://github.com/lpinca')
  end

  test 'registry login alone cannot establish a GitHub recipient identity' do
    project = build(:project, owner: nil, packages: [
      { 'name' => '@module-federation/vite', 'registry' => { 'name' => 'npmjs.org' }, 'maintainers' => [
        { 'login' => 'gioboa', 'email' => 'candidate@example.com' }
      ] }
    ])

    assert_nil project.contact_email(recipient_url: 'https://github.com/sponsors/gioboa')
    assert_equal ['candidate@example.com'], project.contact_candidates.map { |c| c[:email] }
  end

  test 'a top contributor without a matched identity is still a candidate' do
    project = build(:project, owner: nil, commits: { 'committers' => [
      { 'name' => 'Felix', 'login' => nil, 'email' => 'felix@example.com', 'count' => 166 },
      { 'name' => 'JohnTitor', 'login' => nil, 'email' => 'other@example.com', 'count' => 10 }
    ] })

    assert_nil project.contact_email(recipient_url: 'https://github.com/sponsors/JohnTitor')
  end

  test 'two addresses for one matched identity require confirmation' do
    project = build(:project, owner: { 'login' => 'example', 'email' => 'new@example.com' }, commits: {
      'committers' => [{ 'name' => 'Example', 'login' => 'example', 'email' => 'old@example.com', 'count' => 20 }]
    })

    assert_nil project.contact_email(recipient_url: 'https://github.com/sponsors/example')
  end

  test 'matching candidates do not depend on contributor rank' do
    project = build(:project, owner: nil, commits: { 'committers' => [
      { 'name' => 'Other', 'login' => 'other', 'email' => 'other@example.com', 'count' => 100 },
      { 'name' => 'Another', 'login' => 'another', 'email' => 'another@example.com', 'count' => 90 },
      { 'name' => 'Third', 'login' => 'third', 'email' => 'third@example.com', 'count' => 80 },
      { 'name' => 'Recipient', 'login' => 'recipient', 'email' => 'recipient@example.com', 'count' => 1 }
    ] })

    assert_equal 'recipient@example.com', project.contact_email(recipient_url: 'https://github.com/sponsors/recipient')
  end

  test 'multiple package and commit contacts for an unnamed recipient remain unresolved' do
    project = build(:project, owner: nil, packages: [
      { 'name' => '@someone/project', 'maintainers' => [{ 'email' => 'one@example.com' }] },
      { 'name' => 'project', 'maintainers' => [{ 'email' => 'two@example.com' }] }
    ])

    assert_nil project.contact_email
    project.packages.reverse!
    assert_nil project.contact_email
  end

  test 'an unnamed project can use its owner contact or a single distinct candidate' do
    project = build(:project, owner: { 'email' => 'team@example.com' }, packages: [
      { 'name' => 'project', 'maintainers' => [{ 'email' => 'maintainer@example.com' }] }
    ])
    assert_equal 'team@example.com', project.contact_email

    project.owner = nil
    assert_equal 'maintainer@example.com', project.contact_email
  end

  test 'case variants of the same address do not create ambiguity' do
    project = build(:project, owner: nil, packages: [
      { 'name' => 'project', 'maintainers' => [{ 'email' => 'Person@example.com ' }, { 'email' => 'person@example.com' }] }
    ])

    assert_equal 'person@example.com', project.contact_email&.downcase
  end

  test 'invalid bot and no reply addresses are excluded from every source' do
    project = build(:project, owner: { 'email' => 'noreply@github.com' }, packages: [
      { 'name' => 'project', 'maintainers' => [{ 'email' => 'invalid' }, { 'email' => 'user@localhost' }] },
      { 'name' => 'empty', 'maintainers' => nil }
    ], commits: { 'committers' => [
      { 'name' => 'SomeBot[bot]', 'login' => 'somebot', 'email' => 'bot@example.com', 'count' => 20 },
      { 'name' => 'Person', 'login' => 'person', 'email' => 'person@example.com', 'count' => 10 }
    ] })

    assert_equal ['person@example.com'], project.contact_candidates.map { |c| c[:email] }
    assert_equal 'person@example.com', project.contact_email
  end

  test 'a collective or another platform does not identify a contact email' do
    project = build(:project, owner: { 'login' => 'someone', 'email' => 'someone@example.com' })

    assert_nil project.contact_email(recipient_url: 'https://opencollective.com/example')
    assert_nil project.contact_email(recipient_url: 'https://patreon.com/example')
    assert_nil project.contact_email(recipient_url: 'https://github.com.evil.example/sponsors/someone')
  end

  test 'confirmed addresses are scoped to the recipient and survive indexing updates' do
    project = create(:project, owner: nil)
    recipient = 'https://github.com/sponsors/gioboa'

    project.confirm_contact_email!('giorgio@example.com', recipient_url: recipient)
    project.update!(packages: [{ 'name' => 'other', 'maintainers' => [{ 'email' => 'other@example.com' }] }])

    assert_equal 'giorgio@example.com', project.reload.contact_email(recipient_url: recipient.upcase + '/')
    assert_nil project.contact_email(recipient_url: 'https://github.com/sponsors/someone-else')
  end

  test 'confirmation rejects missing or invalid addresses' do
    project = create(:project)

    assert_raises(ActiveRecord::RecordInvalid) { project.confirm_contact_email!('bad-address') }
    assert_raises(ActiveRecord::RecordInvalid) { project.confirm_contact_email!('') }
  end

  test 'default recipient uses the stored funding source without fetching funding links' do
    source = create(:funding_source, platform: 'github.com', url: 'https://github.com/sponsors/example')
    project = create(:project, funding_source: source, owner: { 'login' => 'example', 'email' => 'example@example.com' })
    project.expects(:preferred_funding_link).never

    assert_equal source.url, project.contact_recipient_url
    assert_equal 'example@example.com', project.contact_email
  end

  test 'a confirmation for one recipient does not follow a funding source change' do
    source = create(:funding_source, platform: 'github.com', url: 'https://github.com/sponsors/first')
    project = create(:project, funding_source: source, owner: nil)
    project.confirm_contact_email!('confirmed@example.com')
    source.update!(url: 'https://github.com/sponsors/second')

    assert_nil project.reload.contact_email
  end
end
