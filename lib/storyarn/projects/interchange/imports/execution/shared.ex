defmodule Storyarn.Projects.Imports.Shared do
  @moduledoc """
  Small helpers used by more than one part of the import pipeline.

  Deliberately tiny: anything with a policy in it belongs to the module that
  owns that policy, not here.
  """

  alias Storyarn.Projects.Imports.ImportPlan
  alias Storyarn.Projects.Imports.PlanStorage
  alias Storyarn.Projects.Imports.ProjectImportAttempt
  alias Storyarn.Repo

  @plan_binding_domain "storyarn:import-plan:attempt-binding:v2"

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

  @doc "Binds a plan to its unique encrypted-storage identity and exact persisted content."
  @spec bind_plan_to_attempt(ImportPlan.t(), String.t()) ::
          {:ok, ImportPlan.t()} | {:error, :import_plan_storage_failed}
  def bind_plan_to_attempt(%ImportPlan{} = plan, plan_storage_key) when is_binary(plan_storage_key) do
    with {:ok, canonical_payload} <- PlanStorage.canonical_binding_payload(plan) do
      {:ok, %{plan | attempt_binding: expected_plan_binding(plan_storage_key, canonical_payload)}}
    end
  end

  @doc """
  Confirms a loaded plan is the one the attempt was created from.

  The attempt and its plan live in different stores. If they ever disagree the
  import is rejected rather than materialized against a plan the preview never
  described.
  """
  def validate_attempt_plan_binding(attempt, plan) do
    with true <- attempt.format == to_string(plan.format),
         true <- attempt.parser_version == plan.parser_version,
         true <- attempt.source_kind == to_string(plan.source_kind),
         {:ok, canonical_payload} <- PlanStorage.canonical_binding_payload(plan),
         true <- valid_plan_binding?(attempt.plan_storage_key, plan.attempt_binding, canonical_payload) do
      :ok
    else
      _mismatch_or_invalid_payload -> {:error, :invalid_import_review}
    end
  end

  defp valid_plan_binding?(plan_storage_key, stored_binding, canonical_payload)
       when is_binary(plan_storage_key) and is_binary(stored_binding) and byte_size(stored_binding) == 64 do
    Plug.Crypto.secure_compare(expected_plan_binding(plan_storage_key, canonical_payload), stored_binding)
  end

  defp valid_plan_binding?(_plan_storage_key, _stored_binding, _canonical_payload), do: false

  defp expected_plan_binding(plan_storage_key, canonical_payload) do
    secret = Application.fetch_env!(:storyarn, :import_idempotency_secret)

    :hmac
    |> :crypto.mac(:sha256, secret, [@plan_binding_domain, <<0>>, plan_storage_key, <<0>>, canonical_payload])
    |> Base.encode16(case: :lower)
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
