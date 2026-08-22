defmodule Storyarn.Analytics.EventContract do
  @moduledoc """
  Technical port for consumer-owned product analytics contracts.

  A contract maps its private event identifier to the stable external name and
  the exact coarse properties that may leave Storyarn. It must also validate
  and project property values before transport. The adapter invokes both parts
  of the contract and fails closed; callers cannot bypass value validation by
  invoking `Storyarn.Analytics.track/4` directly.
  """

  @max_name_bytes 120
  @max_property_key_bytes 120

  @callback event(term()) :: {:ok, String.t(), [atom() | String.t()]} | :error
  @callback sanitize(term(), map()) :: {:ok, map()} | :error

  @spec resolve(module(), term()) :: {:ok, String.t(), MapSet.t(String.t())} | :error
  def resolve(contract, event) when is_atom(contract) do
    with true <- Code.ensure_loaded?(contract),
         true <- function_exported?(contract, :event, 1),
         {:ok, event_name, property_keys} <- contract.event(event),
         true <- bounded_string?(event_name, @max_name_bytes),
         {:ok, normalized_keys} <- normalize_property_keys(property_keys) do
      {:ok, event_name, MapSet.new(normalized_keys)}
    else
      _invalid -> :error
    end
  rescue
    _error -> :error
  catch
    _kind, _reason -> :error
  end

  def resolve(_contract, _event), do: :error

  @doc false
  @spec sanitize(module(), term(), map()) :: {:ok, map()} | :error
  def sanitize(contract, event, properties) when is_atom(contract) and is_map(properties) do
    with true <- Code.ensure_loaded?(contract),
         true <- function_exported?(contract, :sanitize, 2),
         {:ok, safe_properties} when is_map(safe_properties) <- contract.sanitize(event, properties) do
      {:ok, safe_properties}
    else
      _invalid -> :error
    end
  rescue
    _error -> :error
  catch
    _kind, _reason -> :error
  end

  def sanitize(_contract, _event, _properties), do: :error

  defp normalize_property_keys(keys) when is_list(keys) do
    normalized = Enum.map(keys, &normalize_key/1)

    if Enum.all?(normalized, &bounded_string?(&1, @max_property_key_bytes)) and
         Enum.uniq(normalized) == normalized do
      {:ok, normalized}
    else
      :error
    end
  end

  defp normalize_property_keys(_keys), do: :error

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(_key), do: nil

  defp bounded_string?(value, maximum), do: is_binary(value) and byte_size(value) > 0 and byte_size(value) <= maximum
end
