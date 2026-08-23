defmodule Storyarn.Sheets.Events do
  @moduledoc """
  Sheet-owned business event vocabulary.

  Sheets owns the facts and payloads. Platform owns cross-cutting reactions
  such as product metrics, notifications, and future delivery policies.
  """

  alias Storyarn.Platform
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Persistence.AssetRecord
  alias Storyarn.Sheets.Sheet

  @event_types [
    :asset_uploaded,
    :block_created,
    :version_compared,
    :version_created,
    :version_panel_opened,
    :version_restored
  ]

  @block_types Block.types()
  @creation_methods ~w(create duplicate wrap_selection)

  @spec emit(term(), atom(), map()) :: :ok
  def emit(scope_or_user, event_type, payload) when event_type in @event_types and is_map(payload) do
    if valid_payload?(event_type, payload) do
      Platform.react_to_event(scope_or_user, :sheets, event_type, payload)
    else
      :ok
    end
  end

  def emit(_scope_or_user, _event_type, _payload), do: :ok

  @doc "Publishes the coarse product fact for a Sheet-owned asset write."
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

  @doc "Publishes the product fact for a block created inside a Sheet."
  @spec block_created(term(), Sheet.t(), Block.t(), String.t(), term()) :: :ok
  def block_created(scope_or_user, %Sheet{} = sheet, %Block{} = block, creation_method, block_scope) do
    emit(scope_or_user, :block_created, %{
      block_type: block.type,
      creation_method: creation_method,
      project_id: sheet.project_id,
      scope: block_scope,
      sheet_id: sheet.id
    })
  end

  def block_created(_scope_or_user, _sheet, _block, _creation_method, _block_scope), do: :ok

  defp valid_payload?(:asset_uploaded, %{
         asset_type: asset_type,
         content_type: content_type,
         created_variant: created_variant,
         project_id: project_id,
         purpose: purpose,
         size_bucket: size_bucket
       }) do
    asset_type in ~w(image audio application) and is_binary(content_type) and
      String.starts_with?(content_type, asset_type <> "/") and is_boolean(created_variant) and
      valid_id?(project_id) and is_nil(purpose) and
      size_bucket in ~w(under_100kb 100kb_to_1mb 1mb_to_10mb over_10mb)
  end

  defp valid_payload?(event_type, %{entity_type: "sheet", project_id: project_id})
       when event_type in [:version_compared, :version_created, :version_panel_opened, :version_restored],
       do: valid_id?(project_id)

  defp valid_payload?(:block_created, payload) do
    payload.block_type in @block_types and payload.creation_method in @creation_methods and
      valid_id?(payload.project_id) and valid_id?(payload.sheet_id) and
      (is_nil(payload.scope) or is_binary(payload.scope))
  end

  defp valid_id?(id), do: is_integer(id) and id > 0

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
end
