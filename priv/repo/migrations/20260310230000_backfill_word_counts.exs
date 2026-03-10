defmodule Storyarn.Repo.Migrations.BackfillWordCounts do
  use Ecto.Migration

  import Ecto.Query

  alias Storyarn.Repo
  alias Storyarn.Shared.WordCount

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
        wc = WordCount.for_block_value(decode_value(value))

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
      where: is_nil(n.deleted_at) and is_nil(f.deleted_at) and n.type == "dialogue",
      select: {n.id, n.data}
    )
    |> Repo.stream(max_rows: @batch_size)
    |> Stream.chunk_every(@batch_size)
    |> Enum.each(fn batch ->
      Enum.each(batch, fn {id, data} ->
        wc = WordCount.for_node_data(decode_value(data))

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
end
