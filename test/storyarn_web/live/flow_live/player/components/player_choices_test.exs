defmodule StoryarnWeb.FlowLive.Player.Components.PlayerChoicesTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.FlowLive.Player.Components.PlayerChoices

  # =============================================================================
  # player_choices/1 rendering
  # =============================================================================

  describe "player_choices/1 in :player mode" do
    test "renders only valid responses" do
      responses = [
        %{id: "r1", text: "Accept the quest", valid: true, number: 1, has_condition: false},
        %{id: "r2", text: "Refuse politely", valid: false, number: 2, has_condition: true},
        %{id: "r3", text: "Ask for more info", valid: true, number: 3, has_condition: false}
      ]

      html =
        render_component(&PlayerChoices.player_choices/1, %{
          responses: responses,
          player_mode: :player
        })

      assert html =~ "Accept the quest"
      assert html =~ "Ask for more info"
      refute html =~ "Refuse politely"
    end

    test "renders response numbers for valid responses" do
      responses = [
        %{id: "r1", text: "Yes", valid: true, number: 1, has_condition: false},
        %{id: "r2", text: "No", valid: true, number: 2, has_condition: false}
      ]

      html =
        render_component(&PlayerChoices.player_choices/1, %{
          responses: responses,
          player_mode: :player
        })

      assert html =~ "player-response-number"
      assert html =~ ">1</span>"
      assert html =~ ">2</span>"
    end

    test "does not show condition badge in player mode" do
      responses = [
        %{id: "r1", text: "Guarded option", valid: true, number: 1, has_condition: true}
      ]

      html =
        render_component(&PlayerChoices.player_choices/1, %{
          responses: responses,
          player_mode: :player
        })

      refute html =~ "player-response-badge"
    end

    test "buttons are not disabled in player mode for valid responses" do
      responses = [
        %{id: "r1", text: "Go ahead", valid: true, number: 1, has_condition: false}
      ]

      html =
        render_component(&PlayerChoices.player_choices/1, %{
          responses: responses,
          player_mode: :player
        })

      assert html =~ "phx-click=\"choose_response\""
      assert html =~ "phx-value-id=\"r1\""
      refute html =~ "disabled"
    end

    test "renders nothing when no responses are valid" do
      responses = [
        %{id: "r1", text: "Locked", valid: false, number: 1, has_condition: true},
        %{id: "r2", text: "Also locked", valid: false, number: 2, has_condition: true}
      ]

      html =
        render_component(&PlayerChoices.player_choices/1, %{
          responses: responses,
          player_mode: :player
        })

      refute html =~ "player-choices"
      refute html =~ "Locked"
      refute html =~ "Also locked"
    end
  end

  describe "player_choices/1 in :analysis mode" do
    test "renders all responses including invalid ones" do
      responses = [
        %{id: "r1", text: "Accept the quest", valid: true, number: 1, has_condition: false},
        %{id: "r2", text: "Refuse politely", valid: false, number: 2, has_condition: true}
      ]

      html =
        render_component(&PlayerChoices.player_choices/1, %{
          responses: responses,
          player_mode: :analysis
        })

      assert html =~ "Accept the quest"
      assert html =~ "Refuse politely"
    end

    test "marks invalid responses with invalid CSS class" do
      responses = [
        %{id: "r1", text: "Valid", valid: true, number: 1, has_condition: false},
        %{id: "r2", text: "Invalid", valid: false, number: 2, has_condition: false}
      ]

      html =
        render_component(&PlayerChoices.player_choices/1, %{
          responses: responses,
          player_mode: :analysis
        })

      assert html =~ "player-response-invalid"
    end

    test "disables invalid response buttons in analysis mode" do
      responses = [
        %{id: "r1", text: "Blocked", valid: false, number: 1, has_condition: false}
      ]

      html =
        render_component(&PlayerChoices.player_choices/1, %{
          responses: responses,
          player_mode: :analysis
        })

      assert html =~ "disabled"
    end

    test "does not disable valid response buttons in analysis mode" do
      responses = [
        %{id: "r1", text: "Open", valid: true, number: 1, has_condition: false}
      ]

      html =
        render_component(&PlayerChoices.player_choices/1, %{
          responses: responses,
          player_mode: :analysis
        })

      refute html =~ "disabled"
    end

    test "shows condition badge for responses with conditions in analysis mode" do
      responses = [
        %{id: "r1", text: "Conditional", valid: true, number: 1, has_condition: true}
      ]

      html =
        render_component(&PlayerChoices.player_choices/1, %{
          responses: responses,
          player_mode: :analysis
        })

      assert html =~ "player-response-badge"
      assert html =~ "shield-question"
    end

    test "does not show condition badge for responses without conditions" do
      responses = [
        %{id: "r1", text: "Simple", valid: true, number: 1, has_condition: false}
      ]

      html =
        render_component(&PlayerChoices.player_choices/1, %{
          responses: responses,
          player_mode: :analysis
        })

      refute html =~ "player-response-badge"
    end
  end

  describe "player_choices/1 with empty responses" do
    test "renders nothing when responses list is empty in player mode" do
      html =
        render_component(&PlayerChoices.player_choices/1, %{
          responses: [],
          player_mode: :player
        })

      refute html =~ "player-choices"
    end

    test "renders nothing when responses list is empty in analysis mode" do
      html =
        render_component(&PlayerChoices.player_choices/1, %{
          responses: [],
          player_mode: :analysis
        })

      refute html =~ "player-choices"
    end
  end

  describe "player_choices/1 event attributes" do
    test "each button emits choose_response with response id" do
      responses = [
        %{id: "resp-abc", text: "First", valid: true, number: 1, has_condition: false},
        %{id: "resp-xyz", text: "Second", valid: true, number: 2, has_condition: false}
      ]

      html =
        render_component(&PlayerChoices.player_choices/1, %{
          responses: responses,
          player_mode: :player
        })

      assert html =~ "phx-value-id=\"resp-abc\""
      assert html =~ "phx-value-id=\"resp-xyz\""
    end
  end
end
