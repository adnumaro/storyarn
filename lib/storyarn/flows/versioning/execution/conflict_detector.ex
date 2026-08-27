defmodule Storyarn.Flows.Versioning.ConflictDetector do
  @moduledoc """
  Flow-owned, read-only preview of conflicts that would block an entity restore.

  The preview reads the shared schema through Flow records and mirrors the
  checks enforced authoritatively under locks by `FlowSnapshot.restore/3`.
  """

  use Gettext, backend: Storyarn.Gettext

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.References
  alias Storyarn.Flows.Versioning.AssetCatalog
  alias Storyarn.Flows.Versioning.FlowSnapshot
  alias Storyarn.Flows.Versioning.Projections.SceneRecord
  alias Storyarn.Flows.Versioning.Projections.SheetAvatarRecord
  alias Storyarn.Flows.Versioning.Projections.SheetRecord
  alias Storyarn.Repo

  @doc "Returns the conflict report consumed by the Flow version-history UI."
  @spec detect(map(), Flow.t()) :: map()
  def detect(snapshot, %Flow{} = flow) when is_map(snapshot) do
    references = Enum.map(FlowSnapshot.scan_references(snapshot), &normalize_reference/1)
    existing = load_existing(references, flow.project_id)

    missing =
      Enum.reject(references, &materializable?(&1, existing, snapshot, flow.project_id)) ++
        variable_conflicts(snapshot, flow.project_id)

    conflicts = group_conflicts(missing)
    {shortcut_collision, resolved_shortcut} = shortcut_collision(flow, snapshot["shortcut"])

    %{
      has_conflicts: conflicts != [] or shortcut_collision,
      conflicts: conflicts,
      shortcut_collision: shortcut_collision,
      resolved_shortcut: resolved_shortcut,
      summary: summary(conflicts, shortcut_collision)
    }
  end

  defp load_existing(references, project_id) do
    ids_by_type =
      references
      |> Enum.group_by(& &1.type, & &1.id)
      |> Map.new(fn {type, ids} ->
        {type, ids |> Enum.filter(&queryable_id?/1) |> Enum.uniq()}
      end)

    %{
      sheet: active_ids(SheetRecord, ids_by_type[:sheet] || [], project_id),
      flow: active_ids(Flow, ids_by_type[:flow] || [], project_id),
      scene: active_ids(SceneRecord, ids_by_type[:scene] || [], project_id),
      avatar: active_avatars(ids_by_type[:avatar] || [], project_id)
    }
  end

  defp active_ids(_schema, [], _project_id), do: MapSet.new()

  defp active_ids(schema, ids, project_id) do
    from(record in schema,
      where:
        record.id in ^ids and field(record, :project_id) == ^project_id and
          is_nil(field(record, :deleted_at)),
      select: record.id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp active_avatars([], _project_id), do: %{}

  defp active_avatars(ids, project_id) do
    from(avatar in SheetAvatarRecord,
      join: sheet in SheetRecord,
      on: sheet.id == avatar.sheet_id,
      where:
        avatar.id in ^ids and sheet.project_id == ^project_id and
          is_nil(sheet.deleted_at),
      select: {avatar.id, avatar.sheet_id}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp materializable?(%{type: :reference}, _existing, _snapshot, _project_id), do: false

  defp materializable?(%{type: :asset, id: id} = reference, _existing, snapshot, project_id) do
    AssetCatalog.validate_snapshot_asset_materialization(
      id,
      snapshot,
      project_id,
      expected_content_type_prefix: reference.expected_content_type_prefix,
      asset_context: reference.context
    ) == :ok
  end

  defp materializable?(%{type: :avatar, id: id, speaker_sheet_id: speaker_sheet_id}, existing, _snapshot, _project_id) do
    case existing.avatar[id] do
      sheet_id when is_integer(sheet_id) ->
        References.validate_avatar_speaker(id, sheet_id, speaker_sheet_id) == :ok

      _missing ->
        false
    end
  end

  defp materializable?(%{type: type, id: id}, existing, _snapshot, _project_id) when type in [:sheet, :flow, :scene] do
    is_integer(id) and MapSet.member?(Map.fetch!(existing, type), id)
  end

  defp materializable?(_reference, _existing, _snapshot, _project_id), do: false

  defp normalize_reference(%{id: id} = reference) do
    reference = Map.put(reference, :id, normalize_id(id))

    case reference do
      %{type: :avatar, speaker_sheet_id: speaker_sheet_id} ->
        Map.put(reference, :speaker_sheet_id, normalize_id(speaker_sheet_id))

      _other ->
        reference
    end
  end

  defp normalize_id(value) do
    case References.normalize_optional_id(value) do
      {:ok, id} -> id
      :error -> value
    end
  end

  defp queryable_id?(id) do
    case References.normalize_optional_id(id) do
      {:ok, normalized_id} when is_integer(normalized_id) -> true
      _invalid_or_absent -> false
    end
  end

  defp variable_conflicts(snapshot, project_id) do
    case References.validate_flow_node_variable_targets(
           snapshot["nodes"] || [],
           project_id
         ) do
      :ok ->
        []

      {:error, reason} ->
        [variable_conflict(reason)]
    end
  end

  defp variable_conflict({:unresolved_variable_reference, source_type, source_id, kind, source_sheet, source_variable}) do
    %{
      type: :variable,
      id: "#{source_sheet}.#{source_variable}",
      context:
        dgettext(
          "versioning",
          "%{source} #%{id} — unresolved %{kind} variable",
          source: variable_source_label(source_type),
          id: source_id,
          kind: variable_kind_label(kind)
        )
    }
  end

  defp variable_conflict({:malformed_variable_reference, source_type, source_id, _context, _value}) do
    %{
      type: :variable,
      id: nil,
      context:
        dgettext(
          "versioning",
          "%{source} #%{id} — malformed variable reference",
          source: variable_source_label(source_type),
          id: source_id
        )
    }
  end

  defp variable_conflict(_reason) do
    %{
      type: :variable,
      id: nil,
      context: dgettext("versioning", "Snapshot variable references could not be validated")
    }
  end

  defp variable_source_label("flow_node"), do: dgettext("versioning", "Flow node")
  defp variable_source_label(_source_type), do: dgettext("versioning", "Snapshot source")

  defp variable_kind_label("read"), do: dgettext("versioning", "read")
  defp variable_kind_label("write"), do: dgettext("versioning", "write")
  defp variable_kind_label(_kind), do: dgettext("versioning", "referenced")

  defp group_conflicts(conflicts) do
    conflicts
    |> Enum.group_by(&{&1.type, &1.id})
    |> Enum.map(fn {{type, id}, entries} ->
      %{type: type, id: id, contexts: entries |> Enum.map(& &1.context) |> Enum.uniq()}
    end)
    |> Enum.sort_by(&{&1.type, &1.id})
  end

  defp shortcut_collision(_flow, nil), do: {false, nil}

  defp shortcut_collision(flow, shortcut) when is_binary(shortcut) do
    collision? =
      Repo.exists?(
        from(candidate in Flow,
          where:
            candidate.project_id == ^flow.project_id and candidate.id != ^flow.id and
              candidate.shortcut == ^shortcut and is_nil(candidate.deleted_at)
        )
      )

    if collision?, do: {true, shortcut <> "-restored"}, else: {false, shortcut}
  end

  defp shortcut_collision(_flow, shortcut), do: {false, shortcut}

  defp summary([], false), do: nil

  defp summary(conflicts, shortcut_collision) do
    parts =
      conflicts
      |> Enum.group_by(& &1.type)
      |> Enum.map(fn {type, entries} -> "#{length(entries)} missing #{type}" end)

    parts = if shortcut_collision, do: parts ++ [dgettext("versioning", "shortcut collision")], else: parts
    Enum.join(parts, ", ")
  end
end
