defmodule Storyarn.Versioning.VersionNumberLock do
  @moduledoc false

  alias Storyarn.Repo

  @entity_version_namespace 981_001
  @project_snapshot_namespace 981_002
  @max_lock_key 2_147_483_647

  @spec entity_version(String.t(), integer(), (-> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def entity_version(entity_type, entity_id, fun) when is_function(fun, 0) do
    transaction(@entity_version_namespace, {entity_type, entity_id}, fun)
  end

  @spec project_snapshot(integer(), (-> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def project_snapshot(project_id, fun) when is_function(fun, 0) do
    transaction(@project_snapshot_namespace, project_id, fun)
  end

  defp transaction(namespace, key, fun) do
    Repo.transaction(fn ->
      lock!(namespace, key)

      case fun.() do
        {:ok, result} -> result
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp lock!(namespace, key) do
    Repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [
      namespace,
      :erlang.phash2(key, @max_lock_key)
    ])

    :ok
  end
end
