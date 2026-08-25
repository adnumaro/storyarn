defmodule Storyarn.Workspaces.Lifecycle.Queries.Workspaces do
  @moduledoc false

  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace

  @spec get!(integer()) :: Workspace.t()
  def get!(id), do: Repo.get!(Workspace, id)
end
