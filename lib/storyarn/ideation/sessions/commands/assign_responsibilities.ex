defmodule Storyarn.Ideation.Sessions.Commands.AssignResponsibilities do
  @moduledoc false
  import Ecto.Changeset

  alias Storyarn.Ideation.Sessions.Adapters.ProjectAccess
  alias Storyarn.Ideation.Sessions.Execution.Mutation
  alias Storyarn.Repo

  def run(scope, project_id, session_id, revision, attrs) do
    Mutation.run(scope, project_id, session_id, revision, fn session, access ->
      changeset =
        session
        |> cast(attrs, [:facilitator_id, :decision_owner_id])
        |> validate_delegate(:facilitator_id, scope, project_id, attrs)
        |> validate_delegate(:decision_owner_id, scope, project_id, attrs)

      cond do
        not changeset.valid? ->
          {:error, changeset}

        changeset.changes == %{} ->
          {:ok, session}

        true ->
          persist(changeset, session.revision, access.user_id)
      end
    end)
  end

  defp persist(changeset, revision, actor_id) do
    with {:ok, updated} <- changeset |> put_change(:revision, revision + 1) |> Repo.update() do
      Mutation.record(updated, actor_id, :responsibilities_assigned)
    end
  end

  defp validate_delegate(changeset, field, scope, project_id, attrs) do
    supplied? = Map.has_key?(attrs, field) or Map.has_key?(attrs, Atom.to_string(field))

    if supplied? and not ProjectAccess.eligible_delegate?(scope, project_id, get_field(changeset, field)),
      do: add_error(changeset, field, "must be a current project editor"),
      else: changeset
  end
end
