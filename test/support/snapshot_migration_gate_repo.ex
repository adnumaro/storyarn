defmodule Storyarn.SnapshotMigrationGateRepo do
  @moduledoc false

  @migration_response_key {__MODULE__, :migration_response}
  @readiness_response_key {__MODULE__, :readiness_response}

  def configure(migration_response, readiness_response \\ {:ok, %{rows: []}}) do
    Process.put(@migration_response_key, migration_response)
    Process.put(@readiness_response_key, readiness_response)
    :ok
  end

  def query(statement, [20_260_805_130_000]) when is_binary(statement) do
    if String.contains?(statement, "schema_migrations") do
      Process.get(@migration_response_key, {:ok, %{rows: [[false]]}})
    else
      Process.get(@readiness_response_key, {:ok, %{rows: []}})
    end
  end

  def query(_statement, _params) do
    Process.get(@readiness_response_key, {:ok, %{rows: []}})
  end
end
