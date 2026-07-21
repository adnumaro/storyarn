defmodule Storyarn.GlobalSearch do
  @moduledoc """
  Authorized, bounded destination search across everything a user can reach:
  workspaces, projects, and named entities (sheets, flows, scenes).

  Security contract: results derive EXCLUSIVELY from the caller's scope
  through the existing membership-scoped queries in `Workspaces`/`Projects` —
  never from caller-provided ids — and entity lookups only ever run against
  that pre-authorized project set. Consumers (command palette today, global
  search / AI context resolution later) receive structured data; URL mapping
  belongs to the web layer.
  """

  alias Storyarn.GlobalSearch.Destinations

  defdelegate destinations(scope, query, opts \\ []), to: Destinations
end
