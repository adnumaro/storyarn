defmodule Storyarn.Flows.DebugSessionStoreTest do
  use ExUnit.Case, async: false

  alias Storyarn.Flows.DebugSessionStore

  # The store is started by the application supervision tree.
  # Use unique keys per test to avoid interference.

  describe "store/2 and take/1" do
    test "roundtrip: store then take returns the stored map" do
      key = {__MODULE__, :roundtrip}
      assigns = %{debug_state: :some_state, debug_nodes: %{1 => :node}}

      DebugSessionStore.store(key, assigns)
      result = DebugSessionStore.take(key)

      assert result == assigns
    end

    test "take returns nil for missing key" do
      assert DebugSessionStore.take({__MODULE__, :missing}) == nil
    end

    test "take removes the entry (one-shot)" do
      key = {__MODULE__, :oneshot}
      DebugSessionStore.store(key, %{data: true})

      assert DebugSessionStore.take(key) == %{data: true}
      assert DebugSessionStore.take(key) == nil
    end

    test "store overwrites existing entry" do
      key = {__MODULE__, :overwrite}
      DebugSessionStore.store(key, %{version: 1})
      DebugSessionStore.store(key, %{version: 2})

      assert DebugSessionStore.take(key) == %{version: 2}
    end
  end
end
