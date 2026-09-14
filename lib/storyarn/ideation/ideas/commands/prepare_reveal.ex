defmodule Storyarn.Ideation.Ideas.Commands.PrepareReveal do
  @moduledoc false
  alias Storyarn.Ideation.Ideas.Execution.RevealManifest
  alias Storyarn.Ideation.Ideas.Execution.Transaction
  alias Storyarn.Ideation.Ideas.Reveal
  alias Storyarn.Ideation.Ideas.Rules.Input
  alias Storyarn.Ideation.Ideas.Rules.Selection
  alias Storyarn.Ideation.Ideas.View
  alias Storyarn.Repo

  def run(scope, project_id, session_id, request_key, targets) do
    with {:ok, key} <- Input.request_key(%{request_key: request_key}),
         {:ok, selection} <- Selection.normalize(targets) do
      Transaction.run(scope, project_id, session_id, &prepare_locked(&1, key, selection))
    end
  end

  defp prepare_locked(access, key, selection) do
    case Repo.get_by(Reveal, session_id: access.session_id, actor_id: access.user_id, request_key: key) do
      nil -> prepare(access, key, selection)
      %{selection: ^selection} = operation -> Transaction.success(View.reveal(operation))
      _ -> {:error, :idempotency_conflict}
    end
  end

  defp prepare(access, key, selection) do
    with {:ok, manifest} <- RevealManifest.capture(selection, access) do
      operation =
        Repo.insert!(%Reveal{
          session_id: access.session_id,
          actor_id: access.user_id,
          request_key: key,
          selection: selection,
          manifest: manifest
        })

      Transaction.success(View.reveal(operation))
    end
  end
end
