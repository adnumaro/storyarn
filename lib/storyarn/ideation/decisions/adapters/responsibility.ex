defmodule Storyarn.Ideation.Decisions.Adapters.Responsibility do
  @moduledoc false
  alias Storyarn.Projects

  def validate(scope, project_id, responsible_id) do
    case Projects.check_editor_candidate_locked(scope, project_id, responsible_id, :nowait) do
      {:ok, true} -> :ok
      {:error, :candidate_busy} -> {:error, :responsible_busy}
      _ -> {:error, :ineligible_responsible}
    end
  end
end
