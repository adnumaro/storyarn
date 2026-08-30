defmodule Storyarn.Projects.SceneEntityReferenceTracker do
  @moduledoc """
  Project-owned reconstruction writer for Scene entity references.

  Project import and exact restore rebuild this projection from their own Scene
  persistence records. The extraction rules intentionally duplicate the Scene
  context so Project reconstitution neither calls `Storyarn.Scenes` nor borrows
  Sheet-owned reference behavior.
  """

  import Ecto.Query

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Persistence.EntityReferenceRecord
  alias Storyarn.Projects.Persistence.FlowRecord
  alias Storyarn.Projects.Persistence.SceneRecord
  alias Storyarn.Projects.Persistence.SheetRecord
  alias Storyarn.Projects.SceneVariableNamespaceResolver
  alias Storyarn.Repo

  @reference_schemas [
    {"flow", FlowRecord},
    {"scene", SceneRecord},
    {"sheet", SheetRecord}
  ]

  @max_pg_bigint 9_223_372_036_854_775_807

  @spec update_pin_references(map(), keyword()) :: :ok | {:error, term()}
  def update_pin_references(pin, opts \\ [])

  def update_pin_references(%{id: pin_id} = pin, opts) when is_integer(pin_id) do
    replace_references("scene_pin", pin_id, pin_references(pin), opts)
  end

  def update_pin_references(_pin, _opts), do: :ok

  @spec update_zone_references(map(), keyword()) :: :ok | {:error, term()}
  def update_zone_references(zone, opts \\ [])

  def update_zone_references(%{id: zone_id} = zone, opts) when is_integer(zone_id) do
    replace_references("scene_zone", zone_id, zone_references(zone, opts), opts)
  end

  def update_zone_references(_zone, _opts), do: :ok

  defp replace_references(source_type, source_id, references, opts) do
    project_id = Keyword.get(opts, :project_id)

    with :ok <- validate_project_id(project_id),
         :ok <- ensure_transaction(),
         {:ok, normalized} <- normalize_and_lock(project_id, references) do
      Repo.delete_all(
        from reference in EntityReferenceRecord,
          where:
            reference.source_type == ^source_type and
              reference.source_id == ^source_id
      )

      insert_references(source_type, source_id, normalized)
    end
  end

  defp validate_project_id(project_id) when is_integer(project_id) and project_id > 0, do: :ok
  defp validate_project_id(project_id), do: {:error, {:invalid_project_id, project_id}}

  defp ensure_transaction do
    if Repo.in_transaction?(),
      do: :ok,
      else: {:error, :transaction_required}
  end

  # Unresolvable or inactive targets are silently dropped rather than rejected:
  # scene pins and zones may legitimately hold references to trashed flows and
  # sheets (surfaced by the stale_* health codes), and project reconstruction
  # must reproduce that state instead of aborting on it.
  defp normalize_and_lock(project_id, references) do
    normalized =
      references
      |> Enum.uniq_by(&{&1.type, &1.id, &1.context})
      |> Enum.flat_map(fn reference ->
        case normalize_reference_id(reference.id) do
          {:ok, id} -> [%{reference | id: id}]
          :error -> []
        end
      end)

    lock_references(project_id, normalized)
  end

  defp normalize_reference_id(id) when is_integer(id) and id > 0 and id <= @max_pg_bigint, do: {:ok, id}

  defp normalize_reference_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} when parsed > 0 and parsed <= @max_pg_bigint -> {:ok, parsed}
      _invalid -> :error
    end
  end

  defp normalize_reference_id(_id), do: :error

  defp lock_references(project_id, normalized) do
    allowed =
      Enum.reduce(@reference_schemas, MapSet.new(), fn {type, schema}, allowed ->
        ids =
          normalized
          |> Enum.filter(&(&1.type == type))
          |> Enum.map(& &1.id)
          |> Enum.uniq()
          |> Enum.sort()

        locked_ids = lock_active_ids(schema, project_id, ids)
        Enum.reduce(locked_ids, allowed, &MapSet.put(&2, {type, &1}))
      end)

    {:ok, Enum.filter(normalized, &MapSet.member?(allowed, {&1.type, &1.id}))}
  end

  defp lock_active_ids(_schema, _project_id, []), do: []

  defp lock_active_ids(schema, project_id, ids) do
    Repo.all(
      from target in schema,
        where:
          target.id in ^ids and target.project_id == ^project_id and
            is_nil(target.deleted_at),
        order_by: [asc: target.id],
        lock: "FOR SHARE",
        select: target.id
    )
  end

  defp insert_references(_source_type, _source_id, []), do: :ok

  defp insert_references(source_type, source_id, references) do
    now = DateTime.to_naive(TimeHelpers.now())

    entries =
      Enum.map(references, fn reference ->
        %{
          source_type: source_type,
          source_id: source_id,
          target_type: reference.type,
          target_id: reference.id,
          context: reference.context,
          inserted_at: now,
          updated_at: now
        }
      end)

    case Repo.insert_all(EntityReferenceRecord, entries, on_conflict: :nothing) do
      {count, _rows} when count >= 0 and count <= length(entries) -> :ok
      result -> {:error, {:entity_reference_insert_count_mismatch, length(entries), result}}
    end
  end

  defp pin_references(pin) do
    []
    |> maybe_add_reference("flow", Map.get(pin, :flow_id), "target")
    |> maybe_add_reference("sheet", Map.get(pin, :sheet_id), "display")
  end

  defp zone_references(zone, opts) do
    project_id = Keyword.get(opts, :project_id)

    []
    |> maybe_add_reference(Map.get(zone, :target_type), Map.get(zone, :target_id), "target")
    |> Kernel.++(zone_action_references(zone, project_id))
  end

  defp zone_action_references(%{action_type: "action", action_data: action_data}, project_id) when is_map(action_data) do
    assignments = Map.get(action_data, "assignments", [])

    namespaces =
      Enum.flat_map(assignments, fn assignment ->
        read_namespace =
          if assignment["value_type"] == "variable_ref",
            do: assignment["value_sheet"]

        [assignment["sheet"], read_namespace]
      end)

    sheet_ids = SceneVariableNamespaceResolver.resolve_sheet_ids(project_id, namespaces)

    assignments
    |> Enum.flat_map(fn assignment ->
      []
      |> maybe_add_assignment_source(sheet_ids, assignment)
      |> add_resolved_sheet(sheet_ids, assignment["sheet"], "assignment")
    end)
    |> Enum.uniq_by(&{&1.type, &1.id})
  end

  defp zone_action_references(%{action_type: "display", action_data: action_data}, project_id) when is_map(action_data) do
    with variable_ref when is_binary(variable_ref) and variable_ref != "" <-
           Map.get(action_data, "variable_ref"),
         [namespace, _variable] <- String.split(variable_ref, ".", parts: 2),
         sheet_id when is_integer(sheet_id) <-
           SceneVariableNamespaceResolver.resolve_sheet_id(project_id, namespace) do
      [%{type: "sheet", id: sheet_id, context: "display"}]
    else
      _absent_or_invalid -> []
    end
  end

  defp zone_action_references(%{action_type: "collection", action_data: %{"items" => items}}, _project_id)
       when is_list(items) do
    items
    |> Enum.flat_map(fn
      %{"sheet_id" => sheet_id} when is_integer(sheet_id) ->
        [%{type: "sheet", id: sheet_id, context: "collection_item"}]

      _item ->
        []
    end)
    |> Enum.uniq_by(&{&1.type, &1.id})
  end

  defp zone_action_references(_zone, _project_id), do: []

  defp maybe_add_assignment_source(references, sheet_ids, %{"value_type" => "variable_ref"} = assignment),
    do: add_resolved_sheet(references, sheet_ids, assignment["value_sheet"], "assignment_source")

  defp maybe_add_assignment_source(references, _sheet_ids, _assignment), do: references

  defp add_resolved_sheet(references, sheet_ids, namespace, context) do
    case Map.fetch(sheet_ids, namespace) do
      {:ok, sheet_id} -> [%{type: "sheet", id: sheet_id, context: context} | references]
      :error -> references
    end
  end

  defp maybe_add_reference(references, type, id, context) when type in ["flow", "scene", "sheet"] and not is_nil(id),
    do: [%{type: type, id: id, context: context} | references]

  defp maybe_add_reference(references, _type, _id, _context), do: references
end
