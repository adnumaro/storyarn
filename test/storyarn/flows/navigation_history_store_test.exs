defmodule Storyarn.Flows.NavigationHistoryStoreTest do
  use ExUnit.Case, async: false

  alias Storyarn.Flows.NavigationHistoryStore

  # The store is started by the application supervisor, so it's already running.
  # We just need to clean up after each test.

  setup do
    key = {System.unique_integer([:positive]), System.unique_integer([:positive])}
    on_exit(fn -> NavigationHistoryStore.clear(key) end)
    %{key: key}
  end

  describe "put/2 and get/1" do
    test "stores and retrieves history", %{key: key} do
      history = [%{flow_id: 1, node_id: 2}]
      NavigationHistoryStore.put(key, history)

      assert NavigationHistoryStore.get(key) == history
    end

    test "overwrites existing entry", %{key: key} do
      NavigationHistoryStore.put(key, [%{flow_id: 1}])
      NavigationHistoryStore.put(key, [%{flow_id: 2}])

      assert NavigationHistoryStore.get(key) == [%{flow_id: 2}]
    end

    test "returns nil for non-existent key" do
      missing_key = {-999, -999}
      assert NavigationHistoryStore.get(missing_key) == nil
    end
  end

  describe "clear/1" do
    test "removes entry for key", %{key: key} do
      NavigationHistoryStore.put(key, [%{flow_id: 1}])
      NavigationHistoryStore.clear(key)

      assert NavigationHistoryStore.get(key) == nil
    end

    test "no-op for non-existent key" do
      missing_key = {-888, -888}
      assert :ok = NavigationHistoryStore.clear(missing_key)
    end
  end

  describe "isolation" do
    test "different keys store independent histories" do
      key1 = {10001, 20001}
      key2 = {10002, 20002}

      NavigationHistoryStore.put(key1, [%{flow_id: 1}])
      NavigationHistoryStore.put(key2, [%{flow_id: 2}])

      assert NavigationHistoryStore.get(key1) == [%{flow_id: 1}]
      assert NavigationHistoryStore.get(key2) == [%{flow_id: 2}]

      NavigationHistoryStore.clear(key1)
      NavigationHistoryStore.clear(key2)
    end
  end
end
