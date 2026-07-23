defmodule Storyarn.AI.ModelCatalog.Entry do
  @moduledoc "Validated, content-free capability contract for one provider model."

  alias Storyarn.AI.ConfigMap

  @capabilities ~w(translation suggestions tasks images)a
  @modalities ~w(text image audio)a
  @structured_output_modes ~w(json_schema json_object none)a

  @enforce_keys [
    :provider,
    :model,
    :catalog_version,
    :capabilities,
    :modalities,
    :structured_output,
    :processing_locations,
    :deprecated?
  ]
  defstruct [
    :provider,
    :model,
    :catalog_version,
    :capabilities,
    :modalities,
    :structured_output,
    :context_window,
    :max_output_tokens,
    :processing_locations,
    :pricing_version,
    :deprecated?
  ]

  @type t :: %__MODULE__{}

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, :invalid_model_catalog_entry}
  def new(attrs) do
    attrs = ConfigMap.normalize(attrs)

    with provider when is_binary(provider) <- nonempty(attrs["provider"]),
         model when is_binary(model) <- nonempty(attrs["model"]),
         version when is_integer(version) and version > 0 <- attrs["catalog_version"],
         {:ok, capabilities} <- enum_list(attrs["capabilities"], @capabilities),
         true <- capabilities != [],
         {:ok, modalities} <- enum_list(attrs["modalities"], @modalities),
         true <- modalities != [],
         {:ok, structured_output} <- enum_value(attrs["structured_output"], @structured_output_modes),
         {:ok, context_window} <- optional_positive_integer(attrs["context_window"]),
         {:ok, max_output_tokens} <- optional_positive_integer(attrs["max_output_tokens"]),
         {:ok, processing_locations} <- string_list(attrs["processing_locations"]),
         true <- processing_locations != [],
         {:ok, pricing_version} <- optional_positive_integer(attrs["pricing_version"]),
         deprecated? when is_boolean(deprecated?) <- attrs["deprecated"] do
      {:ok,
       %__MODULE__{
         provider: provider,
         model: model,
         catalog_version: version,
         capabilities: capabilities,
         modalities: modalities,
         structured_output: structured_output,
         context_window: context_window,
         max_output_tokens: max_output_tokens,
         processing_locations: processing_locations,
         pricing_version: pricing_version,
         deprecated?: deprecated?
       }}
    else
      _invalid -> {:error, :invalid_model_catalog_entry}
    end
  end

  defp nonempty(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp nonempty(_value), do: nil

  defp enum_list(values, allowed) when is_list(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case enum_value(value, allowed) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, normalized |> Enum.reverse() |> Enum.uniq()}
      :error -> {:error, :invalid_enum_list}
    end
  end

  defp enum_list(_values, _allowed), do: {:error, :invalid_enum_list}

  defp enum_value(value, allowed) when is_atom(value) do
    if value in allowed, do: {:ok, value}, else: :error
  end

  defp enum_value(value, allowed) when is_binary(value) do
    case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
      nil -> :error
      normalized -> {:ok, normalized}
    end
  end

  defp enum_value(_value, _allowed), do: :error

  defp optional_positive_integer(nil), do: {:ok, nil}
  defp optional_positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp optional_positive_integer(_value), do: {:error, :invalid_positive_integer}

  defp string_list(values) when is_list(values) do
    if Enum.all?(values, &(is_binary(&1) and String.valid?(&1) and byte_size(String.trim(&1)) > 0)) do
      {:ok, values |> Enum.map(&String.trim/1) |> Enum.uniq()}
    else
      {:error, :invalid_string_list}
    end
  end

  defp string_list(_values), do: {:error, :invalid_string_list}
end
