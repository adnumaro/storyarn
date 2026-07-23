defmodule Storyarn.AI.Context.Builders.Sheet do
  @moduledoc false

  alias Storyarn.AI.Context.Entity
  alias Storyarn.AI.Context.Policy
  alias Storyarn.AI.Context.SubjectRef
  alias Storyarn.Flows
  alias Storyarn.Sheets

  @default_block_fields ~w(type label value variable_name)

  @spec build(map(), SubjectRef.t(), Policy.t()) :: {:ok, map()} | {:error, atom()}
  def build(project, %SubjectRef{} = subject_ref, %Policy{} = policy) do
    case Sheets.get_context_sheet(project.id, subject_ref.subject_id) do
      nil ->
        {:error, :context_missing}

      sheet ->
        build_sheet(project.id, sheet, subject_ref.block_ids, policy)
    end
  end

  defp build_sheet(project_id, sheet, block_ids, policy) do
    with {:ok, sheet_entity} <- sheet_entity(sheet),
         {:ok, block_entities, missing_blocks} <-
           block_entities(project_id, sheet.id, block_ids, policy),
         {:ok, reference_entities, reference_excluded} <-
           reference_entities(project_id, block_entities, policy) do
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

  defp sheet_entity(sheet) do
    Entity.new(
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

  defp block_entities(project_id, sheet_id, block_ids, policy) do
    blocks = Sheets.list_context_blocks(project_id, sheet_id, block_ids, policy.max_entities + 1)
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

        case Entity.new(
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

  defp reference_entities(project_id, block_entities, policy) do
    targets =
      block_entities
      |> Enum.flat_map(&reference_target/1)
      |> Enum.uniq()
      |> Enum.sort()

    loaded = load_reference_targets(project_id, targets, policy.max_entities + 1)

    targets
    |> Enum.reduce_while({:ok, [], []}, fn {type, id}, {:ok, entities, excluded} ->
      case reference_entity(loaded, type, id) do
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
        |> Sheets.list_context_sheets(sheet_ids, limit)
        |> Map.new(&{&1.id, &1}),
      "flow" =>
        project_id
        |> Flows.list_context_flows(flow_ids, limit)
        |> Map.new(&{&1.id, &1})
    }
  end

  defp reference_target(%Entity{content: %{"type" => "reference", "value" => value}}) when is_map(value) do
    with type when type in ["sheet", "flow"] <- value["target_type"] || value[:target_type],
         {:ok, id} <- normalize_id(value["target_id"] || value[:target_id]) do
      [{type, id}]
    else
      _invalid -> []
    end
  end

  defp reference_target(_entity), do: []

  defp reference_entity(loaded, "sheet", id) do
    case get_in(loaded, ["sheet", id]) do
      nil ->
        :missing

      sheet ->
        Entity.new(
          "sheet",
          sheet.id,
          %{"name" => sheet.name, "shortcut" => sheet.shortcut},
          required: true,
          priority: 2,
          revision: sheet.updated_at
        )
    end
  end

  defp reference_entity(loaded, "flow", id) do
    case get_in(loaded, ["flow", id]) do
      nil ->
        :missing

      flow ->
        Entity.new(
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
