defmodule Storyarn.Projects.Access.Commands.OwnerAuthority do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Projects.Access.Rules.OwnershipInvariant
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Repo

  @max_pg_bigint 9_223_372_036_854_775_807

  @type locked_state :: %{
          project: Project.t(),
          memberships: [ProjectMembership.t()],
          owner_membership: ProjectMembership.t()
        }

  defguardp valid_id(id)
            when is_integer(id) and id > 0 and id <= @max_pg_bigint

  @spec transact_as_owner(map(), pos_integer(), (locked_state() -> term())) :: term()
  def transact_as_owner(%{user: %{id: actor_id}}, project_id, fun)
      when valid_id(actor_id) and valid_id(project_id) and is_function(fun, 1) do
    Repo.transact(fn ->
      with {:ok, state} <- lock_and_validate(project_id),
           :ok <- authorize_owner(state.owner_membership, actor_id) do
        fun.(state)
      end
    end)
  end

  def transact_as_owner(_scope, _project_id, _fun), do: {:error, :unauthorized}

  @spec lock_and_validate(pos_integer()) ::
          {:ok, locked_state()} | {:error, :not_found | :ownership_invariant_violation}
  def lock_and_validate(project_id) when valid_id(project_id) do
    case lock_project(project_id) do
      %Project{} = project ->
        memberships = lock_memberships(project.id)

        case OwnershipInvariant.owner(project, memberships) do
          {:ok, owner_membership} ->
            {:ok,
             %{
               project: project,
               memberships: memberships,
               owner_membership: owner_membership
             }}

          error ->
            error
        end

      nil ->
        {:error, :not_found}
    end
  end

  defp lock_project(project_id) do
    Repo.one(
      from(project in Project,
        where: project.id == ^project_id and is_nil(project.deleted_at),
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_memberships(project_id) do
    Repo.all(
      from(membership in ProjectMembership,
        where: membership.project_id == ^project_id,
        order_by: [asc: membership.user_id, asc: membership.id],
        lock: "FOR UPDATE"
      )
    )
  end

  defp authorize_owner(%ProjectMembership{user_id: actor_id}, actor_id), do: :ok
  defp authorize_owner(_owner_membership, _actor_id), do: {:error, :unauthorized}
end
