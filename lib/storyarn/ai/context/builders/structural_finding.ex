defmodule Storyarn.AI.Context.Builders.StructuralFinding do
  @moduledoc false

  alias Storyarn.AI.Context.Entity
  alias Storyarn.AI.Context.Policy
  alias Storyarn.AI.Context.SubjectRef

  @spec build(map(), SubjectRef.t(), Policy.t()) :: {:ok, map()} | {:error, atom()}
  def build(_project, %SubjectRef{} = subject_ref, %Policy{} = policy) do
    if length(subject_ref.evidence) > policy.max_fan_out do
      {:error, :context_too_large}
    else
      with {:ok, finding} <-
             Entity.new(
               "structural_finding",
               subject_ref.subject_id,
               subject_ref.finding,
               required: true,
               priority: 1
             ),
           {:ok, evidence} <- evidence_entities(subject_ref.evidence) do
        {:ok, %{entities: [finding | evidence], excluded: [], warnings: []}}
      end
    end
  end

  defp evidence_entities(evidence) do
    evidence
    |> Enum.sort_by(&{value(&1, :type), value(&1, :id)})
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case Entity.new(
             value(item, :type),
             value(item, :id),
             value(item, :content),
             required: true,
             priority: 1,
             revision: value(item, :revision)
           ) do
        {:ok, entity} -> {:cont, {:ok, [entity | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, entities} -> {:ok, Enum.reverse(entities)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
