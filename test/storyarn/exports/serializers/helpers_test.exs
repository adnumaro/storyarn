defmodule Storyarn.Exports.Serializers.HelpersTest do
  use ExUnit.Case, async: true

  alias Storyarn.Exports.Serializers.Helpers

  # ===========================================================================
  # collect_variables
  # ===========================================================================

  describe "collect_variables/1" do
    test "extracts variables from sheets, skipping constants" do
      sheets = [
        %{
          shortcut: "mc.jaime",
          blocks: [
            %{
              variable_name: "health",
              is_constant: false,
              type: "number",
              value: %{"number" => 100}
            },
            %{variable_name: "name", is_constant: true, type: "text", value: %{"text" => "Jaime"}}
          ]
        }
      ]

      vars = Helpers.collect_variables(sheets)
      assert length(vars) == 1
      assert hd(vars).full_ref == "mc.jaime.health"
      assert hd(vars).type == :number
    end

    test "returns empty list for nil or non-list" do
      assert Helpers.collect_variables(nil) == []
      assert Helpers.collect_variables("not a list") == []
    end

    test "skips blocks with empty variable_name" do
      sheets = [
        %{
          shortcut: "npc",
          blocks: [
            %{variable_name: "", is_constant: false, type: "text", value: %{}},
            %{variable_name: nil, is_constant: false, type: "text", value: %{}}
          ]
        }
      ]

      assert Helpers.collect_variables(sheets) == []
    end

    test "collects from multiple sheets" do
      sheets = [
        %{
          shortcut: "a",
          blocks: [
            %{variable_name: "x", is_constant: false, type: "number", value: %{"number" => 1}}
          ]
        },
        %{
          shortcut: "b",
          blocks: [
            %{
              variable_name: "y",
              is_constant: false,
              type: "boolean",
              value: %{"boolean" => true}
            }
          ]
        }
      ]

      vars = Helpers.collect_variables(sheets)
      assert length(vars) == 2
      refs = Enum.map(vars, & &1.full_ref)
      assert "a.x" in refs
      assert "b.y" in refs
    end
  end

  # ===========================================================================
  # infer_variable_type
  # ===========================================================================

  describe "infer_variable_type/1" do
    test "maps block types to engine types" do
      assert Helpers.infer_variable_type(%{type: "number"}) == :number
      assert Helpers.infer_variable_type(%{type: "boolean"}) == :boolean
      assert Helpers.infer_variable_type(%{type: "text"}) == :string
      assert Helpers.infer_variable_type(%{type: "rich_text"}) == :string
      assert Helpers.infer_variable_type(%{type: "select"}) == :string
      assert Helpers.infer_variable_type(%{type: "multi_select"}) == :string
      assert Helpers.infer_variable_type(%{type: "date"}) == :string
    end

    test "defaults to string for unknown types" do
      assert Helpers.infer_variable_type(%{type: "custom"}) == :string
    end
  end

  # ===========================================================================
  # infer_default_value
  # ===========================================================================

  describe "infer_default_value/1" do
    test "returns number default" do
      assert Helpers.infer_default_value(%{type: "number", value: %{"number" => 42}}) == 42
      assert Helpers.infer_default_value(%{type: "number", value: %{}}) == 0
    end

    test "returns boolean default" do
      assert Helpers.infer_default_value(%{type: "boolean", value: %{"boolean" => true}}) == true
      assert Helpers.infer_default_value(%{type: "boolean", value: %{}}) == false
    end

    test "returns string default for text types" do
      assert Helpers.infer_default_value(%{type: "text", value: %{"text" => "hi"}}) == "hi"
    end

    test "strips HTML from rich_text default" do
      assert Helpers.infer_default_value(%{
               type: "rich_text",
               value: %{"rich_text" => "<p>hi</p>"}
             }) ==
               "hi"
    end

    test "returns empty string for unknown types" do
      assert Helpers.infer_default_value(%{type: "unknown_type", value: %{}}) == ""
    end
  end

  # ===========================================================================
  # strip_html
  # ===========================================================================

  describe "strip_html/1" do
    test "strips tags and decodes entities" do
      assert Helpers.strip_html("<p>Hello <strong>world</strong></p>") == "Hello world"
      assert Helpers.strip_html("plain text") == "plain text"
      assert Helpers.strip_html("&amp; &lt; &gt;") == "& < >"
      assert Helpers.strip_html("&quot;quoted&quot;") == "\"quoted\""
      assert Helpers.strip_html("&#39;apos&#39;") == "'apos'"
      assert Helpers.strip_html("word&nbsp;space") == "word space"
    end

    test "converts br and p tags to newlines" do
      assert Helpers.strip_html("a<br>b") == "a\nb"
      assert Helpers.strip_html("<p>a</p><p>b</p>") == "a\nb"
    end

    test "handles nil and empty string" do
      assert Helpers.strip_html(nil) == ""
      assert Helpers.strip_html("") == ""
    end
  end

  # ===========================================================================
  # shortcut_to_identifier
  # ===========================================================================

  describe "shortcut_to_identifier/1" do
    test "converts dots and hyphens to underscores" do
      assert Helpers.shortcut_to_identifier("mc.jaime") == "mc_jaime"
      assert Helpers.shortcut_to_identifier("a-b.c") == "a_b_c"
    end

    test "handles nil and empty string" do
      assert Helpers.shortcut_to_identifier(nil) == ""
      assert Helpers.shortcut_to_identifier("") == ""
    end

    test "preserves alphanumeric and underscores" do
      assert Helpers.shortcut_to_identifier("abc_123") == "abc_123"
    end
  end

  # ===========================================================================
  # escape_csv_field
  # ===========================================================================

  describe "escape_csv_field/1" do
    test "returns empty string for nil" do
      assert Helpers.escape_csv_field(nil) == ""
    end

    test "converts numbers to string" do
      assert Helpers.escape_csv_field(42) == "42"
      assert Helpers.escape_csv_field(3.14) == "3.14"
    end

    test "converts booleans to string" do
      assert Helpers.escape_csv_field(true) == "true"
      assert Helpers.escape_csv_field(false) == "false"
    end

    test "passes through simple strings" do
      assert Helpers.escape_csv_field("hello") == "hello"
    end

    test "wraps strings with special characters in quotes" do
      assert Helpers.escape_csv_field("a,b") == "\"a,b\""
      assert Helpers.escape_csv_field("a\"b") == "\"a\"\"b\""
      assert Helpers.escape_csv_field("a\nb") == "\"a\nb\""
    end
  end

  # ===========================================================================
  # build_csv
  # ===========================================================================

  describe "build_csv/2" do
    test "builds CSV with headers and rows" do
      result = Helpers.build_csv(["Name", "Age"], [["Alice", 30], ["Bob", 25]])
      assert result == "Name,Age\nAlice,30\nBob,25"
    end

    test "handles empty rows" do
      result = Helpers.build_csv(["A", "B"], [])
      assert result == "A,B"
    end

    test "escapes special characters in values" do
      result = Helpers.build_csv(["Col"], [["hello,world"]])
      assert result == "Col\n\"hello,world\""
    end
  end

  # ===========================================================================
  # connection_graph
  # ===========================================================================

  describe "connection_graph/1" do
    test "builds adjacency list from connections" do
      flow = %{
        nodes: [],
        connections: [
          %{source_node_id: 1, source_pin: "output", target_node_id: 2, target_pin: "input"},
          %{source_node_id: 1, source_pin: "resp_1", target_node_id: 3, target_pin: "input"}
        ]
      }

      graph = Helpers.connection_graph(flow)
      assert Map.has_key?(graph, 1)
      assert length(graph[1]) == 2
    end

    test "returns empty map for no connections" do
      graph = Helpers.connection_graph(%{nodes: [], connections: []})
      assert graph == %{}
    end
  end

  # ===========================================================================
  # find_entry_node
  # ===========================================================================

  describe "find_entry_node/1" do
    test "finds the entry node" do
      flow = %{
        nodes: [
          %{id: 1, type: "entry"},
          %{id: 2, type: "dialogue"}
        ]
      }

      assert Helpers.find_entry_node(flow).id == 1
    end

    test "returns nil if no entry node" do
      flow = %{nodes: [%{id: 1, type: "dialogue"}]}
      assert Helpers.find_entry_node(flow) == nil
    end
  end

  # ===========================================================================
  # dialogue_text
  # ===========================================================================

  describe "dialogue_text/1" do
    test "extracts and strips HTML from dialogue text" do
      assert Helpers.dialogue_text(%{"text" => "<p>Hello</p>"}) == "Hello"
    end

    test "returns empty string for missing text" do
      assert Helpers.dialogue_text(%{}) == ""
    end
  end

  # ===========================================================================
  # extract_condition
  # ===========================================================================

  describe "extract_condition/1" do
    test "returns nil for nil and empty" do
      assert Helpers.extract_condition(nil) == nil
      assert Helpers.extract_condition("") == nil
    end

    test "passes through map with logic key" do
      cond = %{"logic" => "all", "rules" => []}
      assert Helpers.extract_condition(cond) == cond
    end

    test "parses JSON string to condition map" do
      json = Jason.encode!(%{"logic" => "any", "rules" => [%{"variable" => "x"}]})
      result = Helpers.extract_condition(json)
      assert result["logic"] == "any"
    end

    test "returns nil for invalid JSON" do
      assert Helpers.extract_condition("not json") == nil
    end

    test "returns nil for non-condition JSON" do
      assert Helpers.extract_condition(Jason.encode!(%{"foo" => "bar"})) == nil
    end
  end

  # ===========================================================================
  # infer_default_value — uncovered branches
  # ===========================================================================

  describe "infer_default_value/1 additional branches" do
    test "returns select value when present" do
      assert Helpers.infer_default_value(%{type: "select", value: %{"select" => "warrior"}}) ==
               "warrior"
    end

    test "returns date value when present" do
      assert Helpers.infer_default_value(%{type: "date", value: %{"date" => "2024-06-15"}}) ==
               "2024-06-15"
    end
  end

  # ===========================================================================
  # build_speaker_map — non-list fallback
  # ===========================================================================

  describe "build_speaker_map/1 edge cases" do
    test "returns empty map for non-list input" do
      assert Helpers.build_speaker_map(nil) == %{}
      assert Helpers.build_speaker_map("not a list") == %{}
      assert Helpers.build_speaker_map(42) == %{}
    end
  end

  # ===========================================================================
  # speaker_name / speaker_shortcut — empty string case
  # ===========================================================================

  describe "speaker_name/2 edge cases" do
    test "returns nil for empty string speaker_sheet_id" do
      speaker_map = %{"1" => %{name: "Jaime", shortcut: "mc.jaime"}}
      assert Helpers.speaker_name(%{"speaker_sheet_id" => ""}, speaker_map) == nil
    end

    test "returns nil for nil speaker_sheet_id" do
      speaker_map = %{"1" => %{name: "Jaime", shortcut: "mc.jaime"}}
      assert Helpers.speaker_name(%{"speaker_sheet_id" => nil}, speaker_map) == nil
    end

    test "returns name for valid speaker_sheet_id" do
      speaker_map = %{"1" => %{name: "Jaime", shortcut: "mc.jaime"}}
      assert Helpers.speaker_name(%{"speaker_sheet_id" => "1"}, speaker_map) == "Jaime"
    end
  end

  describe "speaker_shortcut/2 edge cases" do
    test "returns nil for empty string speaker_sheet_id" do
      speaker_map = %{"1" => %{name: "Jaime", shortcut: "mc.jaime"}}
      assert Helpers.speaker_shortcut(%{"speaker_sheet_id" => ""}, speaker_map) == nil
    end
  end

  # ===========================================================================
  # dialogue_responses — instruction JSON parsing
  # ===========================================================================

  describe "dialogue_responses/1 instruction parsing" do
    test "parses empty instruction string to empty list" do
      data = %{"responses" => [%{"id" => "r1", "text" => "Yes", "instruction" => ""}]}
      [resp] = Helpers.dialogue_responses(data)
      assert resp["instruction_assignments"] == []
    end

    test "parses valid JSON array instruction" do
      assignments = [%{"variable" => "health", "operator" => "set", "value" => "100"}]
      json = Jason.encode!(assignments)
      data = %{"responses" => [%{"id" => "r1", "text" => "Heal", "instruction" => json}]}
      [resp] = Helpers.dialogue_responses(data)
      assert length(resp["instruction_assignments"]) == 1
    end

    test "returns empty list for invalid JSON instruction" do
      data = %{"responses" => [%{"id" => "r1", "text" => "X", "instruction" => "not json"}]}
      [resp] = Helpers.dialogue_responses(data)
      assert resp["instruction_assignments"] == []
    end

    test "returns empty list for non-array JSON instruction" do
      json = Jason.encode!(%{"not" => "array"})
      data = %{"responses" => [%{"id" => "r1", "text" => "X", "instruction" => json}]}
      [resp] = Helpers.dialogue_responses(data)
      assert resp["instruction_assignments"] == []
    end

    test "returns empty list for non-string instruction" do
      data = %{"responses" => [%{"id" => "r1", "text" => "X", "instruction" => 42}]}
      [resp] = Helpers.dialogue_responses(data)
      assert resp["instruction_assignments"] == []
    end
  end

  # ===========================================================================
  # extract_condition — catch-all
  # ===========================================================================

  describe "extract_condition/1 additional cases" do
    test "returns nil for non-string non-map input" do
      assert Helpers.extract_condition(42) == nil
      assert Helpers.extract_condition([1, 2, 3]) == nil
      assert Helpers.extract_condition(true) == nil
    end
  end

  # ===========================================================================
  # format_var_declaration_value
  # ===========================================================================

  describe "format_var_declaration_value/1" do
    test "formats number" do
      assert Helpers.format_var_declaration_value(%{type: :number, default: 42}) == "42"
    end

    test "formats boolean" do
      assert Helpers.format_var_declaration_value(%{type: :boolean, default: true}) == "true"
    end

    test "formats string with quotes" do
      assert Helpers.format_var_declaration_value(%{type: :string, default: "hello"}) ==
               ~s("hello")
    end

    test "escapes quotes in string values" do
      assert Helpers.format_var_declaration_value(%{type: :string, default: ~s(say "hi")}) ==
               ~s("say \\"hi\\"")
    end

    test "defaults for types without values" do
      assert Helpers.format_var_declaration_value(%{type: :number}) == "0"
      assert Helpers.format_var_declaration_value(%{type: :boolean}) == "false"
      assert Helpers.format_var_declaration_value(%{type: :string, default: ""}) == ~s("")
    end
  end
end
