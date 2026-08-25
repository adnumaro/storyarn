defmodule Storyarn.Workspaces.Lifecycle do
  @moduledoc false

  alias Storyarn.Workspaces.Lifecycle.Commands.CreateWorkspace
  alias Storyarn.Workspaces.Lifecycle.Commands.DeleteWorkspace
  alias Storyarn.Workspaces.Lifecycle.Commands.UpdateWorkspace
  alias Storyarn.Workspaces.Lifecycle.Data.SourceLocaleCatalog
  alias Storyarn.Workspaces.Lifecycle.Queries.UniqueSlug
  alias Storyarn.Workspaces.Lifecycle.Queries.Workspaces
  alias Storyarn.Workspaces.Workspace

  defdelegate get_workspace!(id), to: Workspaces, as: :get!
  defdelegate create_workspace(scope, attrs), to: CreateWorkspace, as: :create
  defdelegate create_workspace_with_owner(user, attrs), to: CreateWorkspace, as: :create_with_owner

  def change_workspace(%Workspace{} = workspace, attrs \\ %{}) do
    Workspace.update_changeset(workspace, attrs)
  end

  def change_new_workspace, do: change_workspace(%Workspace{})
  defdelegate update_workspace(workspace, attrs), to: UpdateWorkspace, as: :update
  defdelegate delete_workspace(workspace), to: DeleteWorkspace, as: :delete
  defdelegate generate_slug(name), to: UniqueSlug, as: :generate
  defdelegate source_locale_options(), to: SourceLocaleCatalog, as: :all
end
