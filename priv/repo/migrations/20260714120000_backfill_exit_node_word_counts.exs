defmodule Storyarn.Repo.Migrations.BackfillExitNodeWordCounts do
  use Ecto.Migration

  import Ecto.Query

  alias Storyarn.Repo
  alias Storyarn.Shared.WordCount

  @batch_size 500

  def up do
    from(n in "flow_nodes",
      join: f in "flows",
      on: n.flow_id == f.id,
      where: is_nil(n.deleted_at) and is_nil(f.deleted_at) and n.type == "exit",
      select: {n.id, n.data}
    )
    |> Repo.stream(max_rows: @batch_size)
    |> Stream.chunk_every(@batch_size)
    |> Enum.each(fn batch ->
      Enum.each(batch, fn {id, data} ->
        word_count = WordCount.for_node_data("exit", decode_value(data))

        from(n in "flow_nodes", where: n.id == ^id)
        |> Repo.update_all(set: [word_count: word_count])
      end)
    end)
  end

  def down do
    :ok
  end

  defp decode_value(value) when is_map(value), do: value
  defp decode_value(_value), do: nil
end
