defmodule Storyarn.Repo.Migrations.BackfillExitNodeWordCounts do
  use Ecto.Migration

  import Ecto.Query

  alias Storyarn.Repo

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
        word_count = exit_word_count(decode_value(data))

        from(n in "flow_nodes", where: n.id == ^id and n.data == ^data)
        |> Repo.update_all(set: [word_count: word_count])
      end)
    end)
  end

  def down do
    :ok
  end

  defp decode_value(value) when is_map(value), do: value
  defp decode_value(_value), do: nil

  # Historical migrations must not depend on runtime domain helpers: those
  # helpers can move as bounded contexts become autonomous.
  defp exit_word_count(data) when is_map(data) do
    data
    |> field("label", :label)
    |> text_word_count()
  end

  defp exit_word_count(_data), do: 0

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
