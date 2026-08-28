defmodule Storyarn.Workspaces.Lifecycle.Commands.UpdateWorkspace do
  @moduledoc false

  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace

  @spec update(Workspace.t() | %{id: integer()}, map()) ::
          {:ok, Workspace.t()} | {:error, Ecto.Changeset.t()}
  def update(%Workspace{} = workspace, attrs) do
    workspace
    |> Workspace.update_changeset(attrs)
    |> Repo.update()
  end

  def update(%{id: id}, attrs) do
    Workspace
    |> Repo.get!(id)
    |> update(attrs)
  end
end
