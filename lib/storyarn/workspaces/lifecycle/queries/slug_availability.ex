defmodule Storyarn.Workspaces.Lifecycle.Queries.SlugAvailability do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace

  @spec available?(String.t()) :: boolean()
  def available?(slug) do
    not Repo.exists?(from(workspace in Workspace, where: workspace.slug == ^slug))
  end
end
