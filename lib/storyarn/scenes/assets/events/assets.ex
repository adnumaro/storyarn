defmodule Storyarn.Scenes.Assets.Events do
  @moduledoc false

  alias Storyarn.Platform
  alias Storyarn.Scenes.Assets.Entities.AssetRecord

  @doc "Publishes the coarse product fact for a Scene-owned asset write."
  @spec asset_uploaded(term(), AssetRecord.t(), map()) :: :ok
  def asset_uploaded(scope_or_user, %AssetRecord{} = asset, attrs) when is_map(attrs) do
    payload = %{
      asset_type: asset_type(asset.content_type),
      content_type: asset.content_type,
      created_variant: (asset.metadata || %{})["is_variant"] == true,
      project_id: asset.project_id,
      purpose: analytics_value(Map.get(attrs, :purpose, Map.get(attrs, "purpose"))),
      size_bucket: size_bucket(asset.size)
    }

    if valid_payload?(payload) do
      Platform.react_to_event(scope_or_user, :scenes, :asset_uploaded, payload)
    else
      :ok
    end
  end

  def asset_uploaded(_scope_or_user, _asset, _attrs), do: :ok

  defp valid_payload?(%{
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
