defmodule Storyarn.AI.Governance.Adapters.Postgres.PolicyLock do
  @moduledoc "PostgreSQL advisory lock serializing one workspace AI-policy transition."

  alias Storyarn.Repo

  @namespace 981_004

  @spec lock!(pos_integer()) :: Postgrex.Result.t()
  def lock!(workspace_id) when is_integer(workspace_id) and workspace_id > 0 do
    Repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [@namespace, workspace_id])
  end
end
