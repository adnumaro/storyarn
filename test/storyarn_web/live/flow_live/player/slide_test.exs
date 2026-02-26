defmodule StoryarnWeb.FlowLive.Player.SlideTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.FlowLive.Player.Slide
  alias Storyarn.Flows.Evaluator.State

  # ---------------------------------------------------------------------------
  # Helpers — minimal structs for testing
  # ---------------------------------------------------------------------------

  defp base_state(overrides \\ %{}) do
    defaults = %State{
      variables: %{},
      pending_choices: nil,
      console: [],
      step_count: 0
    }

    Map.merge(defaults, overrides)
  end

  defp dialogue_node(data) do
    %{id: 1, type: "dialogue", data: data}
  end

  defp exit_node(data) do
    %{id: 2, type: "exit", data: data}
  end

  defp scene_node(data) do
    %{id: 3, type: "scene", data: data}
  end

  defp variable(value, initial_value \\ nil) do
    %{
      value: value,
      initial_value: initial_value || value,
      previous_value: nil,
      source: :initial,
      block_type: "number",
      block_id: 100,
      sheet_shortcut: "mc",
      variable_name: "health"
    }
  end

  # ---------------------------------------------------------------------------
  # build/4 — nil node
  # ---------------------------------------------------------------------------

  describe "build/4 with nil node" do
    test "returns empty slide" do
      assert Slide.build(nil, base_state(), %{}, 1) == %{type: :empty}
    end
  end

  # ---------------------------------------------------------------------------
  # build/4 — unknown node type
  # ---------------------------------------------------------------------------

  describe "build/4 with unknown node type" do
    test "returns empty slide for unrecognized type" do
      node = %{id: 99, type: "unknown_type", data: %{}}
      assert Slide.build(node, base_state(), %{}, 1) == %{type: :empty}
    end

    test "returns empty slide for hub type" do
      node = %{id: 99, type: "hub", data: %{}}
      assert Slide.build(node, base_state(), %{}, 1) == %{type: :empty}
    end

    test "returns empty slide for condition type" do
      node = %{id: 99, type: "condition", data: %{}}
      assert Slide.build(node, base_state(), %{}, 1) == %{type: :empty}
    end
  end

  # ---------------------------------------------------------------------------
  # build/4 — dialogue node
  # ---------------------------------------------------------------------------

  describe "build/4 with dialogue node" do
    test "returns dialogue slide with minimal data" do
      node = dialogue_node(%{})
      result = Slide.build(node, base_state(), %{}, 1)

      assert result.type == :dialogue
      assert result.node_id == 1
      assert result.speaker_name == nil
      assert result.speaker_initials == "?"
      assert result.speaker_color == nil
      assert result.text == ""
      assert result.stage_directions == ""
      assert result.menu_text == ""
      assert result.responses == []
    end

    test "returns dialogue with text content" do
      node = dialogue_node(%{"text" => "Hello world"})
      result = Slide.build(node, base_state(), %{}, 1)

      assert result.text == "Hello world"
    end

    test "handles nil data gracefully" do
      node = %{id: 1, type: "dialogue", data: nil}
      result = Slide.build(node, base_state(), %{}, 1)

      assert result.type == :dialogue
      assert result.text == ""
      assert result.speaker_name == nil
    end

    test "resolves speaker from sheets_map by integer id" do
      node = dialogue_node(%{"speaker_sheet_id" => 42})
      sheets_map = %{"42" => %{name: "Jaime", color: "#ff0000"}}

      result = Slide.build(node, base_state(), sheets_map, 1)

      assert result.speaker_name == "Jaime"
      assert result.speaker_initials == "J"
      assert result.speaker_color == "#ff0000"
    end

    test "resolves speaker from sheets_map by string id" do
      node = dialogue_node(%{"speaker_sheet_id" => "42"})
      sheets_map = %{"42" => %{name: "Jaime Torres", color: "#00ff00"}}

      result = Slide.build(node, base_state(), sheets_map, 1)

      assert result.speaker_name == "Jaime Torres"
      assert result.speaker_initials == "JT"
      assert result.speaker_color == "#00ff00"
    end

    test "returns unknown speaker when sheet_id not in map" do
      node = dialogue_node(%{"speaker_sheet_id" => 999})
      sheets_map = %{"42" => %{name: "Jaime"}}

      result = Slide.build(node, base_state(), sheets_map, 1)

      assert result.speaker_name == nil
      assert result.speaker_initials == "?"
      assert result.speaker_color == nil
    end

    test "returns unknown speaker for nil speaker_sheet_id" do
      node = dialogue_node(%{"speaker_sheet_id" => nil})

      result = Slide.build(node, base_state(), %{}, 1)

      assert result.speaker_name == nil
      assert result.speaker_initials == "?"
    end

    test "computes initials from single-word name" do
      node = dialogue_node(%{"speaker_sheet_id" => 1})
      sheets_map = %{"1" => %{name: "Narrator"}}

      result = Slide.build(node, base_state(), sheets_map, 1)

      assert result.speaker_initials == "N"
    end

    test "computes initials from multi-word name (takes first two words)" do
      node = dialogue_node(%{"speaker_sheet_id" => 1})
      sheets_map = %{"1" => %{name: "John Michael Smith"}}

      result = Slide.build(node, base_state(), sheets_map, 1)

      assert result.speaker_initials == "JM"
    end

    test "handles empty speaker name" do
      node = dialogue_node(%{"speaker_sheet_id" => 1})
      sheets_map = %{"1" => %{name: ""}}

      result = Slide.build(node, base_state(), sheets_map, 1)

      assert result.speaker_initials == "?"
    end

    test "handles nil speaker name in sheets_map" do
      node = dialogue_node(%{"speaker_sheet_id" => 1})
      sheets_map = %{"1" => %{name: nil}}

      result = Slide.build(node, base_state(), sheets_map, 1)

      assert result.speaker_initials == "?"
    end

    test "extracts stage_directions and menu_text" do
      node =
        dialogue_node(%{
          "stage_directions" => "walks slowly",
          "menu_text" => "Ask about the quest"
        })

      result = Slide.build(node, base_state(), %{}, 1)

      assert result.stage_directions == "walks slowly"
      assert result.menu_text == "Ask about the quest"
    end

    test "stage_directions defaults to empty string when missing" do
      node = dialogue_node(%{})
      result = Slide.build(node, base_state(), %{}, 1)

      assert result.stage_directions == ""
    end

    test "menu_text defaults to empty string when missing" do
      node = dialogue_node(%{})
      result = Slide.build(node, base_state(), %{}, 1)

      assert result.menu_text == ""
    end

    test "builds responses from pending_choices" do
      state =
        base_state(%{
          pending_choices: %{
            responses: [
              %{id: "r1", text: "Yes", valid: true},
              %{id: "r2", text: "No", valid: false, rule_details: [%{ref: "mc.health"}]}
            ]
          }
        })

      node = dialogue_node(%{})
      result = Slide.build(node, state, %{}, 1)

      assert length(result.responses) == 2

      [resp1, resp2] = result.responses
      assert resp1.id == "r1"
      assert resp1.text == "Yes"
      assert resp1.valid == true
      assert resp1.number == 1
      assert resp1.has_condition == false

      assert resp2.id == "r2"
      assert resp2.text == "No"
      assert resp2.valid == false
      assert resp2.number == 2
      assert resp2.has_condition == true
    end

    test "responses are empty when pending_choices is nil" do
      state = base_state(%{pending_choices: nil})
      node = dialogue_node(%{})
      result = Slide.build(node, state, %{}, 1)

      assert result.responses == []
    end

    test "responses are empty when pending_choices has no responses key" do
      state = base_state(%{pending_choices: %{something_else: true}})
      node = dialogue_node(%{})
      result = Slide.build(node, state, %{}, 1)

      assert result.responses == []
    end

    test "responses are empty when pending_choices.responses is not a list" do
      state = base_state(%{pending_choices: %{responses: "invalid"}})
      node = dialogue_node(%{})
      result = Slide.build(node, state, %{}, 1)

      assert result.responses == []
    end

    test "response with nil text defaults to empty string" do
      state =
        base_state(%{
          pending_choices: %{
            responses: [%{id: "r1", text: nil, valid: true}]
          }
        })

      node = dialogue_node(%{})
      result = Slide.build(node, state, %{}, 1)

      assert hd(result.responses).text == ""
    end

    test "response has_condition is false when rule_details is nil" do
      state =
        base_state(%{
          pending_choices: %{
            responses: [%{id: "r1", text: "Go", valid: true, rule_details: nil}]
          }
        })

      node = dialogue_node(%{})
      result = Slide.build(node, state, %{}, 1)

      assert hd(result.responses).has_condition == false
    end

    test "response has_condition is false when rule_details is empty list" do
      state =
        base_state(%{
          pending_choices: %{
            responses: [%{id: "r1", text: "Go", valid: true, rule_details: []}]
          }
        })

      node = dialogue_node(%{})
      result = Slide.build(node, state, %{}, 1)

      assert hd(result.responses).has_condition == false
    end

    test "response has_condition is true when rule_details has entries" do
      state =
        base_state(%{
          pending_choices: %{
            responses: [
              %{id: "r1", text: "Go", valid: true, rule_details: [%{ref: "x.y"}]}
            ]
          }
        })

      node = dialogue_node(%{})
      result = Slide.build(node, state, %{}, 1)

      assert hd(result.responses).has_condition == true
    end
  end

  # ---------------------------------------------------------------------------
  # build/4 — dialogue variable interpolation
  # ---------------------------------------------------------------------------

  describe "build/4 dialogue variable interpolation" do
    test "interpolates {ref} patterns in text" do
      state = base_state(%{variables: %{"mc.health" => variable(100)}})
      node = dialogue_node(%{"text" => "Health is {mc.health}"})

      result = Slide.build(node, state, %{}, 1)

      assert result.text =~ "100"
      assert result.text =~ "player-var"
    end

    test "shows unknown marker for unresolved {ref} in text" do
      state = base_state(%{variables: %{}})
      node = dialogue_node(%{"text" => "Health is {mc.health}"})

      result = Slide.build(node, state, %{}, 1)

      assert result.text =~ "player-var-unknown"
      assert result.text =~ "[mc.health]"
    end

    test "resolves variable-ref spans from Tiptap" do
      html =
        ~s(<p>Your health is <span class="variable-ref" data-ref="mc.health">$mc.health</span></p>)

      state = base_state(%{variables: %{"mc.health" => variable(75)}})
      node = dialogue_node(%{"text" => html})

      result = Slide.build(node, state, %{}, 1)

      assert result.text =~ "75"
      assert result.text =~ "player-var"
      refute result.text =~ "variable-ref"
    end

    test "resolves variable-ref span with reversed attribute order" do
      html =
        ~s(<span data-ref="mc.health" class="variable-ref">$mc.health</span>)

      state = base_state(%{variables: %{"mc.health" => variable(50)}})
      node = dialogue_node(%{"text" => html})

      result = Slide.build(node, state, %{}, 1)

      assert result.text =~ "50"
      assert result.text =~ "player-var"
    end

    test "shows unknown marker for unresolved variable-ref spans" do
      html =
        ~s(<span class="variable-ref" data-ref="mc.missing">$mc.missing</span>)

      state = base_state(%{variables: %{}})
      node = dialogue_node(%{"text" => html})

      result = Slide.build(node, state, %{}, 1)

      assert result.text =~ "player-var-unknown"
      assert result.text =~ "[mc.missing]"
    end

    test "interpolates $ref patterns in response text" do
      state =
        base_state(%{
          variables: %{"mc.health" => variable(90)},
          pending_choices: %{
            responses: [
              %{id: "r1", text: "Health: $mc.health points", valid: true}
            ]
          }
        })

      node = dialogue_node(%{})
      result = Slide.build(node, state, %{}, 1)

      assert hd(result.responses).text == "Health: 90 points"
    end

    test "shows unknown marker for unresolved $ref in response text" do
      state =
        base_state(%{
          variables: %{},
          pending_choices: %{
            responses: [
              %{id: "r1", text: "Health: $mc.health points", valid: true}
            ]
          }
        })

      node = dialogue_node(%{})
      result = Slide.build(node, state, %{}, 1)

      assert hd(result.responses).text == "Health: [$mc.health] points"
    end

    test "does not interpolate $ref without dot (e.g. $100)" do
      state =
        base_state(%{
          pending_choices: %{
            responses: [
              %{id: "r1", text: "Pay $100 to continue", valid: true}
            ]
          }
        })

      node = dialogue_node(%{})
      result = Slide.build(node, state, %{}, 1)

      assert hd(result.responses).text == "Pay $100 to continue"
    end

    test "formats boolean variable value as string" do
      state = base_state(%{variables: %{"mc.alive" => variable(true)}})
      node = dialogue_node(%{"text" => "{mc.alive}"})

      result = Slide.build(node, state, %{}, 1)
      assert result.text =~ "true"
    end

    test "formats nil variable value as 'nil'" do
      state = base_state(%{variables: %{"mc.mood" => variable(nil)}})
      node = dialogue_node(%{"text" => "{mc.mood}"})

      result = Slide.build(node, state, %{}, 1)
      assert result.text =~ "nil"
    end

    test "formats list variable value as comma-separated" do
      state = base_state(%{variables: %{"mc.tags" => variable(["brave", "kind"])}})
      node = dialogue_node(%{"text" => "{mc.tags}"})

      result = Slide.build(node, state, %{}, 1)
      assert result.text =~ "brave, kind"
    end

    test "html-escapes string variable values" do
      state = base_state(%{variables: %{"mc.name" => variable("<b>Evil</b>")}})
      node = dialogue_node(%{"text" => "{mc.name}"})

      result = Slide.build(node, state, %{}, 1)
      assert result.text =~ "&lt;b&gt;Evil&lt;/b&gt;"
      refute result.text =~ "<b>Evil</b>"
    end

    test "formats numeric variable values" do
      state = base_state(%{variables: %{"mc.level" => variable(42)}})
      node = dialogue_node(%{"text" => "{mc.level}"})

      result = Slide.build(node, state, %{}, 1)
      assert result.text =~ "42"
    end
  end

  # ---------------------------------------------------------------------------
  # build/4 — exit node
  # ---------------------------------------------------------------------------

  describe "build/4 with exit node" do
    test "returns outcome slide with minimal data" do
      node = exit_node(%{})
      result = Slide.build(node, base_state(), %{}, 1)

      assert result.type == :outcome
      assert result.node_id == 2
      assert result.label == "The End"
      assert result.outcome_color == nil
      assert result.outcome_tags == []
      assert result.step_count == 0
      assert result.variables_changed == 0
      assert result.choices_made == 0
    end

    test "uses label from data when present" do
      node = exit_node(%{"label" => "Victory"})
      result = Slide.build(node, base_state(), %{}, 1)

      assert result.label == "Victory"
    end

    test "falls back to stripped text when label is nil" do
      node = exit_node(%{"label" => nil, "text" => "<p>Game Over</p>"})
      result = Slide.build(node, base_state(), %{}, 1)

      assert result.label == "Game Over"
    end

    test "falls back to 'The End' when both label and text are nil" do
      node = exit_node(%{"label" => nil, "text" => nil})
      result = Slide.build(node, base_state(), %{}, 1)

      assert result.label == "The End"
    end

    test "handles nil data" do
      node = %{id: 2, type: "exit", data: nil}
      result = Slide.build(node, base_state(), %{}, 1)

      assert result.type == :outcome
      assert result.label == "The End"
    end

    test "preserves outcome_color" do
      node = exit_node(%{"outcome_color" => "#ff0000"})
      result = Slide.build(node, base_state(), %{}, 1)

      assert result.outcome_color == "#ff0000"
    end

    test "preserves outcome_tags" do
      node = exit_node(%{"outcome_tags" => ["good", "ending"]})
      result = Slide.build(node, base_state(), %{}, 1)

      assert result.outcome_tags == ["good", "ending"]
    end

    test "defaults outcome_tags to empty list when missing" do
      node = exit_node(%{})
      result = Slide.build(node, base_state(), %{}, 1)

      assert result.outcome_tags == []
    end

    test "counts variables that changed from initial" do
      state =
        base_state(%{
          variables: %{
            "mc.health" => %{value: 50, initial_value: 100},
            "mc.level" => %{value: 5, initial_value: 5},
            "mc.gold" => %{value: 200, initial_value: 0}
          }
        })

      node = exit_node(%{})
      result = Slide.build(node, state, %{}, 1)

      assert result.variables_changed == 2
    end

    test "counts zero variables changed when all match initial" do
      state =
        base_state(%{
          variables: %{
            "mc.health" => %{value: 100, initial_value: 100},
            "mc.level" => %{value: 1, initial_value: 1}
          }
        })

      node = exit_node(%{})
      result = Slide.build(node, state, %{}, 1)

      assert result.variables_changed == 0
    end

    test "counts choices made from console entries" do
      state =
        base_state(%{
          console: [
            %{message: "Selected: Yes"},
            %{message: "Entered dialogue node"},
            %{message: "Selected: No"},
            %{message: "Selected: Maybe"}
          ]
        })

      node = exit_node(%{})
      result = Slide.build(node, state, %{}, 1)

      assert result.choices_made == 3
    end

    test "counts zero choices when no console entries start with 'Selected:'" do
      state =
        base_state(%{
          console: [
            %{message: "Entered dialogue node"},
            %{message: "Condition evaluated: true"}
          ]
        })

      node = exit_node(%{})
      result = Slide.build(node, state, %{}, 1)

      assert result.choices_made == 0
    end

    test "uses step_count from state" do
      state = base_state(%{step_count: 15})
      node = exit_node(%{})
      result = Slide.build(node, state, %{}, 1)

      assert result.step_count == 15
    end
  end

  # ---------------------------------------------------------------------------
  # build/4 — scene node
  # ---------------------------------------------------------------------------

  describe "build/4 with scene node" do
    test "returns scene slide with minimal data" do
      node = scene_node(%{})
      result = Slide.build(node, base_state(), %{}, 1)

      assert result.type == :scene
      assert result.node_id == 3
      assert result.setting == "INT"
      assert result.location_name == ""
      assert result.sub_location == ""
      assert result.time_of_day == ""
      assert result.description == ""
    end

    test "uses setting from data" do
      node = scene_node(%{"setting" => "EXT"})
      result = Slide.build(node, base_state(), %{}, 1)

      assert result.setting == "EXT"
    end

    test "defaults setting to INT when missing" do
      node = scene_node(%{})
      result = Slide.build(node, base_state(), %{}, 1)

      assert result.setting == "INT"
    end

    test "resolves location name from sheets_map" do
      node = scene_node(%{"location_sheet_id" => 10})
      sheets_map = %{"10" => %{name: "Tavern"}}

      result = Slide.build(node, base_state(), sheets_map, 1)

      assert result.location_name == "Tavern"
    end

    test "falls back to location_name field when sheet not found" do
      node = scene_node(%{"location_sheet_id" => 999, "location_name" => "Dark Forest"})
      sheets_map = %{}

      result = Slide.build(node, base_state(), sheets_map, 1)

      # resolve_speaker returns %{name: nil, ...}, so location.name is nil,
      # then falls through to data["location_name"]
      assert result.location_name == "Dark Forest"
    end

    test "falls back to empty string when no location info" do
      node = scene_node(%{})
      result = Slide.build(node, base_state(), %{}, 1)

      assert result.location_name == ""
    end

    test "preserves sub_location" do
      node = scene_node(%{"sub_location" => "Back room"})
      result = Slide.build(node, base_state(), %{}, 1)

      assert result.sub_location == "Back room"
    end

    test "preserves time_of_day" do
      node = scene_node(%{"time_of_day" => "NIGHT"})
      result = Slide.build(node, base_state(), %{}, 1)

      assert result.time_of_day == "NIGHT"
    end

    test "interpolates variables in description" do
      state = base_state(%{variables: %{"mc.health" => variable(75)}})
      node = scene_node(%{"description" => "The hero has {mc.health} HP"})

      result = Slide.build(node, state, %{}, 1)

      assert result.description =~ "75"
      assert result.description =~ "player-var"
    end

    test "shows unknown marker for unresolved variable in description" do
      state = base_state(%{variables: %{}})
      node = scene_node(%{"description" => "Gold: {mc.gold}"})

      result = Slide.build(node, state, %{}, 1)

      assert result.description =~ "player-var-unknown"
      assert result.description =~ "[mc.gold]"
    end

    test "handles nil data" do
      node = %{id: 3, type: "scene", data: nil}
      result = Slide.build(node, base_state(), %{}, 1)

      assert result.type == :scene
      assert result.setting == "INT"
    end

    test "handles empty description" do
      node = scene_node(%{"description" => ""})
      result = Slide.build(node, base_state(), %{}, 1)

      assert result.description == ""
    end
  end

  # ---------------------------------------------------------------------------
  # build/4 — speaker resolution edge cases
  # ---------------------------------------------------------------------------

  describe "speaker resolution edge cases" do
    test "handles non-parseable string sheet_id" do
      node = dialogue_node(%{"speaker_sheet_id" => "not-a-number"})
      sheets_map = %{"not-a-number" => %{name: "Ghost"}}

      result = Slide.build(node, base_state(), sheets_map, 1)

      # parse_sheet_id returns nil for non-integer strings, so it won't match
      assert result.speaker_name == nil
      assert result.speaker_initials == "?"
    end

    test "speaker with no color in sheets_map" do
      node = dialogue_node(%{"speaker_sheet_id" => 1})
      sheets_map = %{"1" => %{name: "NPC"}}

      result = Slide.build(node, base_state(), sheets_map, 1)

      assert result.speaker_name == "NPC"
      assert result.speaker_color == nil
    end

    test "handles sheet_id as float-like string" do
      node = dialogue_node(%{"speaker_sheet_id" => "42.5"})

      result = Slide.build(node, base_state(), %{}, 1)

      # "42.5" won't parse as integer cleanly (remainder ".5")
      assert result.speaker_name == nil
      assert result.speaker_initials == "?"
    end
  end

  # ---------------------------------------------------------------------------
  # build/4 — HTML sanitization in dialogue
  # ---------------------------------------------------------------------------

  describe "HTML sanitization in dialogue" do
    test "strips script tags from text" do
      html = ~s[<p>Hello</p><script>alert('xss')</script>]
      node = dialogue_node(%{"text" => html})

      result = Slide.build(node, base_state(), %{}, 1)

      refute result.text =~ "<script>"
      assert result.text =~ "Hello"
    end

    test "preserves allowed tags" do
      html = "<p><strong>Bold</strong> and <em>italic</em></p>"
      node = dialogue_node(%{"text" => html})

      result = Slide.build(node, base_state(), %{}, 1)

      assert result.text =~ "<strong>"
      assert result.text =~ "<em>"
    end
  end

  # ---------------------------------------------------------------------------
  # build/4 — empty variables map
  # ---------------------------------------------------------------------------

  describe "build/4 with empty variables" do
    test "dialogue with empty variables and no interpolation targets" do
      state = base_state(%{variables: %{}})
      node = dialogue_node(%{"text" => "Plain text with no variables"})

      result = Slide.build(node, state, %{}, 1)

      assert result.text == "Plain text with no variables"
    end

    test "exit with empty variables reports zero changes" do
      state = base_state(%{variables: %{}, console: []})
      node = exit_node(%{})

      result = Slide.build(node, state, %{}, 1)

      assert result.variables_changed == 0
      assert result.choices_made == 0
    end
  end
end
