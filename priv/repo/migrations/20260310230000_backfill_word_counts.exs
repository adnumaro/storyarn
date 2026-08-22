defmodule Storyarn.Repo.Migrations.BackfillWordCounts do
  use Ecto.Migration

  import Ecto.Query

  alias Storyarn.Repo

  @batch_size 500

  def up do
    backfill_blocks()
    backfill_flow_nodes()
  end

  def down do
    # Reset all word counts to 0
    execute("UPDATE blocks SET word_count = 0")
    execute("UPDATE flow_nodes SET word_count = 0")
  end

  defp backfill_blocks do
    from(b in "blocks",
      join: s in "sheets",
      on: b.sheet_id == s.id,
      where: is_nil(b.deleted_at) and is_nil(s.deleted_at) and b.type in ["text", "rich_text"],
      select: {b.id, b.value}
    )
    |> Repo.stream(max_rows: @batch_size)
    |> Stream.chunk_every(@batch_size)
    |> Enum.each(fn batch ->
      Enum.each(batch, fn {id, value} ->
        wc = block_word_count(decode_value(value))

        if wc > 0 do
          from(b in "blocks", where: b.id == ^id)
          |> Repo.update_all(set: [word_count: wc])
        end
      end)
    end)
  end

  defp backfill_flow_nodes do
    from(n in "flow_nodes",
      join: f in "flows",
      on: n.flow_id == f.id,
      where: is_nil(n.deleted_at) and is_nil(f.deleted_at) and n.type in ["dialogue", "exit"],
      select: {n.id, n.type, n.data}
    )
    |> Repo.stream(max_rows: @batch_size)
    |> Stream.chunk_every(@batch_size)
    |> Enum.each(fn batch ->
      Enum.each(batch, fn {id, type, data} ->
        wc = node_word_count(type, decode_value(data))

        if wc > 0 do
          from(n in "flow_nodes", where: n.id == ^id)
          |> Repo.update_all(set: [word_count: wc])
        end
      end)
    end)
  end

  # JSONB columns are returned as already-decoded maps by Postgrex
  defp decode_value(value) when is_map(value), do: value
  defp decode_value(_), do: nil

  # Keep this historical migration self-contained. Runtime domain helpers may
  # move when bounded contexts are split, but an upgrade from an old release
  # must always execute the original backfill semantics.
  defp block_word_count(value) when is_map(value) do
    value
    |> field("content", :content)
    |> text_word_count()
  end

  defp block_word_count(_value), do: 0

  defp node_word_count("dialogue", data) when is_map(data) do
    base_text = [
      field(data, "text", :text),
      field(data, "menu_text", :menu_text),
      field(data, "stage_directions", :stage_directions)
    ]

    response_text =
      case field(data, "responses", :responses) do
        responses when is_list(responses) -> Enum.map(responses, &response_text/1)
        _responses -> []
      end

    (base_text ++ response_text)
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&text_word_count/1)
    |> Enum.sum()
  end

  defp node_word_count("exit", data) when is_map(data) do
    data
    |> field("label", :label)
    |> text_word_count()
  end

  defp node_word_count(_type, _data), do: 0

  defp response_text(response) when is_map(response), do: field(response, "text", :text)
  defp response_text(_response), do: nil

  defp field(map, string_key, atom_key) do
    case Map.fetch(map, string_key) do
      {:ok, value} -> value
      :error -> Map.get(map, atom_key)
    end
  end

  defp text_word_count(text) when is_binary(text) do
    text
    |> String.replace(~r/<br\s*\/?>/, "\n")
    |> String.replace(~r/<\/p>\s*<p[^>]*>/, "\n")
    |> String.replace(~r/<[^>]+>/, "")
    |> decode_entities()
    |> String.trim()
    |> String.split(~r/\s+/, trim: true)
    |> length()
  end

  defp text_word_count(_text), do: 0

  defp decode_entities(text) do
    text
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&nbsp;", " ")
  end
end
