-- Tests for ado.state module

describe('state', function()
  local state

  before_each(function()
    -- Clear module cache to get fresh state
    package.loaded['ado.state'] = nil
    state = require('ado.state')
    state.reset()
  end)

  describe('reset', function()
    it('initializes all fields to default values', function()
      state.set('org_url', 'https://example.com')
      state.set('project', 'TestProject')

      state.reset()

      assert.is_nil(state.get('org_url'))
      assert.is_nil(state.get('project'))
      assert.is_nil(state.get('projects'))
      assert.is_nil(state.get('work_items'))
      assert.is_nil(state.get('selected_work_item'))
      assert.equals(0, state.get('request_seq'))
      assert.is_false(state.get('loading'))
    end)
  end)

  describe('get/set', function()
    it('stores and retrieves values', function()
      state.set('org_url', 'https://dev.azure.com/myorg')
      assert.equals('https://dev.azure.com/myorg', state.get('org_url'))
    end)

    it('returns nil for unset keys', function()
      assert.is_nil(state.get('nonexistent_key'))
    end)

    it('handles table values', function()
      local items = { { id = 1 }, { id = 2 } }
      state.set('work_items', items)
      assert.same(items, state.get('work_items'))
    end)
  end)

  describe('request sequencing', function()
    it('starts at sequence 0', function()
      assert.equals(0, state.get('request_seq'))
    end)

    it('increments sequence on next_request_seq', function()
      local seq1 = state.next_request_seq()
      assert.equals(1, seq1)

      local seq2 = state.next_request_seq()
      assert.equals(2, seq2)
    end)

    it('correctly identifies current sequence', function()
      local seq1 = state.next_request_seq()
      assert.is_true(state.is_current_seq(seq1))

      local seq2 = state.next_request_seq()
      assert.is_false(state.is_current_seq(seq1))
      assert.is_true(state.is_current_seq(seq2))
    end)
  end)

  describe('loading state', function()
    it('starts not loading', function()
      assert.is_false(state.is_loading())
    end)

    it('tracks loading state', function()
      state.set_loading(true)
      assert.is_true(state.is_loading())

      state.set_loading(false)
      assert.is_false(state.is_loading())
    end)
  end)

  describe('subscribe', function()
    it('returns an unsubscribe function', function()
      local unsub = state.subscribe('work_items', function() end)
      assert.is_function(unsub)
    end)
  end)
end)
