defmodule Storyarn.Sheets.Versioning.Adapters.Localization.VersionRestore do
  @moduledoc """
  Narrow Sheet adapter for Localization-owned version persistence.

  Sheet owns snapshot orchestration and identity remapping. Localization owns
  validation and writes of the localized-text inventory.
  """

  alias Storyarn.Localization

  @spec restore(pos_integer(), [map()], map()) :: :ok | {:error, term()}
  def restore(project_id, rows, id_maps) do
    Localization.restore_sheet_version_texts(project_id, rows, id_maps)
  end
end
