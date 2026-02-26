defmodule StoryarnWeb.FlowLive.Player.Components.PlayerSlideTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.FlowLive.Player.Components.PlayerSlide

  # =============================================================================
  # player_slide/1 — :dialogue type
  # =============================================================================

  describe "player_slide/1 dialogue type" do
    test "renders dialogue slide with speaker info and text" do
      slide = %{
        type: :dialogue,
        speaker_name: "Jaime",
        speaker_initials: "JA",
        speaker_color: "#8b5cf6",
        text: "<p>Hello, traveler!</p>",
        stage_directions: ""
      }

      html = render_component(&PlayerSlide.player_slide/1, %{slide: slide})

      assert html =~ "player-slide-dialogue"
      assert html =~ "player-speaker"
      assert html =~ "JA"
      assert html =~ "Jaime"
      assert html =~ "Hello, traveler!"
    end

    test "renders speaker avatar with color" do
      slide = %{
        type: :dialogue,
        speaker_name: "Luna",
        speaker_initials: "LU",
        speaker_color: "#22c55e",
        text: "<p>Greetings.</p>",
        stage_directions: ""
      }

      html = render_component(&PlayerSlide.player_slide/1, %{slide: slide})

      assert html =~ "player-speaker-avatar"
      assert html =~ "background-color: #22c55e"
    end

    test "renders without speaker color when nil" do
      slide = %{
        type: :dialogue,
        speaker_name: "Unknown",
        speaker_initials: "UN",
        speaker_color: nil,
        text: "<p>Who are you?</p>",
        stage_directions: ""
      }

      html = render_component(&PlayerSlide.player_slide/1, %{slide: slide})

      assert html =~ "player-speaker-avatar"
      refute html =~ "background-color:"
    end

    test "renders without speaker name when nil" do
      slide = %{
        type: :dialogue,
        speaker_name: nil,
        speaker_initials: "??",
        speaker_color: nil,
        text: "<p>Narrator text</p>",
        stage_directions: ""
      }

      html = render_component(&PlayerSlide.player_slide/1, %{slide: slide})

      assert html =~ "player-speaker-avatar"
      refute html =~ "player-speaker-name"
    end

    test "sanitizes HTML in dialogue text by stripping script tags" do
      slide = %{
        type: :dialogue,
        speaker_name: "Evil",
        speaker_initials: "EV",
        speaker_color: nil,
        text: "<p>Safe text</p><script>alert('xss')</script>",
        stage_directions: ""
      }

      html = render_component(&PlayerSlide.player_slide/1, %{slide: slide})

      assert html =~ "Safe text"
      refute html =~ "<script>"
    end

    test "sanitizes dangerous attributes from HTML in dialogue text" do
      slide = %{
        type: :dialogue,
        speaker_name: "Evil",
        speaker_initials: "EV",
        speaker_color: nil,
        text: "<p onclick=\"steal()\">Click me</p>",
        stage_directions: ""
      }

      html = render_component(&PlayerSlide.player_slide/1, %{slide: slide})

      assert html =~ "Click me"
      refute html =~ "onclick"
    end

    test "renders stage directions when present" do
      slide = %{
        type: :dialogue,
        speaker_name: "Jaime",
        speaker_initials: "JA",
        speaker_color: nil,
        text: "<p>I see...</p>",
        stage_directions: "looks away nervously"
      }

      html = render_component(&PlayerSlide.player_slide/1, %{slide: slide})

      assert html =~ "player-stage-directions"
      assert html =~ "looks away nervously"
    end

    test "does not render stage directions when empty string" do
      slide = %{
        type: :dialogue,
        speaker_name: "Jaime",
        speaker_initials: "JA",
        speaker_color: nil,
        text: "<p>Hello</p>",
        stage_directions: ""
      }

      html = render_component(&PlayerSlide.player_slide/1, %{slide: slide})

      refute html =~ "player-stage-directions"
    end

    test "preserves rich text formatting in dialogue" do
      slide = %{
        type: :dialogue,
        speaker_name: "Narrator",
        speaker_initials: "NA",
        speaker_color: nil,
        text: "<p>This is <strong>bold</strong> and <em>italic</em> text.</p>",
        stage_directions: ""
      }

      html = render_component(&PlayerSlide.player_slide/1, %{slide: slide})

      assert html =~ "<strong>bold</strong>"
      assert html =~ "<em>italic</em>"
    end
  end

  # =============================================================================
  # player_slide/1 — :scene type
  # =============================================================================

  describe "player_slide/1 scene type" do
    test "renders scene slide with setting and location" do
      slide = %{
        type: :scene,
        setting: "INT",
        location_name: "Castle Throne Room",
        sub_location: "",
        time_of_day: "",
        description: ""
      }

      html = render_component(&PlayerSlide.player_slide/1, %{slide: slide})

      assert html =~ "player-slide-scene"
      assert html =~ "player-scene-slug"
      assert html =~ "INT"
      assert html =~ "Castle Throne Room"
    end

    test "renders sub-location when present" do
      slide = %{
        type: :scene,
        setting: "EXT",
        location_name: "Village Square",
        sub_location: "Near the fountain",
        time_of_day: "",
        description: ""
      }

      html = render_component(&PlayerSlide.player_slide/1, %{slide: slide})

      assert html =~ "Near the fountain"
    end

    test "does not render sub-location when empty" do
      slide = %{
        type: :scene,
        setting: "INT",
        location_name: "Tavern",
        sub_location: "",
        time_of_day: "",
        description: ""
      }

      html = render_component(&PlayerSlide.player_slide/1, %{slide: slide})

      assert html =~ "Tavern"
      # The sub_location span should not be rendered
      refute html =~ " — </span>"
    end

    test "renders time of day in uppercase when present" do
      slide = %{
        type: :scene,
        setting: "EXT",
        location_name: "Forest Path",
        sub_location: "",
        time_of_day: "night",
        description: ""
      }

      html = render_component(&PlayerSlide.player_slide/1, %{slide: slide})

      assert html =~ "NIGHT"
    end

    test "does not render time of day when empty" do
      slide = %{
        type: :scene,
        setting: "INT",
        location_name: "Library",
        sub_location: "",
        time_of_day: "",
        description: ""
      }

      html = render_component(&PlayerSlide.player_slide/1, %{slide: slide})

      refute html =~ "NIGHT"
      refute html =~ "DAY"
    end

    test "renders scene description when present" do
      slide = %{
        type: :scene,
        setting: "EXT",
        location_name: "Beach",
        sub_location: "",
        time_of_day: "",
        description: "<p>Waves crash against the shore.</p>"
      }

      html = render_component(&PlayerSlide.player_slide/1, %{slide: slide})

      assert html =~ "player-scene-description"
      assert html =~ "Waves crash against the shore."
    end

    test "does not render description when empty" do
      slide = %{
        type: :scene,
        setting: "INT",
        location_name: "Office",
        sub_location: "",
        time_of_day: "",
        description: ""
      }

      html = render_component(&PlayerSlide.player_slide/1, %{slide: slide})

      refute html =~ "player-scene-description"
    end

    test "sanitizes HTML in scene description" do
      slide = %{
        type: :scene,
        setting: "INT",
        location_name: "Lab",
        sub_location: "",
        time_of_day: "",
        description: "<p>Normal text</p><script>bad()</script>"
      }

      html = render_component(&PlayerSlide.player_slide/1, %{slide: slide})

      assert html =~ "Normal text"
      refute html =~ "<script>"
    end

    test "renders full slug line with sub-location and time of day" do
      slide = %{
        type: :scene,
        setting: "INT",
        location_name: "Mansion",
        sub_location: "Ballroom",
        time_of_day: "evening",
        description: ""
      }

      html = render_component(&PlayerSlide.player_slide/1, %{slide: slide})

      assert html =~ "INT"
      assert html =~ "Mansion"
      assert html =~ "Ballroom"
      assert html =~ "EVENING"
    end
  end

  # =============================================================================
  # player_slide/1 — :empty type
  # =============================================================================

  describe "player_slide/1 empty type" do
    test "renders empty slide with message" do
      slide = %{type: :empty}

      html = render_component(&PlayerSlide.player_slide/1, %{slide: slide})

      assert html =~ "player-slide-empty"
    end
  end

  # =============================================================================
  # player_slide/1 — fallback (unknown type)
  # =============================================================================

  describe "player_slide/1 fallback" do
    test "renders empty div for unknown slide type" do
      slide = %{type: :unknown_type}

      html = render_component(&PlayerSlide.player_slide/1, %{slide: slide})

      assert html =~ "player-slide"
      refute html =~ "player-slide-dialogue"
      refute html =~ "player-slide-scene"
      refute html =~ "player-slide-empty"
    end

    test "renders empty div for slide with no matching type" do
      slide = %{type: :custom}

      html = render_component(&PlayerSlide.player_slide/1, %{slide: slide})

      assert html =~ "<div class=\"player-slide\">"
    end
  end
end
