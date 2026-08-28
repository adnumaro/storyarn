defmodule Storyarn.Flows.PlayerOutcomeTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows

  test "builds authored outcome metadata and strips a text fallback" do
    node = %{
      id: 42,
      data: %{
        "label" => nil,
        "text" => "<p>Game <strong>Over</strong></p>",
        "outcome_color" => "#ff0000",
        "outcome_tags" => ["bad", "ending"]
      }
    }

    outcome = Flows.build_player_outcome(node, state())

    assert outcome.label == "Game Over"
    assert outcome.outcome_color == "#ff0000"
    assert outcome.outcome_tags == ["bad", "ending"]
    assert outcome.node_id == 42
  end

  test "prefers the authored label and leaves localization fallback to presentation" do
    assert Flows.build_player_outcome(%{id: 1, data: %{"label" => "Victory"}}, state()).label ==
             "Victory"

    assert Flows.build_player_outcome(%{id: 1, data: %{}}, state()).label == nil
  end

  test "computes run statistics from evaluator semantics" do
    state =
      state(%{
        step_count: 15,
        variables: %{
          "hero.health" => %{value: 50, initial_value: 100},
          "hero.level" => %{value: 5, initial_value: 5},
          "hero.gold" => %{value: 200, initial_value: 0},
          "invalid" => %{value: 1}
        },
        console: [
          %{message: "Selected: Yes"},
          %{message: "Entered dialogue node"},
          %{message: "Selected: No"},
          %{level: :info}
        ]
      })

    outcome = Flows.build_player_outcome(%{id: 1, data: %{}}, state)

    assert outcome.step_count == 15
    assert outcome.variables_changed == 2
    assert outcome.choices_made == 2
  end

  defp state(overrides \\ %{}) do
    Map.merge(%{step_count: 0, variables: %{}, console: []}, overrides)
  end
end
