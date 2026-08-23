defmodule Storyarn.Sheets.Versioning.VersionNumberLock do
  @moduledoc false

  alias Storyarn.Repo

  # Preserve the namespace used by the existing entity-version writer while
  # both implementations share the same table during the migration.
  @entity_version_namespace 981_001
  @max_lock_key 2_147_483_647

  @spec run(integer(), (-> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def run(sheet_id, fun) when is_integer(sheet_id) and sheet_id > 0 and is_function(fun, 0) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [
        @entity_version_namespace,
        lock_key({"sheet", sheet_id})
      ])

      case fun.() do
        {:ok, result} -> result
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp lock_key(key), do: :erlang.phash2(key, @max_lock_key)
end
