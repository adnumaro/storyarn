defmodule Storyarn.Ideation.Ideas.Commands.Reveal do
  @moduledoc false
  import Storyarn.Ideation.Ideas.Rules.Input, only: [valid_id: 1]

  alias Storyarn.Ideation.Ideas.Execution.Publication
  alias Storyarn.Ideation.Ideas.Execution.RevealManifest
  alias Storyarn.Ideation.Ideas.Execution.Transaction
  alias Storyarn.Ideation.Ideas.Reveal
  alias Storyarn.Ideation.Ideas.View
  alias Storyarn.Repo

  def run(scope, project_id, session_id, operation_id) when valid_id(operation_id) do
    Transaction.run(scope, project_id, session_id, &reveal_locked(&1, operation_id))
  end

  def run(_scope, _project_id, _session_id, _operation_id), do: {:error, :not_found}

  defp reveal_locked(access, operation_id) do
    case Repo.get_by(Reveal, session_id: access.session_id, actor_id: access.user_id, id: operation_id) do
      nil ->
        {:error, :not_found}

      %{status: :completed} = operation ->
        Transaction.success(View.reveal(operation))

      operation ->
        if(access.configuration.private_mode, do: {:error, :session_private}, else: execute(operation, access))
    end
  end

  defp execute(operation, access) do
    with {:ok, ideas} <- RevealManifest.validate(operation.manifest, access) do
      {completed, changed?} = Publication.publish(operation, ideas, access.user_id)
      Transaction.success(View.reveal(completed), if(changed?, do: [:shared], else: []))
    end
  end
end
