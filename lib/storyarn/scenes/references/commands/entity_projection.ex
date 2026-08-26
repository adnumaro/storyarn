defmodule Storyarn.Scenes.References.Commands.EntityProjection do
  @moduledoc """
  Scene-owned entity-reference projection for pins and zones.

  Rows remain in the shared `entity_references` table, while extraction and
  writes are expressed only in Scene vocabulary and local persistence records.
  """

  import Ecto.Query

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo
  alias Storyarn.Scenes.References.Commands.ProjectIntegrity
  alias Storyarn.Scenes.References.Data.EntityReferenceRecord
  alias Storyarn.Scenes.References.Queries.VariableNamespaces

  def update_pin_references(pin, opts \\ [])

  def update_pin_references(%{id: pin_id} = pin, opts) when is_integer(pin_id) do
    replace_references("scene_pin", pin_id, pin_references(pin), opts)
  end

  def update_pin_references(_pin, _opts), do: :ok

  def delete_pin_references(pin_id) when is_integer(pin_id) do
    Repo.delete_all(
      from reference in EntityReferenceRecord,
        where: reference.source_type == "scene_pin" and reference.source_id == ^pin_id
    )
  end

  def update_zone_references(zone, opts \\ [])

  def update_zone_references(%{id: zone_id} = zone, opts) when is_integer(zone_id) do
    replace_references("scene_zone", zone_id, zone_references(zone, opts), opts)
  end

  def update_zone_references(_zone, _opts), do: :ok

  def delete_zone_references(zone_id) when is_integer(zone_id) do
    Repo.delete_all(
      from reference in EntityReferenceRecord,
        where: reference.source_type == "scene_zone" and reference.source_id == ^zone_id
    )
  end

  defp replace_references(source_type, source_id, references, opts) do
    project_id = Keyword.get(opts, :project_id)

    with :ok <- validate_project_id(project_id),
         :ok <- ensure_transaction(),
         {:ok, normalized} <- normalize_and_lock(project_id, source_type, source_id, references) do
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

  defp normalize_and_lock(project_id, source_type, source_id, references) do
    references = Enum.uniq_by(references, &{&1.type, &1.id, &1.context})

    specs =
      Enum.map(references, fn reference ->
        type = reference_type(reference.type)
        {type, {source_type, source_id, reference.context}, reference.id}
      end)

    # Filtering, not erroring: stale references to trashed targets are legal
    # data (surfaced by the stale_* health codes). The save-time guards in
    # SceneReferenceIntegrity own rejection; the projection just skips them.
    ids = ProjectIntegrity.lock_active_reference_ids(project_id, specs)

    normalized =
      references
      |> Enum.zip(ids)
      |> Enum.map(fn {reference, id} -> %{reference | id: id} end)
      |> Enum.reject(&is_nil(&1.id))
      |> Enum.uniq_by(&{&1.type, &1.id, &1.context})

    {:ok, normalized}
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
        read_namespace = if assignment["value_type"] == "variable_ref", do: assignment["value_sheet"]
        [assignment["sheet"], read_namespace]
      end)

    sheet_ids = VariableNamespaces.resolve_sheet_ids(project_id, namespaces)

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
           VariableNamespaces.resolve_sheet_id(project_id, namespace) do
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

  defp reference_type("flow"), do: :flow
  defp reference_type("scene"), do: :scene
  defp reference_type("sheet"), do: :sheet
end
