defmodule StoryarnWeb.PrivateDownload.Range do
  @moduledoc false

  @type selection :: %{
          required(:status) => :ok | :partial_content | :range_not_satisfiable,
          required(:offset) => non_neg_integer(),
          required(:length) => non_neg_integer(),
          required(:last_byte) => non_neg_integer(),
          required(:size) => non_neg_integer(),
          required(:etag) => binary() | nil
        }

  @spec select([binary()], [binary()], non_neg_integer(), binary() | nil) :: selection()
  def select(range_headers, if_range_headers, size, etag) do
    case if_range_headers do
      [] -> parse_range(range_headers, size, etag)
      [if_range] when is_binary(etag) and if_range == etag -> parse_range(range_headers, size, etag)
      _ -> full_selection(size, etag)
    end
  end

  defp parse_range([], size, etag), do: full_selection(size, etag)

  defp parse_range(["bytes=" <> range], 0, etag) do
    if valid_single_range_syntax?(range) do
      unsatisfied_selection(0, etag)
    else
      full_selection(0, etag)
    end
  end

  defp parse_range(["bytes=" <> range], size, etag) do
    if String.contains?(range, ",") do
      full_selection(size, etag)
    else
      parse_single_range(range, size, etag)
    end
  end

  defp parse_range(_range_headers, size, etag), do: full_selection(size, etag)

  defp parse_single_range("-" <> suffix, size, etag) do
    case parse_non_negative_integer(suffix) do
      {:ok, 0} -> unsatisfied_selection(size, etag)
      {:ok, suffix_length} -> partial_selection(max(size - suffix_length, 0), size - 1, size, etag)
      :error -> full_selection(size, etag)
    end
  end

  defp parse_single_range(range, size, etag) do
    case String.split(range, "-", parts: 2) do
      [first, ""] -> parse_open_range(first, size, etag)
      [first, last] -> parse_closed_range(first, last, size, etag)
      _ -> full_selection(size, etag)
    end
  end

  defp parse_open_range(first, size, etag) do
    case parse_non_negative_integer(first) do
      {:ok, first_byte} when first_byte < size ->
        partial_selection(first_byte, size - 1, size, etag)

      {:ok, _first_byte} ->
        unsatisfied_selection(size, etag)

      :error ->
        full_selection(size, etag)
    end
  end

  defp parse_closed_range(first, last, size, etag) do
    with {:ok, first_byte} <- parse_non_negative_integer(first),
         {:ok, last_byte} <- parse_non_negative_integer(last) do
      cond do
        first_byte >= size -> unsatisfied_selection(size, etag)
        last_byte < first_byte -> unsatisfied_selection(size, etag)
        true -> partial_selection(first_byte, min(last_byte, size - 1), size, etag)
      end
    else
      :error -> full_selection(size, etag)
    end
  end

  defp parse_non_negative_integer(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> {:ok, integer}
      _ -> :error
    end
  end

  defp valid_single_range_syntax?(range) do
    if String.contains?(range, ",") do
      false
    else
      case String.split(range, "-", parts: 2) do
        ["", suffix] ->
          parse_non_negative_integer(suffix) != :error

        [first, ""] ->
          parse_non_negative_integer(first) != :error

        [first, last] ->
          parse_non_negative_integer(first) != :error and
            parse_non_negative_integer(last) != :error

        _ ->
          false
      end
    end
  end

  defp full_selection(size, etag) do
    %{
      status: :ok,
      offset: 0,
      length: size,
      last_byte: max(size - 1, 0),
      size: size,
      etag: etag
    }
  end

  defp partial_selection(first_byte, last_byte, size, etag) do
    %{
      status: :partial_content,
      offset: first_byte,
      length: last_byte - first_byte + 1,
      last_byte: last_byte,
      size: size,
      etag: etag
    }
  end

  defp unsatisfied_selection(size, etag) do
    %{
      status: :range_not_satisfiable,
      offset: 0,
      length: 0,
      last_byte: 0,
      size: size,
      etag: etag
    }
  end
end
