defmodule Storyarn.Analytics.AllowlistFailClosedTest do
  @moduledoc """
  The allowlist in `@event_property_keys` is the only thing standing between the
  codebase and a story-content leak into PostHog. Its guarantee is that it fails
  CLOSED: an event nobody declared is dropped before the adapter is reached, and
  a property nobody declared is stripped before the event is sent.

  Observing that guarantee needs care. An adapter that raises when reached proves
  nothing here: `safe_apply/3` rescues everything and answers `:ok`, deliberately,
  so analytics can never break a request. A raising adapter is therefore
  indistinguishable from a dropped event — a mutant that removed the allowlist
  check entirely still passed such a test.

  What does work: a recording adapter. Every non-PostHog adapter is applied
  synchronously (`dispatch_with_adapter/3` falls through to `safe_apply/3` with no
  task), so by the time `track/3` returns, a dispatched event has already reached
  the adapter. `refute_receive` with a zero timeout is then an exact observation,
  not a race. Both directions are pinned below, and the mutant check is recorded
  in the PR notes.

  This is also what makes deleting the twelve orphaned `"flow analysis *"` /
  `"flow explanation *"` contracts safe, and what makes leaving them in unsafe:
  while a name is listed, a stray emit *succeeds* and ships dead
  `rule_id`/`rule_version`/`category` vocabulary.
  """
  use ExUnit.Case, async: false

  alias Storyarn.Accounts.User
  alias Storyarn.Analytics

  # The contracts removed with the structural-analysis panel and the AI
  # explanation feature. Nothing emits them; nothing may re-declare them without
  # an emitter.
  @removed_events [
    "flow analysis run",
    "flow analysis finding dismissed",
    "flow analysis finding restored",
    "flow analysis evidence navigated",
    "flow explanation preflight shown",
    "flow explanation preflight blocked",
    "flow explanation stale rerun",
    "flow explanation route selected",
    "flow explanation execution started",
    "flow explanation result viewed",
    "flow explanation detached",
    "flow explanation failed"
  ]

  defmodule RecordingAdapter do
    @moduledoc false
    def capture(payload) do
      send(Process.get(:analytics_test_pid), {:analytics_capture, payload})
      :ok
    end

    def identify(payload) do
      send(Process.get(:analytics_test_pid), {:analytics_identify, payload})
      :ok
    end
  end

  setup do
    original_adapter = Application.get_env(:storyarn, :analytics_adapter)
    Process.put(:analytics_test_pid, self())

    on_exit(fn ->
      case original_adapter do
        nil -> Application.delete_env(:storyarn, :analytics_adapter)
        adapter -> Application.put_env(:storyarn, :analytics_adapter, adapter)
      end

      Process.delete(:analytics_test_pid)
    end)
  end

  defp use_adapter(module), do: Application.put_env(:storyarn, :analytics_adapter, module)

  describe "an undeclared event never reaches the adapter" do
    setup do
      use_adapter(RecordingAdapter)
    end

    test "track/3 drops it and answers :ok" do
      assert Analytics.track(%User{id: 42}, "an event nobody declared", %{project_id: 7}) == :ok
      refute_received {:analytics_capture, _payload}
    end

    test "track_system/2 drops it and answers :ok" do
      assert Analytics.track_system("an event nobody declared", %{project_id: 7}) == :ok
      refute_received {:analytics_capture, _payload}
    end

    test "the drop is by name, not by payload — an empty payload is dropped too" do
      assert Analytics.track(%User{id: 42}, "an event nobody declared", %{}) == :ok
      refute_received {:analytics_capture, _payload}
    end

    test "every removed flow-analysis and flow-explanation contract is dropped" do
      for event <- @removed_events do
        assert Analytics.track(%User{id: 42}, event, %{rule_id: "unreachable_node", rule_version: 1}) == :ok
        assert Analytics.track_system(event, %{category: "structure"}) == :ok

        refute_received {:analytics_capture, %{event: ^event}},
                        "#{inspect(event)} is still allowlisted; a stray emit would ship dead vocabulary"
      end
    end
  end

  describe "a declared event keeps only its declared properties" do
    setup do
      use_adapter(RecordingAdapter)
    end

    test "undeclared keys are stripped, declared keys survive" do
      Analytics.track(%User{id: 42}, "palette opened", %{
        surface: "flow",
        rule_id: "unreachable_node",
        query: "the player betrays the king",
        email: "owner@example.com"
      })

      assert_receive {:analytics_capture, %{event: "palette opened", properties: properties}}

      assert properties == %{"surface" => "flow"},
             "the allowlist is an exact set, not a denylist of known-bad keys"
    end

    test "an event declared with properties still sends when given none" do
      Analytics.track(%User{id: 42}, "palette opened", %{})

      assert_receive {:analytics_capture, %{event: "palette opened", properties: %{}}}
    end

    test "the harness itself can observe a capture (positive control)" do
      Analytics.track(%User{id: 42}, "workspace created", %{workspace_id: 3})

      assert_receive {:analytics_capture, %{event: "workspace created", properties: %{"workspace_id" => 3}}}
    end
  end
end
