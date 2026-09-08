defmodule Storyarn.Projects.Access.Commands.LockBackgroundWrite do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Projects.Project
  alias Storyarn.Repo

  def run(project_id) when is_integer(project_id) and project_id > 0 and project_id <= 9_223_372_036_854_775_807 do
    if Repo.in_transaction?() do
      # Durable work must also serialize its terminal bookkeeping for a deleted
      # project. This lock grants no permission to execute the original action.
      case Repo.one(from p in Project, where: p.id == ^project_id, select: p.id, lock: "FOR SHARE") do
        nil -> {:error, :not_found}
        _id -> :ok
      end
    else
      {:error, :background_write_transaction_required}
    end
  end

  def run(_), do: {:error, :not_found}
end
