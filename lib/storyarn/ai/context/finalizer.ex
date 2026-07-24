defmodule Storyarn.AI.Context.Finalizer do
  @moduledoc false

  alias Storyarn.Shared.CanonicalJSON
  alias Storyarn.AI.Context.Entity
  alias Storyarn.AI.Context.Package
  alias Storyarn.AI.Context.Policy

  @package_version "storyarn-context-v1"

  @spec finalize(Policy.t(), String.t(), [Entity.t()], [map()], [String.t()]) ::
          {:ok, Package.t()}
          | {:error, :context_too_large | :context_serialization_failed | :invalid_context_entities}
  def finalize(%Policy{} = policy, context_version, entities, excluded \\ [], warnings \\ []) do
    entities = Enum.sort_by(entities, &sort_key/1)
    required = Enum.filter(entities, & &1.required?)
    optional = Enum.reject(entities, & &1.required?)

    with :ok <- unique_entity_keys(entities),
         :ok <- required_entity_limit(required, policy),
         {:ok, required_bytes} <- payload_size(policy.scope, required),
         :ok <- required_byte_limit(required_bytes, policy),
         {included, excluded, truncated?} <- include_optional(required, optional, excluded, policy),
         {:ok, payload} <- payload(policy.scope, included),
         {:ok, encoded_payload} <- CanonicalJSON.encode(payload),
         manifest = manifest(included, excluded),
         warnings =
           warnings
           |> maybe_add_warning(truncated?, "optional_context_truncated")
           |> Enum.uniq()
           |> Enum.sort(),
         {:ok, hash} <- context_hash(context_version, payload, manifest, warnings) do
      {:ok,
       %Package{
         version: @package_version,
         context_version: context_version,
         scope: policy.scope,
         payload: payload,
         manifest: manifest,
         serialized_bytes: byte_size(encoded_payload),
         token_count: token_count(policy.tokenizer, encoded_payload),
         hash: hash,
         warnings: warnings
       }}
    else
      {:error, :invalid_structured_input} -> {:error, :context_serialization_failed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp include_optional(required, optional, excluded, policy) do
    optional
    |> Enum.reduce(
      {required, excluded, false},
      &include_optional_entity(&1, &2, policy)
    )
    |> then(fn {included, dropped, truncated?} ->
      {included, Enum.sort_by(dropped, &excluded_sort_key/1), truncated?}
    end)
  end

  defp payload(scope, entities) do
    {:ok,
     %{
       "version" => @package_version,
       "scope" => Atom.to_string(scope),
       "entities" => Enum.map(entities, &Entity.payload/1)
     }}
  end

  defp include_optional_entity(entity, {included, dropped, _truncated?}, policy)
       when length(included) >= policy.max_entities do
    {included, [excluded(entity, "entity_limit") | dropped], true}
  end

  defp include_optional_entity(entity, {included, dropped, truncated?}, policy) do
    case payload_size(policy.scope, included ++ [entity]) do
      {:ok, size} when size <= policy.max_bytes ->
        {included ++ [entity], dropped, truncated?}

      {:ok, _size} ->
        {included, [excluded(entity, "byte_limit") | dropped], true}

      {:error, _reason} ->
        {included, [excluded(entity, "serialization_failed") | dropped], true}
    end
  end

  defp payload_size(scope, entities) do
    with {:ok, payload} <- payload(scope, entities),
         {:ok, encoded} <- CanonicalJSON.encode(payload) do
      {:ok, byte_size(encoded)}
    else
      {:error, _reason} -> {:error, :context_serialization_failed}
    end
  end

  defp manifest(included, excluded) do
    included_keys = MapSet.new(included, &{&1.type, &1.id})

    excluded =
      excluded
      |> Enum.reject(&MapSet.member?(included_keys, {&1["type"], &1["id"]}))
      |> Enum.uniq_by(&{&1["type"], &1["id"], &1["reason"]})
      |> Enum.sort_by(&excluded_sort_key/1)

    %{
      included: Enum.map(included, &Entity.manifest/1),
      excluded: excluded
    }
  end

  defp context_hash(context_version, payload, manifest, warnings) do
    CanonicalJSON.hash(%{
      "version" => @package_version,
      "context_version" => context_version,
      "payload" => payload,
      "warnings" => warnings,
      "manifest" => %{
        "included" => manifest.included,
        "excluded" => manifest.excluded
      }
    })
  end

  defp required_entity_limit(required, policy) do
    if length(required) <= policy.max_entities, do: :ok, else: {:error, :context_too_large}
  end

  defp unique_entity_keys(entities) do
    keys = Enum.map(entities, &{&1.type, &1.id})

    if Enum.uniq(keys) == keys, do: :ok, else: {:error, :invalid_context_entities}
  end

  defp required_byte_limit(bytes, policy) do
    if bytes <= policy.max_bytes, do: :ok, else: {:error, :context_too_large}
  end

  defp token_count(nil, _encoded), do: nil

  defp token_count(tokenizer, encoded) do
    case tokenizer.count(encoded) do
      count when is_integer(count) and count >= 0 -> count
      _invalid -> nil
    end
  rescue
    _exception -> nil
  end

  defp excluded(entity, reason) do
    %{
      "type" => entity.type,
      "id" => entity.id,
      "reason" => reason
    }
  end

  defp sort_key(entity), do: {not entity.required?, entity.priority, entity.type, entity.id}
  defp excluded_sort_key(item), do: {item["reason"], item["type"], item["id"]}
  defp maybe_add_warning(warnings, true, warning), do: [warning | warnings]
  defp maybe_add_warning(warnings, false, _warning), do: warnings
end
