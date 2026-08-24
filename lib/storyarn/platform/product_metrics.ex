defmodule Storyarn.Platform.ProductMetrics do
  @moduledoc """
  Platform-owned product metric reactions and privacy allowlists.

  The source context owns the fact and its payload. This module owns the
  external metric name and the exact coarse properties that may leave Storyarn.
  """

  @behaviour Storyarn.Analytics.EventContract
  @behaviour Storyarn.Platform.EventReaction

  alias Storyarn.Analytics
  alias Storyarn.Analytics.EventContract
  alias Storyarn.Platform.EventReaction

  @creation_methods ~w(create duplicate wrap_selection)
  @sheet_block_types ~w(text rich_text number select multi_select date boolean reference table gallery)
  @asset_content_types ~w(
    image/jpeg image/png image/gif image/webp image/svg+xml
    audio/mpeg audio/wav audio/ogg audio/webm
    application/pdf
  )
  @asset_purposes [nil, "scene_background"]
  @asset_size_buckets ~w(under_100kb 100kb_to_1mb 1mb_to_10mb over_10mb)
  @flow_node_types ~w(annotation dialogue hub condition instruction jump entry exit subflow sequence)
  @sequence_track_kinds ~w(music ambience sfx)
  @visual_layer_kinds ~w(backdrop character prop overlay)
  @visual_layer_slots ~w(
    full left center right custom
    top-left top-center top-right
    middle-left middle-center middle-right
    bottom-left bottom-center bottom-right
  )

  @auth_methods ~w(password invite)

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

  @impl EventReaction
  @spec handle(term(), atom(), atom(), map()) :: :ok
  def handle(:system, source, event_type, payload) when is_atom(source) and is_atom(event_type) and is_map(payload) do
    Analytics.track_system(__MODULE__, {source, event_type}, payload)
  end

  def handle({:user_id, user_id}, source, event_type, payload)
      when is_integer(user_id) and user_id > 0 and is_atom(source) and is_atom(event_type) and is_map(payload) do
    Analytics.track_user_id(user_id, __MODULE__, {source, event_type}, payload)
  end

  def handle(scope_or_user, :accounts, event_type, payload)
      when event_type in [:user_logged_in, :user_signed_up] and is_map(payload) do
    Analytics.identify_user(scope_or_user)
    Analytics.track(scope_or_user, __MODULE__, {:accounts, event_type}, payload)
  end

  def handle(scope_or_user, source, event_type, payload)
      when is_atom(source) and is_atom(event_type) and is_map(payload) do
    Analytics.track(scope_or_user, __MODULE__, {source, event_type}, payload)
  end

  def handle(_scope_or_user, _source, _event_type, _payload), do: :ok

  @doc false
  @impl EventReaction
  @spec events() :: [{atom(), atom()}]
  def events, do: @events |> Map.keys() |> Enum.sort()

  @impl EventContract
  def event(event) do
    case Map.fetch(@events, event) do
      {:ok, {name, property_keys}} -> {:ok, name, property_keys}
      :error -> :error
    end
  end

  @impl EventContract
  def sanitize(event, payload), do: sanitize_payload(event, payload)

  @doc false
  @spec sanitize_payload({atom(), atom()}, map()) :: {:ok, map()} | :error
  def sanitize_payload({:flows, event_type}, %{flow_id: flow_id, project_id: project_id} = payload)
      when event_type in [:debug_started, :player_started] do
    if valid_ids?(flow_id, project_id), do: {:ok, Map.take(payload, [:flow_id, :project_id])}, else: :error
  end

  def sanitize_payload(
        {:flows, :node_created},
        %{
          creation_method: creation_method,
          flow_id: flow_id,
          has_parent: has_parent,
          node_type: node_type,
          project_id: project_id
        } = payload
      ) do
    if creation_method in @creation_methods and valid_ids?(flow_id, project_id) and is_boolean(has_parent) and
         node_type in @flow_node_types do
      {:ok, Map.take(payload, [:creation_method, :flow_id, :has_parent, :node_type, :project_id])}
    else
      :error
    end
  end

  def sanitize_payload(
        {:flows, :sequence_track_updated},
        %{
          changed_asset: changed_asset,
          changed_volume: changed_volume,
          flow_id: flow_id,
          has_asset: has_asset,
          project_id: project_id,
          sequence_id: sequence_id,
          track_kind: track_kind
        } = payload
      ) do
    if is_boolean(changed_asset) and is_boolean(changed_volume) and valid_ids?(flow_id, project_id) and
         is_boolean(has_asset) and valid_id?(sequence_id) and track_kind in @sequence_track_kinds do
      {:ok,
       Map.take(payload, [
         :changed_asset,
         :changed_volume,
         :flow_id,
         :has_asset,
         :project_id,
         :sequence_id,
         :track_kind
       ])}
    else
      :error
    end
  end

  def sanitize_payload(
        {:flows, event_type},
        %{
          changed_asset: changed_asset,
          flow_id: flow_id,
          has_asset: has_asset,
          layer_kind: layer_kind,
          project_id: project_id,
          sequence_id: sequence_id,
          slot: slot
        } = payload
      )
      when event_type in [:sequence_visual_layer_created, :sequence_visual_layer_updated] do
    if is_boolean(changed_asset) and valid_ids?(flow_id, project_id) and is_boolean(has_asset) and
         layer_kind in @visual_layer_kinds and valid_id?(sequence_id) and slot in @visual_layer_slots do
      allowed_keys = [:flow_id, :has_asset, :layer_kind, :project_id, :sequence_id, :slot]

      allowed_keys =
        if event_type == :sequence_visual_layer_updated,
          do: [:changed_asset | allowed_keys],
          else: allowed_keys

      {:ok, Map.take(payload, allowed_keys)}
    else
      :error
    end
  end

  def sanitize_payload({:flows, event_type}, %{entity_type: "flow", project_id: project_id} = payload)
      when event_type in [:version_compared, :version_created, :version_panel_opened, :version_restored] do
    if valid_id?(project_id), do: {:ok, Map.take(payload, [:entity_type, :project_id])}, else: :error
  end

  def sanitize_payload(
        {:scenes, :asset_uploaded},
        %{
          asset_type: asset_type,
          content_type: content_type,
          created_variant: created_variant,
          project_id: project_id,
          purpose: purpose,
          size_bucket: size_bucket
        } = payload
      ) do
    if content_type in @asset_content_types and asset_type == content_type_asset_type(content_type) and
         is_boolean(created_variant) and valid_id?(project_id) and purpose in @asset_purposes and
         size_bucket in @asset_size_buckets do
      {:ok,
       Map.take(payload, [
         :asset_type,
         :content_type,
         :created_variant,
         :project_id,
         :purpose,
         :size_bucket
       ])}
    else
      :error
    end
  end

  def sanitize_payload(
        {:scenes, :exploration_started},
        %{has_saved_session: has_saved_session, project_id: project_id, scene_id: scene_id} = payload
      ) do
    if is_boolean(has_saved_session) and valid_ids?(scene_id, project_id) do
      {:ok, Map.take(payload, [:has_saved_session, :project_id, :scene_id])}
    else
      :error
    end
  end

  def sanitize_payload({:scenes, event_type}, %{entity_type: "scene", project_id: project_id} = payload)
      when event_type in [:version_compared, :version_created, :version_panel_opened, :version_restored] do
    if valid_id?(project_id), do: {:ok, Map.take(payload, [:entity_type, :project_id])}, else: :error
  end

  # Sheet asset uploads share the Scene payload contract and external name.
  def sanitize_payload({:sheets, :asset_uploaded}, payload) do
    sanitize_payload({:scenes, :asset_uploaded}, payload)
  end

  def sanitize_payload(
        {:sheets, :block_created},
        %{
          block_type: block_type,
          creation_method: creation_method,
          project_id: project_id,
          scope: scope,
          sheet_id: sheet_id
        } = payload
      ) do
    if block_type in @sheet_block_types and creation_method in @creation_methods and
         valid_ids?(sheet_id, project_id) and (is_nil(scope) or is_binary(scope)) do
      {:ok, Map.take(payload, [:block_type, :creation_method, :project_id, :scope, :sheet_id])}
    else
      :error
    end
  end

  def sanitize_payload({:sheets, event_type}, %{entity_type: "sheet", project_id: project_id} = payload)
      when event_type in [:version_compared, :version_created, :version_panel_opened, :version_restored] do
    if valid_id?(project_id), do: {:ok, Map.take(payload, [:entity_type, :project_id])}, else: :error
  end

  def sanitize_payload({:accounts, event_type}, %{auth_method: auth_method} = payload)
      when event_type in [:user_logged_in, :user_signed_up] do
    if auth_method in @auth_methods, do: {:ok, Map.take(payload, [:auth_method])}, else: :error
  end

  def sanitize_payload({:workspaces, :workspace_created}, %{workspace_id: workspace_id} = payload) do
    if valid_id?(workspace_id), do: {:ok, Map.take(payload, [:workspace_id])}, else: :error
  end

  def sanitize_payload(_event, _payload), do: :error

  defp content_type_asset_type(content_type), do: content_type |> String.split("/", parts: 2) |> List.first()

  defp valid_ids?(flow_id, project_id), do: valid_id?(flow_id) and valid_id?(project_id)
  defp valid_id?(id), do: is_integer(id) and id > 0
end
