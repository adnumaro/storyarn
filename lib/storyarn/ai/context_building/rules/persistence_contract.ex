defmodule Storyarn.AI.Context.PersistenceContract do
  @moduledoc false

  alias Storyarn.AI.Context.SubjectRef
  alias Storyarn.AI.Routing
  alias Storyarn.AI.Task

  @max_manifest_sources 1_000

  @spec valid?(String.t(), String.t() | nil, map() | nil, map() | nil) :: boolean()
  def valid?(_task_id, nil, nil, nil), do: true

  def valid?(task_id, hash, manifest, subject)
      when is_binary(task_id) and is_binary(hash) and is_map(manifest) and is_map(subject) do
    with {:ok, task} <- Routing.get_task(task_id),
         {:ok, policy} <- Task.context_policy(task),
         false <- policy.scope == :none,
         true <- context_scope(manifest) == Atom.to_string(policy.scope),
         {:ok, subject_ref} <- SubjectRef.from_persisted_map(subject, policy.contract),
         true <- policy.contract.subject_matches_policy?(subject_ref, policy),
         true <- valid_sources?(manifest, policy.contract) do
      true
    else
      _invalid -> false
    end
  end

  def valid?(_task_id, _hash, _manifest, _subject), do: false

  defp valid_sources?(manifest, contract) do
    valid_source_list?(value(manifest, :included), contract, :included) and
      valid_source_list?(value(manifest, :excluded), contract, :excluded)
  end

  defp valid_source_list?(sources, contract, location)
       when is_list(sources) and length(sources) <= @max_manifest_sources do
    Enum.all?(sources, fn
      %{} = item ->
        case value(item, :type) do
          type when is_binary(type) -> contract.source_type?(type, location)
          _invalid -> false
        end

      _invalid ->
        false
    end)
  end

  defp valid_source_list?(_sources, _contract, _location), do: false

  defp context_scope(manifest), do: value(manifest, :scope)
  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
