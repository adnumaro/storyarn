defmodule Storyarn.References.Backlinks do
  @moduledoc """
  Read-path adapter for backlinks.

  The SQL still lives in existing modules until the next PR2 pass moves it
  under this namespace.
  """

  alias Storyarn.Sheets.ReferenceTracker

  defdelegate get_backlinks(target_type, target_id), to: ReferenceTracker
  defdelegate get_backlinks_with_sources(target_type, target_id, project_id), to: ReferenceTracker
  defdelegate count_backlinks(target_type, target_id), to: ReferenceTracker
end
