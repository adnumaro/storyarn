defmodule StoryarnWeb.FlowLive.Helpers.FormHelpersTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.FlowLive.Helpers.FormHelpers

  # ── node_data_to_form/1 ────────────────────────────────────────────

  describe "node_data_to_form/1" do
    test "returns a Phoenix.HTML.Form struct with :node name" do
      node = %{
        type: "hub",
        data: %{"hub_id" => "hub_1", "label" => "Start", "color" => "#FF0000"}
      }

      form = FormHelpers.node_data_to_form(node)

      assert %Phoenix.HTML.Form{} = form
      assert form.name == "node"
    end

    test "form contains extracted data for dialogue node" do
      node = %{
        type: "dialogue",
        data: %{
          "speaker_sheet_id" => "sheet_1",
          "text" => "Hello",
          "stage_directions" => "enters",
          "menu_text" => "Greet",
          "audio_asset_id" => nil,
          "technical_id" => "dlg_01",
          "localization_id" => "loc_01",
          "responses" => []
        }
      }

      form = FormHelpers.node_data_to_form(node)

      assert form.params["speaker_sheet_id"] == "sheet_1"
      assert form.params["text"] == "Hello"
      assert form.params["technical_id"] == "dlg_01"
    end

    test "form contains extracted data for condition node" do
      node = %{
        type: "condition",
        data: %{
          "condition" => %{"logic" => "all", "rules" => [%{"variable" => "hp"}]},
          "switch_mode" => true
        }
      }

      form = FormHelpers.node_data_to_form(node)

      assert form.params["switch_mode"] == true
      assert form.params["condition"]["logic"] == "all"
    end

    test "form has empty data for entry node" do
      node = %{type: "entry", data: %{}}
      form = FormHelpers.node_data_to_form(node)

      assert form.params == %{}
    end

    test "form handles nil data values with defaults" do
      node = %{type: "hub", data: %{"hub_id" => nil, "label" => nil, "color" => nil}}
      form = FormHelpers.node_data_to_form(node)

      assert form.params["hub_id"] == ""
      assert form.params["color"] == "#8b5cf6"
    end
  end

  # ── sheets_map/1 ─────────────────────────────────────────────────────

  describe "sheets_map/1" do
    test "builds map keyed by string ID with expected fields" do
      sheets = [
        %{
          id: 1,
          name: "Jaime",
          color: "#ff0000",
          avatar_asset: %{url: "https://cdn.test/jaime.png"}
        },
        %{id: 2, name: "Anya", color: "#00ff00", avatar_asset: nil}
      ]

      result = FormHelpers.sheets_map(sheets)

      assert map_size(result) == 2

      assert result["1"] == %{
               id: 1,
               name: "Jaime",
               avatar_url: "https://cdn.test/jaime.png",
               color: "#ff0000"
             }

      assert result["2"] == %{
               id: 2,
               name: "Anya",
               avatar_url: nil,
               color: "#00ff00"
             }
    end

    test "handles avatar_asset with non-binary url" do
      sheets = [%{id: 10, name: "NPC", color: nil, avatar_asset: %{url: nil}}]
      result = FormHelpers.sheets_map(sheets)

      assert result["10"].avatar_url == nil
    end

    test "handles avatar_asset without url key" do
      sheets = [%{id: 10, name: "NPC", color: nil, avatar_asset: %{}}]
      result = FormHelpers.sheets_map(sheets)

      assert result["10"].avatar_url == nil
    end

    test "returns empty map for empty list" do
      assert FormHelpers.sheets_map([]) == %{}
    end
  end

  # ── get_email_name/1 ─────────────────────────────────────────────────

  describe "get_email_name/1" do
    test "extracts name part from email" do
      assert FormHelpers.get_email_name("alice@example.com") == "alice"
    end

    test "handles email with dots in local part" do
      assert FormHelpers.get_email_name("alice.bob@example.com") == "alice.bob"
    end

    test "handles email with no local part" do
      assert FormHelpers.get_email_name("@example.com") == ""
    end

    test "returns Someone for nil" do
      assert FormHelpers.get_email_name(nil) == "Someone"
    end

    test "returns Someone for integer" do
      assert FormHelpers.get_email_name(42) == "Someone"
    end

    test "returns Someone for atom" do
      assert FormHelpers.get_email_name(:not_email) == "Someone"
    end

    test "handles string without @ sign" do
      assert FormHelpers.get_email_name("noemail") == "noemail"
    end
  end
end
