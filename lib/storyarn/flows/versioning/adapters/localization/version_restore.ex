defmodule Storyarn.Flows.Versioning.Adapters.Localization.VersionRestore do
  @moduledoc """
  Narrow Flow adapter for Localization-owned version persistence.

  Flow owns snapshot orchestration and identity remapping. Localization owns
  validation and writes of the localized-text inventory.
  """

  alias Storyarn.Localization

  @spec prepare(pos_integer(), [pos_integer()], [pos_integer()]) :: :ok
  def prepare(project_id, deleted_node_ids, target_node_ids) do
    Localization.prepare_flow_version_texts(project_id, deleted_node_ids, target_node_ids)
  end

  @spec restore(pos_integer(), [map()], map()) :: :ok | {:error, term()}
  def restore(project_id, rows, id_maps) do
    Localization.restore_flow_version_texts(project_id, rows, id_maps)
  end
end
