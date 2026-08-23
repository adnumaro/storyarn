defmodule Storyarn.Scenes.Events do
  @moduledoc """
  Scene-owned business event vocabulary.

  Scenes owns the facts and payloads. Platform owns cross-cutting reactions
  such as product metrics, notifications, and future delivery policies.
  """

  alias Storyarn.Platform
  alias Storyarn.Scenes.Persistence.AssetRecord
  alias Storyarn.Scenes.Scene

  @event_types [
    :asset_uploaded,
    :exploration_started,
    :version_compared,
    :version_created,
    :version_panel_opened,
    :version_restored
  ]

  @spec emit(term(), atom(), map()) :: :ok
  def emit(scope_or_user, event_type, payload) when event_type in @event_types and is_map(payload) do
    if valid_payload?(event_type, payload) do
      Platform.react_to_event(scope_or_user, :scenes, event_type, payload)
    else
      :ok
    end
  end

  def emit(_scope_or_user, _event_type, _payload), do: :ok

  def exploration_started(scope_or_user, %Scene{} = scene, has_saved_session) when is_boolean(has_saved_session) do
    emit(scope_or_user, :exploration_started, %{
      has_saved_session: has_saved_session,
      project_id: scene.project_id,
      scene_id: scene.id
    })
  end

  def exploration_started(_scope_or_user, _scene, _has_saved_session), do: :ok

  @doc "Publishes the coarse product fact for a Scene-owned asset write."
  @spec asset_uploaded(term(), AssetRecord.t(), map()) :: :ok
  def asset_uploaded(scope_or_user, %AssetRecord{} = asset, attrs) when is_map(attrs) do
    emit(scope_or_user, :asset_uploaded, %{
      asset_type: asset_type(asset.content_type),
      content_type: asset.content_type,
      created_variant: (asset.metadata || %{})["is_variant"] == true,
      project_id: asset.project_id,
      purpose: analytics_value(Map.get(attrs, :purpose, Map.get(attrs, "purpose"))),
      size_bucket: size_bucket(asset.size)
    })
  end

  def asset_uploaded(_scope_or_user, _asset, _attrs), do: :ok

  def version_panel_opened(scope_or_user, %Scene{} = scene) do
    emit(scope_or_user, :version_panel_opened, %{
      entity_type: "scene",
      project_id: scene.project_id
    })
  end

  def version_panel_opened(_scope_or_user, _scene), do: :ok

  def valid_payload?(:exploration_started, %{
        has_saved_session: has_saved_session,
        project_id: project_id,
        scene_id: scene_id
      }), do: is_boolean(has_saved_session) and valid_id?(project_id) and valid_id?(scene_id)

  def valid_payload?(:asset_uploaded, %{
        asset_type: asset_type,
        content_type: content_type,
        created_variant: created_variant,
        project_id: project_id,
        purpose: purpose,
        size_bucket: size_bucket
      }) do
    asset_type in ~w(image audio application) and is_binary(content_type) and
      String.starts_with?(content_type, asset_type <> "/") and is_boolean(created_variant) and
      valid_id?(project_id) and purpose in [nil, "scene_background"] and
      size_bucket in ~w(under_100kb 100kb_to_1mb 1mb_to_10mb over_10mb)
  end

  def valid_payload?(event_type, %{entity_type: "scene", project_id: project_id})
      when event_type in [:version_compared, :version_created, :version_panel_opened, :version_restored],
      do: valid_id?(project_id)

  def valid_payload?(_event_type, _payload), do: false

  defp asset_type(content_type) when is_binary(content_type),
    do: content_type |> String.split("/", parts: 2) |> List.first()

  defp asset_type(_content_type), do: nil

  defp size_bucket(size) when is_integer(size) and size < 100 * 1024, do: "under_100kb"
  defp size_bucket(size) when is_integer(size) and size < 1024 * 1024, do: "100kb_to_1mb"
  defp size_bucket(size) when is_integer(size) and size < 10 * 1024 * 1024, do: "1mb_to_10mb"
  defp size_bucket(size) when is_integer(size), do: "over_10mb"
  defp size_bucket(_size), do: nil

  defp analytics_value(nil), do: nil
  defp analytics_value(value) when is_atom(value), do: Atom.to_string(value)
  defp analytics_value(value), do: value

  defp valid_id?(id), do: is_integer(id) and id > 0
end
