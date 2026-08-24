defmodule Storyarn.Platform.ProductMetricsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Analytics.EventContract
  alias Storyarn.Platform.ProductMetrics

  @events %{
    {:flows, :debug_started} => {"flow debug started", ~w(flow_id project_id)},
    {:flows, :node_created} => {"flow node created", ~w(creation_method flow_id has_parent node_type project_id)},
    {:flows, :player_started} => {"flow player started", ~w(flow_id project_id)},
    {:flows, :sequence_track_updated} =>
      {"sequence track updated", ~w(changed_asset changed_volume flow_id has_asset project_id sequence_id track_kind)},
    {:flows, :sequence_visual_layer_created} =>
      {"sequence visual layer created", ~w(flow_id has_asset layer_kind project_id sequence_id slot)},
    {:flows, :sequence_visual_layer_updated} =>
      {"sequence visual layer updated", ~w(changed_asset flow_id has_asset layer_kind project_id sequence_id slot)},
    {:flows, :version_compared} => {"version compared", ~w(entity_type project_id)},
    {:flows, :version_created} => {"version created", ~w(entity_type project_id)},
    {:flows, :version_panel_opened} => {"version panel opened", ~w(entity_type project_id)},
    {:flows, :version_restored} => {"version restored", ~w(entity_type project_id)},
    {:scenes, :asset_uploaded} =>
      {"asset uploaded", ~w(asset_type content_type created_variant project_id purpose size_bucket)},
    {:scenes, :exploration_started} => {"scene exploration started", ~w(has_saved_session project_id scene_id)},
    {:scenes, :version_compared} => {"version compared", ~w(entity_type project_id)},
    {:scenes, :version_created} => {"version created", ~w(entity_type project_id)},
    {:scenes, :version_panel_opened} => {"version panel opened", ~w(entity_type project_id)},
    {:scenes, :version_restored} => {"version restored", ~w(entity_type project_id)},
    {:sheets, :asset_uploaded} =>
      {"asset uploaded", ~w(asset_type content_type created_variant project_id purpose size_bucket)},
    {:sheets, :block_created} => {"sheet block created", ~w(block_type creation_method project_id scope sheet_id)},
    {:sheets, :version_compared} => {"version compared", ~w(entity_type project_id)},
    {:sheets, :version_created} => {"version created", ~w(entity_type project_id)},
    {:sheets, :version_panel_opened} => {"version panel opened", ~w(entity_type project_id)},
    {:sheets, :version_restored} => {"version restored", ~w(entity_type project_id)},
    {:workspaces, :workspace_created} => {"workspace created", ~w(workspace_id)}
  }

  test "Platform owns the complete tool metric vocabulary and privacy allowlist" do
    expected_events = @events |> Map.keys() |> Enum.sort()
    assert ProductMetrics.events() == expected_events

    assert Map.new(@events, fn {event, {name, keys}} ->
             assert {:ok, ^name, allowed_keys} = EventContract.resolve(ProductMetrics, event)
             assert allowed_keys == MapSet.new(keys)
             {event, {name, keys}}
           end) == @events
  end

  test "unknown product metric reactions fail closed" do
    assert ProductMetrics.event({:flows, :unknown}) == :error
    assert EventContract.resolve(ProductMetrics, {:flows, :unknown}) == :error
  end

  test "Platform independently validates and projects values before analytics" do
    payload = %{
      content: "private story content",
      creation_method: "create",
      flow_id: 11,
      has_parent: true,
      node_type: "dialogue",
      project_id: 7
    }

    assert {:ok,
            %{
              creation_method: "create",
              flow_id: 11,
              has_parent: true,
              node_type: "dialogue",
              project_id: 7
            }} = EventContract.sanitize(ProductMetrics, {:flows, :node_created}, payload)

    assert EventContract.sanitize(
             ProductMetrics,
             {:flows, :node_created},
             %{payload | node_type: "private user-authored content"}
           ) == :error
  end

  test "Scene metrics preserve historical names while dropping authored content" do
    assert {:ok,
            %{
              asset_type: "image",
              content_type: "image/png",
              created_variant: false,
              project_id: 7,
              purpose: "scene_background",
              size_bucket: "under_100kb"
            }} =
             EventContract.sanitize(ProductMetrics, {:scenes, :asset_uploaded}, %{
               asset_type: "image",
               content_type: "image/png",
               created_variant: false,
               filename: "private-background.png",
               project_id: 7,
               purpose: "scene_background",
               size_bucket: "under_100kb"
             })

    assert EventContract.sanitize(ProductMetrics, {:scenes, :asset_uploaded}, %{
             asset_type: "image",
             content_type: "image/png",
             created_variant: false,
             project_id: 7,
             purpose: "private-user-authored-purpose",
             size_bucket: "under_100kb"
           }) == :error

    assert {:ok, %{has_saved_session: true, project_id: 7, scene_id: 11}} =
             EventContract.sanitize(ProductMetrics, {:scenes, :exploration_started}, %{
               authored_scene_name: "private",
               has_saved_session: true,
               project_id: 7,
               scene_id: 11
             })

    for event_type <- [:version_compared, :version_created, :version_panel_opened, :version_restored] do
      assert {:ok, %{entity_type: "scene", project_id: 7}} =
               EventContract.sanitize(ProductMetrics, {:scenes, event_type}, %{
                 entity_type: "scene",
                 project_id: 7,
                 version_name: "private"
               })
    end

    assert ProductMetrics.event({:scenes, :exploration_started}) ==
             {:ok, "scene exploration started", ~w(has_saved_session project_id scene_id)}

    assert ProductMetrics.event({:scenes, :asset_uploaded}) ==
             {:ok, "asset uploaded", ~w(asset_type content_type created_variant project_id purpose size_bucket)}

    assert ProductMetrics.event({:scenes, :version_compared}) ==
             {:ok, "version compared", ~w(entity_type project_id)}

    assert ProductMetrics.event({:scenes, :version_created}) ==
             {:ok, "version created", ~w(entity_type project_id)}

    assert ProductMetrics.event({:scenes, :version_panel_opened}) ==
             {:ok, "version panel opened", ~w(entity_type project_id)}

    assert ProductMetrics.event({:scenes, :version_restored}) ==
             {:ok, "version restored", ~w(entity_type project_id)}
  end
end
