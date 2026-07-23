defmodule Storyarn.AI.ModelCatalog.Entry do
  @moduledoc "Validated, content-free capability contract for one provider model."

  alias Storyarn.AI.ConfigMap

  @capabilities ~w(translation suggestions tasks images speech)a
  @modalities ~w(text image audio)a
  @structured_output_modes ~w(json_schema json_object none)a
  @api_families ~w(
    structured_text
    openai_images
    openai_speech
    google_interactions_image
    google_interactions_tts
  )a
  @implementation_statuses ~w(executable configuration_only)a
  @release_stages ~w(stable preview)a

  @enforce_keys [
    :provider,
    :model,
    :catalog_version,
    :capabilities,
    :input_modalities,
    :output_modalities,
    :structured_output,
    :api_family,
    :implementation_status,
    :release_stage,
    :processing_locations,
    :deprecated?
  ]
  defstruct [
    :provider,
    :model,
    :catalog_version,
    :capabilities,
    :input_modalities,
    :output_modalities,
    :structured_output,
    :api_family,
    :implementation_status,
    :release_stage,
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
         {:ok, input_modalities} <- enum_list(attrs["input_modalities"], @modalities),
         true <- input_modalities != [],
         {:ok, output_modalities} <- enum_list(attrs["output_modalities"], @modalities),
         true <- output_modalities != [],
         {:ok, structured_output} <- enum_value(attrs["structured_output"], @structured_output_modes),
         {:ok, api_family} <- enum_value(attrs["api_family"], @api_families),
         {:ok, implementation_status} <-
           enum_value(attrs["implementation_status"], @implementation_statuses),
         {:ok, release_stage} <- enum_value(attrs["release_stage"], @release_stages),
         true <-
           valid_contract?(
             capabilities,
             input_modalities,
             structured_output,
             output_modalities,
             api_family,
             implementation_status
           ),
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
         input_modalities: input_modalities,
         output_modalities: output_modalities,
         structured_output: structured_output,
         api_family: api_family,
         implementation_status: implementation_status,
         release_stage: release_stage,
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

  defp valid_contract?(capabilities, [:text], structured_output, [:text], :structured_text, :executable)
       when structured_output in [:json_schema, :json_object],
       do: Enum.all?(capabilities, &(&1 in [:translation, :suggestions, :tasks]))

  defp valid_contract?([:images], input_modalities, :none, [:image], :openai_images, :configuration_only),
    do: :text in input_modalities and Enum.all?(input_modalities, &(&1 in [:text, :image]))

  defp valid_contract?(
         [:images],
         input_modalities,
         :none,
         output_modalities,
         :google_interactions_image,
         :configuration_only
       ),
       do:
         :text in input_modalities and Enum.all?(input_modalities, &(&1 in [:text, :image])) and
           MapSet.new(output_modalities) == MapSet.new([:text, :image])

  defp valid_contract?([:speech], [:text], :none, [:audio], api_family, :configuration_only)
       when api_family in [:openai_speech, :google_interactions_tts], do: true

  defp valid_contract?(
         _capabilities,
         _input_modalities,
         _structured_output,
         _output_modalities,
         _api_family,
         _implementation_status
       ), do: false

  defp string_list(values) when is_list(values) do
    if Enum.all?(values, &(is_binary(&1) and String.valid?(&1) and byte_size(String.trim(&1)) > 0)) do
      {:ok, values |> Enum.map(&String.trim/1) |> Enum.uniq()}
    else
      {:error, :invalid_string_list}
    end
  end

  defp string_list(_values), do: {:error, :invalid_string_list}
end
