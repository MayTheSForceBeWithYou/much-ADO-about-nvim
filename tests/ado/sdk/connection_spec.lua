-- Tests for ado.sdk connection module

describe('Connection', function()
  local sdk

  before_each(function()
    for key, _ in pairs(package.loaded) do
      if key:match('^ado%.sdk') then
        package.loaded[key] = nil
      end
    end
    sdk = require('ado.sdk')
  end)

  it('creates connection with factory function', function()
    local conn = sdk.new('https://dev.azure.com/myorg', sdk.auth.pat('test-token'))
    assert.is_not_nil(conn)
  end)

  it('lazily creates CoreApi (same instance)', function()
    local conn = sdk.new('https://dev.azure.com/myorg', sdk.auth.pat('test-token'))
    local core1 = conn:get_core_api()
    local core2 = conn:get_core_api()
    assert.equals(core1, core2)
  end)

  it('lazily creates WorkItemTrackingApi (same instance)', function()
    local conn = sdk.new('https://dev.azure.com/myorg', sdk.auth.pat('test-token'))
    local wit1 = conn:get_work_item_tracking_api()
    local wit2 = conn:get_work_item_tracking_api()
    assert.equals(wit1, wit2)
  end)

  it('creates different instances for different clients', function()
    local conn = sdk.new('https://dev.azure.com/myorg', sdk.auth.pat('test-token'))
    local core = conn:get_core_api()
    local wit = conn:get_work_item_tracking_api()
    assert.are_not.equals(core, wit)
  end)

  it('exposes rest client', function()
    local conn = sdk.new('https://dev.azure.com/myorg', sdk.auth.pat('test-token'))
    local rest = conn:get_rest_client()
    assert.is_not_nil(rest)
    assert.equals('7.0', rest:get_api_version())
  end)

  it('passes custom options through', function()
    local conn = sdk.new('https://dev.azure.com/myorg', sdk.auth.pat('t'), { api_version = '7.1' })
    assert.equals('7.1', conn:get_rest_client():get_api_version())
  end)

  it('exposes auth on module', function()
    assert.is_not_nil(sdk.auth)
    assert.is_function(sdk.auth.pat)
  end)
end)
