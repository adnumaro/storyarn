defmodule Storyarn.AI.CanonicalJSON do
  @moduledoc false

  @spec encode(term()) :: {:ok, binary()} | {:error, :invalid_structured_input}
  def encode(value) do
    {:ok, encode_value(value)}
  rescue
    ArgumentError -> {:error, :invalid_structured_input}
    Protocol.UndefinedError -> {:error, :invalid_structured_input}
  end

  @spec encode!(term()) :: binary()
  def encode!(value) do
    case encode(value) do
      {:ok, encoded} -> encoded
      {:error, reason} -> raise ArgumentError, "cannot encode AI structured input: #{reason}"
    end
  end

  @spec hash(term()) :: {:ok, String.t()} | {:error, :invalid_structured_input}
  def hash(value) do
    with {:ok, encoded} <- encode(value) do
      {:ok, :sha256 |> :crypto.hash(encoded) |> Base.encode16(case: :lower)}
    end
  end

  defp encode_value(nil), do: "null"
  defp encode_value(true), do: "true"
  defp encode_value(false), do: "false"
  defp encode_value(value) when is_binary(value), do: Jason.encode!(value)
  defp encode_value(value) when is_integer(value), do: Integer.to_string(value)

  defp encode_value(value) when is_float(value), do: Jason.encode!(value)

  defp encode_value(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &encode_value/1) <> "]"
  end

  defp encode_value(%_{}), do: raise(ArgumentError, "structs are not JSON values")

  defp encode_value(value) when is_map(value) do
    pairs =
      Enum.map(value, fn {key, item} -> {normalize_key(key), item} end)

    normalized_keys = Enum.map(pairs, &elem(&1, 0))

    if Enum.uniq(normalized_keys) != normalized_keys do
      raise ArgumentError, "duplicate normalized JSON object key"
    end

    encoded_pairs =
      pairs
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join(",", fn {key, item} -> Jason.encode!(key) <> ":" <> encode_value(item) end)

    "{" <> encoded_pairs <> "}"
  end

  defp encode_value(_value), do: raise(ArgumentError, "unsupported JSON value")

  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(_key), do: raise(ArgumentError, "JSON object keys must be strings")
end
