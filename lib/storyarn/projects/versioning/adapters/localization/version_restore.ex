defmodule Storyarn.Projects.Versioning.Adapters.Localization.VersionRestore do
  @moduledoc """
  Narrow Project-reconstitution adapter for Localization-owned version writes.

  Projects owns whole-Project materialization and identity remapping. This
  adapter exposes only the transaction-participating Localization commands
  required by that closed workflow.
  """

  alias Storyarn.Localization

  @spec lock_inventory!(pos_integer()) :: :ok
  def lock_inventory!(project_id), do: Localization.lock_inventory!(project_id)

  @spec extract_flow(pos_integer()) :: :ok | {:error, term()}
  def extract_flow(flow_id), do: Localization.extract_flow_nodes(flow_id)

  @spec extract_sheet(pos_integer()) :: :ok | {:error, term()}
  def extract_sheet(sheet_id), do: Localization.extract_sheet_blocks(sheet_id)

  @spec sync_sheet_names(pos_integer()) :: :ok | {:error, term()}
  def sync_sheet_names(project_id), do: Localization.sync_sheet_names(project_id)

  @spec restore_flow(pos_integer(), [map()], map()) :: :ok | {:error, term()}
  def restore_flow(project_id, rows, id_maps) do
    Localization.restore_flow_version_texts(project_id, rows, id_maps)
  end

  @spec restore_sheet(pos_integer(), [map()], map()) :: :ok | {:error, term()}
  def restore_sheet(project_id, rows, id_maps) do
    Localization.restore_sheet_version_texts(project_id, rows, id_maps)
  end
end
