defmodule Storyarn.Platform.ProductMetricsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Platform.Analytics.EventContract
  alias Storyarn.Platform.ProductMetrics

  @events %{
    {:accounts, :user_logged_in} => {"user logged in", ~w(auth_method)},
    {:accounts, :user_signed_up} => {"user signed up", ~w(auth_method)},
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
    {:projects, :asset_uploaded} =>
      {"asset uploaded", ~w(asset_type content_type created_variant project_id purpose size_bucket)},
    {:projects, :project_created} => {"project created", ~w(project_id project_subtype project_type workspace_id)},
    {:projects, :template_installation_completed} =>
      {"project template installation completed",
       ~w(duration_bucket error_code installation_id project_id source template_version_id workspace_id)},
    {:projects, :template_installation_failed} =>
      {"project template installation failed",
       ~w(duration_bucket error_code installation_id project_id source template_version_id workspace_id)},
    {:projects, :template_installation_requested} =>
      {"project template installation requested",
       ~w(installation_id source template_id template_version_id visibility workspace_id)},
    {:projects, :version_control_settings_updated} =>
      {"version control settings updated", ~w(auto_version_flows auto_version_scenes auto_version_sheets project_id)},
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

  test "Account metrics keep the closed auth-method vocabulary and drop everything else" do
    for event_type <- [:user_logged_in, :user_signed_up], auth_method <- ["password", "invite"] do
      assert {:ok, %{auth_method: ^auth_method}} =
               EventContract.sanitize(ProductMetrics, {:accounts, event_type}, %{
                 auth_method: auth_method,
                 email: "private@example.com"
               })
    end

    assert EventContract.sanitize(ProductMetrics, {:accounts, :user_signed_up}, %{
             auth_method: "private-user-authored-method"
           }) == :error

    assert ProductMetrics.event({:accounts, :user_signed_up}) == {:ok, "user signed up", ~w(auth_method)}
    assert ProductMetrics.event({:accounts, :user_logged_in}) == {:ok, "user logged in", ~w(auth_method)}
  end

  test "Project metrics keep ids validated and drop authored payload fields" do
    assert {:ok, %{project_id: 7, workspace_id: 3, project_type: "game", project_subtype: "rpg"}} =
             EventContract.sanitize(ProductMetrics, {:projects, :project_created}, %{
               project_id: 7,
               workspace_id: 3,
               project_type: "game",
               project_subtype: "rpg",
               name: "private project name"
             })

    assert EventContract.sanitize(ProductMetrics, {:projects, :project_created}, %{
             project_id: nil,
             workspace_id: 3
           }) == :error

    assert {:ok, sanitized} =
             EventContract.sanitize(ProductMetrics, {:projects, :template_installation_completed}, %{
               duration_bucket: "under_1m",
               error_code: nil,
               installation_id: 11,
               project_id: nil,
               source: "gallery",
               template_version_id: 4,
               workspace_id: 3,
               template_name: "private"
             })

    refute Map.has_key?(sanitized, :template_name)
    assert sanitized.project_id == nil

    assert {:ok, %{auto_version_flows: true, project_id: 7}} =
             EventContract.sanitize(ProductMetrics, {:projects, :version_control_settings_updated}, %{
               auto_version_flows: true,
               auto_version_scenes: false,
               auto_version_sheets: true,
               project_id: 7
             })
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
