defmodule Storyarn.Imports.Shared do
  @moduledoc """
  Small helpers used by more than one part of the import pipeline.

  Deliberately tiny: anything with a policy in it belongs to the module that
  owns that policy, not here.
  """

  alias Storyarn.Imports.ImportPlan
  alias Storyarn.Imports.ProjectImportAttempt
  alias Storyarn.Repo

  @doc "Loads an attempt with the associations the worker and telemetry need."
  @spec get_attempt(pos_integer()) :: ProjectImportAttempt.t() | nil
  def get_attempt(attempt_id) do
    case Repo.get(ProjectImportAttempt, attempt_id) do
      nil -> nil
      %ProjectImportAttempt{} = attempt -> Repo.preload(attempt, [:user, :project])
    end
  end

  @doc "Maps the persisted conflict strategy onto the atom the materializer takes."
  @spec strategy_atom(String.t()) :: :skip | :overwrite | :rename
  def strategy_atom("skip"), do: :skip
  def strategy_atom("overwrite"), do: :overwrite
  def strategy_atom("rename"), do: :rename

  @doc "Stringifies top-level keys before they are stored in a `:map` column."
  @spec stringify_keys(map()) :: map()
  def stringify_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  @doc """
  Confirms a loaded plan is the one the attempt was created from.

  The attempt and its plan live in different stores. If they ever disagree the
  import is rejected rather than materialized against a plan the preview never
  described.
  """
  def validate_attempt_plan_binding(attempt, plan) do
    if attempt.format == to_string(plan.format) and
         attempt.parser_version == plan.parser_version and
         attempt.source_kind == to_string(plan.source_kind) do
      :ok
    else
      {:error, :invalid_import_review}
    end
  end

  @doc """
  Loads a stored plan, converting every failure mode into one error.

  Object storage can fail in ways the import pipeline has no answer for, and an
  exception escaping here would replace whatever error was already being
  handled. Anything other than a decoded plan is `:import_plan_unavailable`.
  """
  def safely_load_plan(plan_load, storage_key) when is_function(plan_load, 1) do
    case plan_load.(storage_key) do
      {:ok, %ImportPlan{} = plan} -> {:ok, plan}
      _failure -> {:error, :import_plan_unavailable}
    end
  rescue
    _exception -> {:error, :import_plan_unavailable}
  catch
    _kind, _reason -> {:error, :import_plan_unavailable}
  end

  def safely_load_plan(_invalid_plan_load, _storage_key), do: {:error, :import_plan_unavailable}
end
