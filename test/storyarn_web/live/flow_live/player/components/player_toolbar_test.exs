defmodule StoryarnWeb.FlowLive.Player.Components.PlayerToolbarTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.FlowLive.Player.Components.PlayerToolbar

  defp default_assigns(overrides \\ %{}) do
    Map.merge(
      %{
        can_go_back: false,
        show_continue: false,
        player_mode: :player,
        is_finished: false,
        workspace: %{slug: "test-ws"},
        project: %{slug: "test-proj"},
        flow: %{id: "flow-001"}
      },
      overrides
    )
  end

  # =============================================================================
  # player_toolbar/1 basic rendering
  # =============================================================================

  describe "player_toolbar/1 basic structure" do
    test "renders toolbar with left, center, and right sections" do
      html = render_component(&PlayerToolbar.player_toolbar/1, default_assigns())

      assert html =~ "player-toolbar"
      assert html =~ "player-toolbar-left"
      assert html =~ "player-toolbar-center"
      assert html =~ "player-toolbar-right"
    end
  end

  # =============================================================================
  # Go back button
  # =============================================================================

  describe "player_toolbar/1 go_back button" do
    test "renders go_back button disabled when can_go_back is false" do
      html =
        render_component(&PlayerToolbar.player_toolbar/1, default_assigns(%{can_go_back: false}))

      assert html =~ "phx-click=\"go_back\""
      assert html =~ "disabled"
    end

    test "renders go_back button enabled when can_go_back is true" do
      html =
        render_component(&PlayerToolbar.player_toolbar/1, default_assigns(%{can_go_back: true}))

      assert html =~ "phx-click=\"go_back\""
      # Parse the go_back button specifically - it should not be disabled
      # We check the button element that contains go_back does not have disabled
      [go_back_section | _] = String.split(html, "phx-click=\"continue\"")
      assert go_back_section =~ "phx-click=\"go_back\""
      refute go_back_section =~ "disabled"
    end

    test "go_back button has arrow-left icon" do
      html = render_component(&PlayerToolbar.player_toolbar/1, default_assigns())

      assert html =~ "arrow-left"
    end
  end

  # =============================================================================
  # Continue button
  # =============================================================================

  describe "player_toolbar/1 continue button" do
    test "shows continue button when show_continue is true and not finished" do
      html =
        render_component(
          &PlayerToolbar.player_toolbar/1,
          default_assigns(%{show_continue: true, is_finished: false})
        )

      assert html =~ "phx-click=\"continue\""
      assert html =~ "arrow-right"
    end

    test "hides continue button when show_continue is false" do
      html =
        render_component(
          &PlayerToolbar.player_toolbar/1,
          default_assigns(%{show_continue: false, is_finished: false})
        )

      refute html =~ "phx-click=\"continue\""
    end

    test "hides continue button when is_finished is true even if show_continue is true" do
      html =
        render_component(
          &PlayerToolbar.player_toolbar/1,
          default_assigns(%{show_continue: true, is_finished: true})
        )

      refute html =~ "phx-click=\"continue\""
    end

    test "continue button has primary styling" do
      html =
        render_component(
          &PlayerToolbar.player_toolbar/1,
          default_assigns(%{show_continue: true, is_finished: false})
        )

      assert html =~ "player-toolbar-btn-primary"
    end
  end

  # =============================================================================
  # Mode toggle
  # =============================================================================

  describe "player_toolbar/1 mode toggle" do
    test "shows player mode with eye icon when in player mode" do
      html =
        render_component(
          &PlayerToolbar.player_toolbar/1,
          default_assigns(%{player_mode: :player})
        )

      assert html =~ "phx-click=\"toggle_mode\""
      assert html =~ "eye"
      # Should NOT have the active class
      refute html =~ "player-toolbar-btn-active"
    end

    test "shows analysis mode with scan-eye icon when in analysis mode" do
      html =
        render_component(
          &PlayerToolbar.player_toolbar/1,
          default_assigns(%{player_mode: :analysis})
        )

      assert html =~ "phx-click=\"toggle_mode\""
      assert html =~ "scan-eye"
      assert html =~ "player-toolbar-btn-active"
    end

    test "mode toggle has mode styling class" do
      html = render_component(&PlayerToolbar.player_toolbar/1, default_assigns())

      assert html =~ "player-toolbar-btn-mode"
    end
  end

  # =============================================================================
  # Restart button
  # =============================================================================

  describe "player_toolbar/1 restart button" do
    test "renders restart button" do
      html = render_component(&PlayerToolbar.player_toolbar/1, default_assigns())

      assert html =~ "phx-click=\"restart\""
      assert html =~ "rotate-ccw"
    end
  end

  # =============================================================================
  # Back to editor link
  # =============================================================================

  describe "player_toolbar/1 back to editor link" do
    test "renders link with correct route" do
      html =
        render_component(
          &PlayerToolbar.player_toolbar/1,
          default_assigns(%{
            workspace: %{slug: "my-ws"},
            project: %{slug: "my-proj"},
            flow: %{id: "flow-xyz"}
          })
        )

      assert html =~ "/workspaces/my-ws/projects/my-proj/flows/flow-xyz"
    end

    test "renders close icon (x)" do
      html = render_component(&PlayerToolbar.player_toolbar/1, default_assigns())

      # The back-to-editor link has the "x" icon rendered as an SVG with lucide-x class
      assert html =~ "lucide-x"
    end
  end

  # =============================================================================
  # Combined scenarios
  # =============================================================================

  describe "player_toolbar/1 combined states" do
    test "full toolbar in analysis mode with continue and go_back" do
      html =
        render_component(
          &PlayerToolbar.player_toolbar/1,
          default_assigns(%{
            can_go_back: true,
            show_continue: true,
            player_mode: :analysis,
            is_finished: false
          })
        )

      # All buttons present
      assert html =~ "phx-click=\"go_back\""
      assert html =~ "phx-click=\"continue\""
      assert html =~ "phx-click=\"toggle_mode\""
      assert html =~ "phx-click=\"restart\""
      assert html =~ "scan-eye"
      assert html =~ "player-toolbar-btn-active"
    end

    test "minimal toolbar when finished with nothing to go back to" do
      html =
        render_component(
          &PlayerToolbar.player_toolbar/1,
          default_assigns(%{
            can_go_back: false,
            show_continue: false,
            player_mode: :player,
            is_finished: true
          })
        )

      # go_back is present but disabled
      assert html =~ "phx-click=\"go_back\""
      assert html =~ "disabled"
      # continue is hidden
      refute html =~ "phx-click=\"continue\""
      # restart and close are always present
      assert html =~ "phx-click=\"restart\""
    end
  end
end
