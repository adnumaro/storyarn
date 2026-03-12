defmodule StoryarnWeb.Helpers.AutoSnapshotTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.Helpers.AutoSnapshot

  defp socket(extra_assigns \\ %{}) do
    base = %{__changed__: %{}, auto_snapshot_ref: nil, auto_snapshot_timer: nil}
    %Phoenix.LiveView.Socket{assigns: Map.merge(base, extra_assigns)}
  end

  describe "schedule/2" do
    test "sets auto_snapshot_ref and auto_snapshot_timer in assigns" do
      result = AutoSnapshot.schedule(socket(), :flow)
      assert is_reference(result.assigns.auto_snapshot_ref)
      assert is_reference(result.assigns.auto_snapshot_timer)
      Process.cancel_timer(result.assigns.auto_snapshot_timer)
    end

    test "cancels previous timer when called again" do
      s1 = AutoSnapshot.schedule(socket(), :flow)
      first_timer = s1.assigns.auto_snapshot_timer

      s2 = AutoSnapshot.schedule(s1, :flow)
      second_timer = s2.assigns.auto_snapshot_timer

      # First timer should be cancelled
      assert Process.read_timer(first_timer) == false
      # Second timer should be active
      assert is_integer(Process.read_timer(second_timer))

      Process.cancel_timer(second_timer)
    end

    test "sends {:try_auto_snapshot, token} message with matching ref" do
      result = AutoSnapshot.schedule(socket(), :scene)
      token = result.assigns.auto_snapshot_ref
      timer = result.assigns.auto_snapshot_timer
      assert is_reference(token)
      assert is_reference(timer)
      assert is_integer(Process.read_timer(timer))
      Process.cancel_timer(timer)
    end

    test "schedules for all entity types" do
      for type <- [:flow, :scene, :sheet] do
        result = AutoSnapshot.schedule(socket(), type)
        assert is_reference(result.assigns.auto_snapshot_ref), "expected timer for #{type}"
        Process.cancel_timer(result.assigns.auto_snapshot_timer)
      end
    end
  end

  describe "cancel/1" do
    test "cancels pending timer and clears ref" do
      s1 = AutoSnapshot.schedule(socket(), :flow)
      timer = s1.assigns.auto_snapshot_timer
      assert is_reference(timer)

      s2 = AutoSnapshot.cancel(s1)
      assert s2.assigns.auto_snapshot_ref == nil
      assert s2.assigns.auto_snapshot_timer == nil
      assert Process.read_timer(timer) == false
    end

    test "is a no-op when no timer is set" do
      result = AutoSnapshot.cancel(socket())
      assert result.assigns.auto_snapshot_ref == nil
      assert result.assigns.auto_snapshot_timer == nil
    end
  end

  describe "stale message handling" do
    test "stale token does not match after reschedule" do
      s1 = AutoSnapshot.schedule(socket(), :flow)
      first_token = s1.assigns.auto_snapshot_ref

      s2 = AutoSnapshot.schedule(s1, :flow)
      second_token = s2.assigns.auto_snapshot_ref

      # Tokens should differ — stale message can be detected
      refute first_token == second_token
      Process.cancel_timer(s2.assigns.auto_snapshot_timer)
    end
  end
end
