defmodule StoryarnWeb.SceneLive.Helpers.HealthHelpersTest do
  @moduledoc """
  The scene health popover is read by Spanish authors too.

  Every label it renders is built on the server, so a hardcoded English word here
  is a word Gettext can never reach — and `String.capitalize` on a DB enum is the
  worst version of that, because it LOOKS like a label.
  """

  use ExUnit.Case, async: true

  alias Storyarn.Scenes.HealthChecker
  alias StoryarnWeb.SceneLive.Helpers.HealthHelpers
  alias StoryarnWeb.SceneLive.Helpers.SceneHelpers

  @item_id "d6a3ceec-7a4c-46a4-bd43-073639a8b66c"

  setup do
    Gettext.put_locale(Storyarn.Gettext, "en")
    :ok
  end

  describe "the popover labels an unnamed element in the reader's language" do
    setup do
      Gettext.put_locale(Storyarn.Gettext, "es")
      on_exit(fn -> Gettext.put_locale(Storyarn.Gettext, "en") end)
      :ok
    end

    test "for every element type it can name" do
      assert labels_by_type() == %{
               "zone" => "Zona n.º 7",
               "pin" => "Marcador n.º 8",
               "connection" => "Conexión n.º 9",
               "annotation" => "Nota n.º 10"
             }
    end

    test "and for a finding whose element is not in the passed collection" do
      # `label_map` covers every element the checker saw, so this is the
      # last-resort clause — the one that used to run `String.capitalize` on the
      # entity_type and hand the UI an untranslatable word.
      payload = payload([finding(:invalid_layer_reference, "zone", 999)], zones: [])

      assert label(payload, :errorItems) == "Zona n.º 999"
    end

    test "and for a collection item inside its zone" do
      payload =
        payload(
          [
            HealthChecker.finding(:stale_collection_sheet_reference, %{
              scene_id: 1,
              entity_type: "collection_item",
              entity_id: @item_id,
              details: %{zone_id: 7, item_id: @item_id}
            })
          ],
          zones: [%{id: 7, name: nil, action_data: %{}}]
        )

      assert label(payload, :errorItems) == "Zona n.º 7 · Elemento n.º #{@item_id}"
    end
  end

  describe "the popover labels a nameless scene" do
    test "with the scene word rather than the blank the author left" do
      payload = payload([finding(:missing_background, "scene", nil)], scene: %{name: "   "})

      assert label(payload, :warningItems) == SceneHelpers.element_type_label("scene")
    end
  end

  describe "the location vocabulary is total" do
    test "every entity type the checker can emit has a word" do
      for entity_type <- HealthChecker.entity_types() do
        label = SceneHelpers.element_type_label(entity_type)
        assert is_binary(label) and label != ""
      end
    end

    test "an unknown entity type raises instead of leaking the enum" do
      assert_raise FunctionClauseError, fn -> SceneHelpers.element_type_label("sequence") end
    end
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp labels_by_type do
    findings = [
      finding(:invalid_zone_geometry, "zone", 7),
      finding(:stale_pin_sheet_reference, "pin", 8),
      finding(:invalid_connection_endpoint, "connection", 9),
      finding(:invalid_layer_reference, "annotation", 10)
    ]

    payload =
      payload(findings,
        zones: [%{id: 7, name: nil, action_data: %{}}],
        pins: [%{id: 8, label: nil}],
        connections: [%{id: 9, label: ""}],
        annotations: [%{id: 10, text: nil}]
      )

    Map.new(payload.errorItems, &{&1.entityType, &1.label})
  end

  defp finding(code, entity_type, entity_id) do
    HealthChecker.finding(code, %{scene_id: 1, entity_type: entity_type, entity_id: entity_id})
  end

  defp payload(findings, opts) do
    HealthHelpers.health_payload(
      findings,
      Keyword.get(opts, :scene, %{name: "Ruinas"}),
      Keyword.get(opts, :layers, []),
      Keyword.get(opts, :zones, []),
      Keyword.get(opts, :pins, []),
      Keyword.get(opts, :connections, []),
      Keyword.get(opts, :annotations, []),
      Keyword.get(opts, :ambient_flows, [])
    )
  end

  defp label(payload, key) do
    [item] = Map.fetch!(payload, key)
    item.label
  end
end
