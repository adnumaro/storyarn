defmodule Storyarn.Projects.Imports.ImportAttemptQueries do
  @moduledoc false

  alias Storyarn.Projects.Imports.ProjectImportAttempt
  alias Storyarn.Projects.Memberships
  alias Storyarn.Repo

  def get_import_attempt(%{user: _} = scope, attempt_id) do
    with %ProjectImportAttempt{} = attempt <- Repo.get(ProjectImportAttempt, attempt_id),
         {:ok, _project, _membership} <- Memberships.authorize(scope, attempt.project_id, :view),
         true <- ProjectImportAttempt.owned_or_ownerless?(attempt, scope.user.id) do
      {:ok, attempt}
    else
      nil -> {:error, :not_found}
      false -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end
end
