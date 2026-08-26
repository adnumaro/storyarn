defmodule Storyarn.Scenes.Health.Contracts.SeverityCatalogTest do
  @moduledoc """
  Freezes the Scene-owned health vocabulary exposed to its consumers.

  The exact map makes every new, removed or reclassified Scene finding an
  explicit product decision without coupling that decision to another tool.
  """

  use ExUnit.Case, async: true

  alias Storyarn.Scenes.Health.Rules.Checker, as: HealthChecker

  test "every Scene health code is pinned to a supported severity" do
    expected = %{
      invalid_ambient_trigger: :error,
      invalid_asset_reference: :error,
      invalid_collection_item: :error,
      invalid_condition_structure: :error,
      invalid_connection_endpoint: :error,
      invalid_connection_route: :error,
      invalid_layer_reference: :error,
      invalid_zone_action_configuration: :error,
      invalid_zone_geometry: :error,
      missing_scene_layer: :error,
      stale_ambient_flow_reference: :error,
      stale_collection_sheet_reference: :error,
      stale_pin_flow_reference: :error,
      stale_pin_sheet_reference: :error,
      stale_variable_reference: :error,
      stale_zone_target: :error,
      ambiguous_patrol_route: :warning,
      element_outside_canvas: :warning,
      empty_action_zone: :warning,
      incomplete_action_assignment: :warning,
      incomplete_condition: :warning,
      leader_without_walkable_area: :warning,
      missing_ambient_event_variable: :warning,
      missing_background: :warning,
      missing_default_layer: :warning,
      missing_display_variable: :warning,
      missing_scene_shortcut: :warning,
      missing_zone_label_icon: :warning,
      multiple_default_layers: :warning,
      patrol_on_playable_pin: :warning,
      patrol_without_route: :warning,
      playable_party_without_leader: :warning,
      variable_type_mismatch: :warning,
      empty_collection: :info,
      empty_scene: :info,
      empty_visibility_condition: :info
    }

    actual = Map.new(HealthChecker.codes(), &{&1, HealthChecker.severity_for(&1)})

    assert actual == expected
    assert map_size(expected) == length(HealthChecker.codes())
    assert Enum.all?(Map.values(actual), &(&1 in [:error, :warning, :info]))
    assert_raise KeyError, fn -> HealthChecker.severity_for(:a_code_that_was_never_declared) end
  end
end
