defmodule Storyarn.Sheets.References.Commands.EntityProjection do
  @moduledoc """
  Maintains the Sheet-owned entity-reference projection.

  This module provides functions to:
  - Extract references from rich_text content (mentions)
  - Extract references from reference blocks
  - Update references atomically when content changes
  - Delete projection rows when Sheet-owned sources or targets disappear

  ## Reference Lifecycle

  - References are created when blocks are saved (reference blocks, rich_text with mentions)
  - References are updated atomically when block content changes
  - References are deleted when source blocks are deleted

  Backlink reads live in `Storyarn.Sheets.References.Queries.Backlinks`. Keeping
  this module command-only makes the transaction and lock boundary explicit.
  """

  import Ecto.Query

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.References.Commands.ProjectIntegrity
  alias Storyarn.Sheets.References.Entities.EntityReferenceRecord
  alias Storyarn.Sheets.References.Projections.FlowRecord
  alias Storyarn.Sheets.References.Projections.SceneRecord
  alias Storyarn.Sheets.References.Rules.RichTextMentions
  alias Storyarn.Sheets.Sheet

  @project_target_types %{"block" => ~w(sheet flow)}

  @doc """
  Updates references from a block.

  Deletes all existing references from this block and creates new ones
  based on the current block state.
  """
  @spec update_block_references(map(), keyword()) :: :ok | {:error, term()}
  def update_block_references(block, opts \\ []) do
    block_id = block.id

    operation = fn ->
      # Delete existing references from this block
      Repo.delete_all(from(r in EntityReferenceRecord, where: r.source_type == "block" and r.source_id == ^block_id))

      # Extract and batch-insert new references
      references = extract_block_references(block)
      batch_insert_references("block", block_id, references, opts)
    end

    if Repo.in_transaction?() do
      operation.()
    else
      case Repo.transaction(operation) do
        {:ok, :ok} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Validates the entity references encoded in a prospective block value.

  This is a writer guard, not a tracker repair operation. It must run in the
  same transaction as the block write so every target stays active and in the
  source project until commit.
  """
  @spec lock_and_normalize_block_value(integer(), String.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def lock_and_normalize_block_value(project_id, "reference", value) when is_integer(project_id) and is_map(value) do
    case extract_block_value_references("reference", value) do
      {:ok, []} ->
        clear_reference_target(value)

      {:ok, [%{type: type, id: id}]} ->
        lock_reference_target(project_id, value, type, id)

      {:error, _reason} = error ->
        error
    end
  end

  def lock_and_normalize_block_value(project_id, "rich_text", value) when is_integer(project_id) and is_map(value) do
    content = value["content"] || value[:content] || ""

    with {:ok, references} <- extract_block_value_references("rich_text", value),
         specs = Enum.map(references, &mention_reference_spec/1),
         {:ok, _normalized_ids} <-
           ProjectIntegrity.lock_active_references(project_id, specs) do
      {:ok,
       value
       |> Map.delete(:content)
       |> Map.put("content", content)}
    end
  end

  def lock_and_normalize_block_value(_project_id, type, value) when type in ["reference", "rich_text"] do
    {:error, {:invalid_project_reference, {:block, :value, type}, value}}
  end

  def lock_and_normalize_block_value(_project_id, _type, value), do: {:ok, value}

  @doc """
  Extracts the project entity references encoded in a prospective block value.

  Unlike the best-effort extraction used to repair historical tracker rows,
  this function applies the same strict value contract as the writer guard so
  restore previews can surface malformed references instead of omitting them.
  """
  @spec extract_block_value_references(String.t(), term()) ::
          {:ok, [map()]} | {:error, term()}
  def extract_block_value_references("reference", value) when is_map(value) do
    target_type = reference_value(value, "target_type")
    target_id = reference_value(value, "target_id")

    case {normalize_optional_target_type(target_type), target_id} do
      {nil, id} when id in [nil, ""] ->
        {:ok, []}

      {type, id} when type in ["sheet", "flow"] and id not in [nil, ""] ->
        validate_block_reference(type, id, target_type)

      _invalid_pair ->
        {:error, {:invalid_project_reference, {:block, :value, target_type}, target_id}}
    end
  end

  def extract_block_value_references("rich_text", value) when is_map(value) do
    content = value["content"] || value[:content] || ""
    strict_mentions_from_html(content)
  end

  def extract_block_value_references(type, value) when type in ["reference", "rich_text"] do
    {:error, {:invalid_project_reference, {:block, :value, type}, value}}
  end

  def extract_block_value_references(_type, _value), do: {:ok, []}

  defp validate_block_reference(type, id, diagnostic_type) do
    case ProjectIntegrity.normalize_optional_id(id) do
      {:ok, normalized_id} when is_integer(normalized_id) ->
        {:ok, [%{type: type, id: id, context: "value"}]}

      _invalid_or_absent ->
        {:error, {:invalid_project_reference, {:block, :value, diagnostic_type}, id}}
    end
  end

  defp clear_reference_target(value) do
    {:ok,
     value
     |> put_reference_value("target_type", nil)
     |> put_reference_value("target_id", nil)}
  end

  defp lock_reference_target(project_id, value, type, id) do
    reference_type = if(type == "sheet", do: :sheet, else: :flow)
    context = {:block, :value, type}

    case ProjectIntegrity.lock_active_references(project_id, [
           {reference_type, context, id}
         ]) do
      {:ok, [normalized_id]} ->
        {:ok,
         value
         |> put_reference_value("target_type", type)
         |> put_reference_value("target_id", normalized_id)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes all references from a block.
  Called when a block is deleted.
  """
  @spec delete_block_references(any()) :: {integer(), nil}
  def delete_block_references(block_id) do
    Repo.delete_all(from(r in EntityReferenceRecord, where: r.source_type == "block" and r.source_id == ^block_id))
  end

  @doc "Deletes projection rows for a batch of Sheet-owned block sources."
  @spec delete_block_references_for_sources([integer()]) :: {non_neg_integer(), nil}
  def delete_block_references_for_sources(block_ids) when is_list(block_ids) do
    Repo.delete_all(
      from(reference in EntityReferenceRecord,
        where:
          reference.source_type == "block" and
            reference.source_id in ^block_ids
      )
    )
  end

  @doc """
  Deletes Sheet-owned block references pointing to a target unless they
  originate from a live block. Foreign source projections are retained for
  their owning contexts to reconcile or report as dangling.
  """
  @spec delete_target_references(String.t(), any()) :: {integer(), nil}
  def delete_target_references(target_type, target_id) do
    retained_blocks_query =
      from(reference in EntityReferenceRecord,
        join: block in Block,
        on: reference.source_type == "block" and reference.source_id == block.id,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where:
          reference.target_type == ^target_type and reference.target_id == ^target_id and
            is_nil(block.deleted_at) and is_nil(sheet.deleted_at),
        distinct: block.id,
        select: block.id
      )

    retained_blocks_query =
      if target_type == "sheet" do
        from([_reference, block, _sheet] in retained_blocks_query,
          where: block.sheet_id != ^target_id
        )
      else
        retained_blocks_query
      end

    retained_block_ids = Repo.all(retained_blocks_query)

    query =
      from(reference in EntityReferenceRecord,
        where:
          reference.source_type == "block" and
            reference.target_type == ^target_type and reference.target_id == ^target_id
      )

    query =
      if retained_block_ids == [] do
        query
      else
        from(reference in query,
          where: reference.source_id not in ^retained_block_ids
        )
      end

    Repo.delete_all(query)
  end

  # Private functions

  defp batch_insert_references(source_type, source_id, references, opts) do
    now = DateTime.to_naive(TimeHelpers.now())

    entries =
      references
      |> Enum.map(fn ref -> ref.id |> parse_id() |> then(&{&1, ref}) end)
      |> Enum.reject(fn {target_id, _} -> is_nil(target_id) end)
      |> Enum.map(fn {target_id, ref} ->
        %{
          source_type: source_type,
          source_id: source_id,
          target_type: ref.type,
          target_id: target_id,
          context: ref.context,
          inserted_at: now,
          updated_at: now
        }
      end)
      |> filter_project_targets(source_type, Keyword.get(opts, :project_id))

    if entries != [], do: Repo.insert_all(EntityReferenceRecord, entries, on_conflict: :nothing)

    :ok
  end

  defp filter_project_targets(entries, _source_type, nil), do: entries

  defp filter_project_targets(entries, source_type, project_id) when is_integer(project_id) do
    if not Repo.in_transaction?() do
      raise ArgumentError,
            "project-scoped entity references must be rebuilt inside an explicit database transaction"
    end

    allowed_types = Map.fetch!(@project_target_types, source_type)
    entries = Enum.filter(entries, &(&1.target_type in allowed_types))

    allowed_targets =
      Enum.reduce([{"sheet", Sheet}, {"flow", FlowRecord}, {"scene", SceneRecord}], MapSet.new(), fn
        {target_type, schema}, allowed ->
          target_ids =
            entries
            |> Enum.filter(&(&1.target_type == target_type))
            |> Enum.map(& &1.target_id)
            |> Enum.uniq()

          active_ids =
            if target_ids == [] do
              []
            else
              Repo.all(
                from target in schema,
                  where:
                    target.id in ^target_ids and target.project_id == ^project_id and
                      is_nil(target.deleted_at),
                  order_by: [asc: target.id],
                  lock: "FOR SHARE",
                  select: target.id
              )
            end

          Enum.reduce(active_ids, allowed, &MapSet.put(&2, {target_type, &1}))
      end)

    Enum.filter(entries, &MapSet.member?(allowed_targets, {&1.target_type, &1.target_id}))
  end

  defp filter_project_targets(_entries, _source_type, project_id) do
    raise ArgumentError, "expected :project_id to be an integer, got: #{inspect(project_id)}"
  end

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_id(_), do: nil

  defp normalize_optional_target_type(nil), do: nil
  defp normalize_optional_target_type(""), do: nil
  defp normalize_optional_target_type(type) when is_atom(type), do: Atom.to_string(type)
  defp normalize_optional_target_type(type), do: type

  defp reference_value(value, key) do
    case Map.fetch(value, key) do
      {:ok, stored_value} -> stored_value
      :error -> Map.get(value, reference_atom_key(key))
    end
  end

  defp put_reference_value(value, key, normalized) do
    value
    |> Map.delete(reference_atom_key(key))
    |> Map.put(key, normalized)
  end

  defp reference_atom_key("target_type"), do: :target_type
  defp reference_atom_key("target_id"), do: :target_id

  defp extract_block_references(block) do
    case block.type do
      "reference" ->
        extract_reference_block_refs(block)

      "rich_text" ->
        extract_rich_text_refs(block)

      _ ->
        []
    end
  end

  defp extract_reference_block_refs(block) do
    target_type = get_in(block.value, ["target_type"])
    target_id = get_in(block.value, ["target_id"])

    if target_type && target_id do
      [%{type: target_type, id: target_id, context: "value"}]
    else
      []
    end
  end

  defp extract_rich_text_refs(block) do
    content = block.value["content"] || block.value[:content] || ""
    extract_mentions_from_html(content)
  end

  defp extract_mentions_from_html(content) when is_binary(content) do
    case strict_mentions_from_html(content) do
      {:ok, references} -> references
      {:error, _reason} -> []
    end
  end

  defp extract_mentions_from_html(_), do: []

  defp strict_mentions_from_html(content) when is_binary(content) do
    case RichTextMentions.extract_from_html(content) do
      {:ok, mentions} ->
        {:ok, Enum.map(mentions, &Map.put(&1, :context, "content"))}

      {:error, {:invalid_html, reason}} ->
        {:error, {:invalid_project_reference, {:block, :content, :invalid_html}, reason}}

      {:error, {:invalid_mention, details}} ->
        invalid_mention_reference(details)
    end
  end

  defp strict_mentions_from_html(content) do
    {:error, {:invalid_project_reference, {:block, :content, :invalid_html}, content}}
  end

  defp invalid_mention_reference(%{type: [type], id: [id]}) do
    {:error, {:invalid_project_reference, {:block, :content, type}, id}}
  end

  defp invalid_mention_reference(details) do
    {:error, {:invalid_project_reference, {:block, :content, :malformed_mention}, details}}
  end

  defp mention_reference_spec(%{type: "sheet", id: id}), do: {:sheet, {:block, :content, "sheet"}, id}

  defp mention_reference_spec(%{type: "flow", id: id}), do: {:flow, {:block, :content, "flow"}, id}
end
