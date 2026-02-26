defmodule StoryarnWeb.FlowLive.Player.Components.PlayerOutcomeTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.FlowLive.Player.Components.PlayerOutcome

  defp build_slide(overrides \\ %{}) do
    Map.merge(
      %{
        label: "Game Over",
        outcome_color: "#ff0000",
        outcome_tags: ["bad ending", "death"],
        step_count: 12,
        choices_made: 5,
        variables_changed: 3
      },
      overrides
    )
  end

  defp build_workspace, do: %{slug: "my-workspace"}
  defp build_project, do: %{slug: "my-project"}
  defp build_flow, do: %{id: "flow-123"}

  # =============================================================================
  # player_outcome/1 rendering
  # =============================================================================

  describe "player_outcome/1 basic rendering" do
    test "renders outcome slide with title" do
      html =
        render_component(&PlayerOutcome.player_outcome/1, %{
          slide: build_slide(),
          workspace: build_workspace(),
          project: build_project(),
          flow: build_flow()
        })

      assert html =~ "player-slide-outcome"
      assert html =~ "Game Over"
    end

    test "renders outcome color accent bar" do
      html =
        render_component(&PlayerOutcome.player_outcome/1, %{
          slide: build_slide(%{outcome_color: "#22c55e"}),
          workspace: build_workspace(),
          project: build_project(),
          flow: build_flow()
        })

      assert html =~ "player-outcome-accent"
      assert html =~ "background-color: #22c55e"
    end

    test "renders without accent color when outcome_color is nil" do
      html =
        render_component(&PlayerOutcome.player_outcome/1, %{
          slide: build_slide(%{outcome_color: nil}),
          workspace: build_workspace(),
          project: build_project(),
          flow: build_flow()
        })

      assert html =~ "player-outcome-accent"
      refute html =~ "background-color:"
    end
  end

  describe "player_outcome/1 tags" do
    test "renders outcome tags" do
      html =
        render_component(&PlayerOutcome.player_outcome/1, %{
          slide: build_slide(%{outcome_tags: ["victory", "heroic"]}),
          workspace: build_workspace(),
          project: build_project(),
          flow: build_flow()
        })

      assert html =~ "player-outcome-tags"
      assert html =~ "victory"
      assert html =~ "heroic"
    end

    test "does not render tags section when outcome_tags is empty" do
      html =
        render_component(&PlayerOutcome.player_outcome/1, %{
          slide: build_slide(%{outcome_tags: []}),
          workspace: build_workspace(),
          project: build_project(),
          flow: build_flow()
        })

      refute html =~ "player-outcome-tags"
    end
  end

  describe "player_outcome/1 stats" do
    test "renders step count stat" do
      html =
        render_component(&PlayerOutcome.player_outcome/1, %{
          slide: build_slide(%{step_count: 42}),
          workspace: build_workspace(),
          project: build_project(),
          flow: build_flow()
        })

      assert html =~ "player-outcome-stats"
      assert html =~ "footprints"
      assert html =~ "42"
    end

    test "renders choices made stat" do
      html =
        render_component(&PlayerOutcome.player_outcome/1, %{
          slide: build_slide(%{choices_made: 7}),
          workspace: build_workspace(),
          project: build_project(),
          flow: build_flow()
        })

      assert html =~ "mouse-pointer-click"
      assert html =~ "7"
    end

    test "renders variables changed stat" do
      html =
        render_component(&PlayerOutcome.player_outcome/1, %{
          slide: build_slide(%{variables_changed: 15}),
          workspace: build_workspace(),
          project: build_project(),
          flow: build_flow()
        })

      assert html =~ "15"
    end

    test "renders zero stats correctly" do
      html =
        render_component(&PlayerOutcome.player_outcome/1, %{
          slide: build_slide(%{step_count: 0, choices_made: 0, variables_changed: 0}),
          workspace: build_workspace(),
          project: build_project(),
          flow: build_flow()
        })

      assert html =~ "player-outcome-stats"
    end
  end

  describe "player_outcome/1 actions" do
    test "renders restart button" do
      html =
        render_component(&PlayerOutcome.player_outcome/1, %{
          slide: build_slide(),
          workspace: build_workspace(),
          project: build_project(),
          flow: build_flow()
        })

      assert html =~ "player-outcome-actions"
      assert html =~ "phx-click=\"restart\""
      assert html =~ "rotate-ccw"
    end

    test "renders back to editor link with correct path" do
      html =
        render_component(&PlayerOutcome.player_outcome/1, %{
          slide: build_slide(),
          workspace: %{slug: "ws-test"},
          project: %{slug: "proj-test"},
          flow: %{id: "flow-abc"}
        })

      assert html =~ "/workspaces/ws-test/projects/proj-test/flows/flow-abc"
      assert html =~ "arrow-left"
    end
  end
end
