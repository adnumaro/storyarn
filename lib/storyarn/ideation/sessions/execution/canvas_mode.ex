defmodule Storyarn.Ideation.Sessions.Execution.CanvasMode do
  @moduledoc false
  import Ecto.Changeset

  alias Storyarn.Ideation.Sessions.Execution.Mutation
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Repo

  # Ideas holds the contribution/session lock and owns the surrounding transaction.
  def set(access, expected, enabled) do
    cond do
      not Repo.in_transaction?() ->
        {:error, :contribution_transaction_required}

      not (access.owner? or access.facilitator_id == access.user_id) ->
        {:error, :unauthorized}

      expected != access.session_revision ->
        {:error, :stale_revision}

      not is_boolean(enabled) ->
        {:error, :invalid_parameters}

      access.configuration.private_mode == enabled ->
        {:ok, %{id: access.session_id, changed: false}}

      true ->
        session = Repo.get!(Session, access.session_id)
        configuration = %{private_mode: enabled}

        updated =
          session
          |> change(revision: session.revision + 1, configuration_version: session.configuration_version + 1)
          |> put_embed(:configuration, configuration)
          |> Repo.update!()

        with {:ok, _} <- Mutation.record(updated, access.user_id, :updated),
             do: {:ok, %{id: session.id, changed: true}}
    end
  end
end
