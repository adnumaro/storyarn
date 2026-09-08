defmodule Storyarn.Ideation.Groups.Rules.Input do
  @moduledoc false
  alias Storyarn.Platform.Kernel.MapAccess

  def get(attrs, key), do: MapAccess.get_flexible(attrs, key)
  defguard valid_id(id) when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807

  defguard valid_version(version)
           when is_integer(version) and version > 0 and version < 2_147_483_647

  def request_key(attrs) when is_map(attrs) do
    case Ecto.UUID.cast(get(attrs, :request_key)) do
      {:ok, key} -> {:ok, key}
      :error -> {:error, :invalid_request_key}
    end
  end

  def request_key(_), do: {:error, :invalid_request_key}

  def fingerprint(operation, group_id, expected, attrs),
    do: :crypto.hash(:sha256, :erlang.term_to_binary({:ideation_group_v1, operation, group_id, expected, attrs}))

  def content(attrs) when is_map(attrs) do
    Enum.reduce_while([{:title, 160}, {:synthesis, 10_000}], {:ok, %{}}, fn {field, max}, {:ok, result} ->
      case content_field(attrs, field, max) do
        :omitted -> {:cont, {:ok, result}}
        {:ok, value} -> {:cont, {:ok, Map.put(result, field, value)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp content_field(attrs, field, max) do
    if Map.has_key?(attrs, field) or Map.has_key?(attrs, Atom.to_string(field)),
      do: text_value(get(attrs, field), max),
      else: :omitted
  end

  defp text_value(nil, _max), do: {:ok, nil}

  defp text_value(value, max) when is_binary(value) and byte_size(value) <= max * 4 do
    if String.valid?(value) and String.length(value) <= max,
      do: {:ok, String.trim(value)},
      else: {:error, :invalid_group}
  end

  defp text_value(_value, _max), do: {:error, :invalid_group}

  def ids(ids) when is_list(ids) and length(ids) <= 200 do
    if Enum.all?(ids, &valid_id(&1)) and length(Enum.uniq(ids)) == length(ids),
      do: {:ok, Enum.sort(ids)},
      else: {:error, :invalid_group_members}
  end

  def ids(_), do: {:error, :invalid_group_members}

  def canvas(attrs) when is_map(attrs) do
    x = get(attrs, :x)
    y = get(attrs, :y)
    width = get(attrs, :width) || 600
    height = get(attrs, :height) || 400

    if coordinate?(x) and coordinate?(y) and dimension?(width, 200) and dimension?(height, 120),
      do: {:ok, %{"x" => x, "y" => y, "width" => width, "height" => height}},
      else: {:error, :invalid_canvas}
  end

  def canvas(_), do: {:error, :invalid_canvas}

  def anchor(attrs) when is_map(attrs) do
    x = get(attrs, :x)
    y = get(attrs, :y)

    if coordinate?(x) and coordinate?(y),
      do: {:ok, %{"x" => x, "y" => y}},
      else: {:error, :invalid_canvas}
  end

  def anchor(_), do: {:error, :invalid_canvas}

  def move(attrs) do
    x = get(attrs, :x)
    y = get(attrs, :y)

    with true <- coordinate?(x) and coordinate?(y),
         {:ok, versions} <- versions(get(attrs, :member_versions)) do
      {:ok, %{x: x, y: y, member_versions: versions}}
    else
      _ -> {:error, :invalid_canvas}
    end
  end

  defp versions(items) when is_list(items) and length(items) <= 200 do
    pairs =
      Enum.map(items, fn item ->
        if is_map(item), do: {get(item, :id), get(item, :version)}, else: {nil, nil}
      end)

    if Enum.all?(pairs, fn {id, version} ->
         valid_id(id) and is_integer(version) and version >= 0
       end) and
         length(Enum.uniq_by(pairs, &elem(&1, 0))) == length(pairs),
       do: {:ok, Map.new(pairs)},
       else: :error
  end

  defp versions(_), do: :error
  defp coordinate?(value), do: is_number(value) and abs(value) <= 1_000_000
  defp dimension?(value, minimum), do: is_number(value) and value >= minimum and value <= 100_000

  def deletion(%DateTime{} = time), do: {:ok, time}

  def deletion(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, 0} -> {:ok, time}
      _ -> {:error, :invalid_group}
    end
  end

  def deletion(_), do: {:error, :invalid_group}
end
