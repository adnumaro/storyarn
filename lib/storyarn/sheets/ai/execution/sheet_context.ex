defmodule Storyarn.Sheets.AI.SheetContext do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Repo
  alias Storyarn.Sheets.AI.ContextContract
  alias Storyarn.Sheets.AI.Data.FlowRecord
  alias Storyarn.Sheets.AI.Queries.Context

  @default_block_fields ~w(type label value variable_name)

  @spec build(map(), map(), map(), function()) :: {:ok, map()} | {:error, atom()}
  def build(project, subject_ref, policy, entity_builder) do
    case Context.get_sheet_brief(project.id, subject_ref.subject_id) do
      nil ->
        {:error, :context_missing}

      sheet ->
        build_sheet(project.id, sheet, ContextContract.block_ids(subject_ref), policy, entity_builder)
    end
  end

  defp build_sheet(project_id, sheet, block_ids, policy, entity_builder) do
    with {:ok, sheet_entity} <- sheet_entity(sheet, entity_builder),
         {:ok, block_entities, missing_blocks} <-
           block_entities(project_id, sheet.id, block_ids, policy, entity_builder),
         {:ok, reference_entities, reference_excluded} <-
           reference_entities(project_id, sheet.id, block_entities, policy, entity_builder) do
      excluded = missing_blocks ++ reference_excluded
      warnings = if excluded == [], do: [], else: ["stale_reference"]

      {:ok,
       %{
         entities: [sheet_entity] ++ block_entities ++ reference_entities,
         excluded: excluded,
         warnings: warnings
       }}
    end
  end

  defp sheet_entity(sheet, entity_builder) do
    entity_builder.(
      "sheet",
      sheet.id,
      %{
        "name" => sheet.name,
        "shortcut" => sheet.shortcut,
        "description" => sheet.description
      },
      required: true,
      priority: 1,
      revision: sheet.updated_at
    )
  end

  defp block_entities(project_id, sheet_id, block_ids, policy, entity_builder) do
    blocks = Context.list_blocks(project_id, sheet_id, block_ids, policy.max_entities + 1)
    loaded_ids = MapSet.new(blocks, & &1.id)

    missing =
      block_ids
      |> Enum.reject(&MapSet.member?(loaded_ids, &1))
      |> Enum.map(&%{"type" => "sheet_block", "id" => &1, "reason" => "stale_reference"})

    fields = Map.get(policy.fields, :sheet_blocks, @default_block_fields)

    result =
      Enum.reduce_while(blocks, {:ok, []}, fn block, {:ok, acc} ->
        content =
          Map.take(
            %{
              "type" => block.type,
              "label" => get_in(block.config, ["label"]),
              "value" => block.value,
              "variable_name" => block.variable_name
            },
            fields
          )

        case entity_builder.(
               "sheet_block",
               block.id,
               content,
               required: true,
               priority: 1,
               revision: block.updated_at
             ) do
          {:ok, entity} -> {:cont, {:ok, [entity | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, entities} -> {:ok, Enum.reverse(entities), missing}
      {:error, reason} -> {:error, reason}
    end
  end

  defp reference_entities(project_id, source_sheet_id, block_entities, policy, entity_builder) do
    targets =
      block_entities
      |> Enum.flat_map(&reference_target/1)
      |> Enum.uniq()
      |> Enum.reject(&(&1 == {"sheet", source_sheet_id}))
      |> Enum.sort()

    loaded = load_reference_targets(project_id, targets, policy.max_entities + 1)

    targets
    |> Enum.reduce_while({:ok, [], []}, fn {type, id}, {:ok, entities, excluded} ->
      case reference_entity(loaded, type, id, entity_builder) do
        {:ok, entity} -> {:cont, {:ok, [entity | entities], excluded}}
        :missing -> {:cont, {:ok, entities, [stale_reference(type, id) | excluded]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, entities, excluded} ->
        {:ok, Enum.reverse(entities), Enum.sort_by(excluded, &{&1["type"], &1["id"]})}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load_reference_targets(project_id, targets, limit) do
    sheet_ids = for {"sheet", id} <- targets, do: id
    flow_ids = for {"flow", id} <- targets, do: id

    %{
      "sheet" =>
        project_id
        |> Context.list_sheet_briefs(sheet_ids, limit)
        |> Map.new(&{&1.id, &1}),
      "flow" =>
        project_id
        |> list_flow_briefs(flow_ids, limit)
        |> Map.new(&{&1.id, &1})
    }
  end

  defp list_flow_briefs(_project_id, [], _limit), do: []

  defp list_flow_briefs(project_id, flow_ids, limit) do
    Repo.all(
      from(flow in FlowRecord,
        where:
          flow.project_id == ^project_id and flow.id in ^flow_ids and
            is_nil(flow.deleted_at),
        order_by: [asc: flow.id],
        limit: ^limit
      )
    )
  end

  defp reference_target(%{content: %{"type" => "reference", "value" => value}}) when is_map(value) do
    with type when type in ["sheet", "flow"] <- value["target_type"] || value[:target_type],
         {:ok, id} <- normalize_id(value["target_id"] || value[:target_id]) do
      [{type, id}]
    else
      _invalid -> []
    end
  end

  defp reference_target(_entity), do: []

  defp reference_entity(loaded, "sheet", id, entity_builder) do
    case get_in(loaded, ["sheet", id]) do
      nil ->
        :missing

      sheet ->
        entity_builder.(
          "sheet",
          sheet.id,
          %{"name" => sheet.name, "shortcut" => sheet.shortcut},
          required: true,
          priority: 2,
          revision: sheet.updated_at
        )
    end
  end

  defp reference_entity(loaded, "flow", id, entity_builder) do
    case get_in(loaded, ["flow", id]) do
      nil ->
        :missing

      flow ->
        entity_builder.(
          "flow",
          flow.id,
          %{"name" => flow.name, "shortcut" => flow.shortcut},
          required: true,
          priority: 2,
          revision: flow.updated_at
        )
    end
  end

  defp stale_reference(type, id), do: %{"type" => type, "id" => id, "reason" => "stale_reference"}

  defp normalize_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp normalize_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> {:ok, id}
      _other -> :error
    end
  end

  defp normalize_id(_value), do: :error
end
