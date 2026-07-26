require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test 'safe_url passes through http and https' do
    assert_equal 'http://example.com', safe_url('http://example.com')
    assert_equal 'https://github.com/foo/bar', safe_url('https://github.com/foo/bar')
  end

  test 'safe_url rejects non-web schemes' do
    assert_nil safe_url('javascript:alert(1)')
    assert_nil safe_url('data:text/html,<script>alert(1)</script>')
    assert_nil safe_url('vbscript:msgbox(1)')
  end

  test 'safe_url rejects blank and unparseable input' do
    assert_nil safe_url(nil)
    assert_nil safe_url('')
    assert_nil safe_url('not a url')
  end
end
