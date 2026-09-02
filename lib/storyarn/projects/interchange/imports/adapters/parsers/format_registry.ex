defmodule Storyarn.Projects.Imports.FormatRegistry do
  @moduledoc """
  Closed registry for behavior that follows a parsed import plan.

  Parser selection and post-parse execution adapters share this source of
  truth. Durable plans carry only a format identifier, so execution resolves
  that identifier again and fails closed when the running release does not
  support it. Source extensions are intentionally exclusive: if two formats
  ever share a container extension, the product must add an explicit format
  discriminator rather than guess from untrusted contents.
  """

  alias Storyarn.Projects.Imports.ImportFormatId
  alias Storyarn.Projects.Imports.ImportPlan
  alias Storyarn.Projects.Imports.Parsers.Yarn
  alias Storyarn.Projects.Imports.Parsers.Yarn.FormatAdapter, as: YarnFormatAdapter

  @formats %{
    yarn: %{
      parser: Yarn,
      adapter: YarnFormatAdapter,
      sources: %{".yarn" => :file, ".zip" => :archive}
    }
  }

  for {format, registration} <- @formats do
    persisted_format = Atom.to_string(format)
    parser = Map.fetch!(registration, :parser)
    adapter = Map.fetch!(registration, :adapter)
    sources = Map.fetch!(registration, :sources)

    if !ImportFormatId.valid?(persisted_format) do
      raise ArgumentError,
            "import format registry contains an invalid durable format id: #{inspect(persisted_format)}"
    end

    Code.ensure_compiled!(parser)
    Code.ensure_compiled!(adapter)

    parser_version = parser.parser_version()

    if parser.format() != format do
      raise ArgumentError,
            "import parser #{inspect(parser)} declares #{inspect(parser.format())}, expected #{inspect(format)}"
    end

    if !(is_binary(parser_version) and parser_version != "" and String.length(parser_version) <= 30) do
      raise ArgumentError,
            "import parser #{inspect(parser)} declares an invalid durable parser version"
    end

    if !adapter.supports_parser_version?(parser_version) do
      raise ArgumentError,
            "import adapter #{inspect(adapter)} does not support current parser version #{inspect(parser_version)}"
    end

    if !(map_size(sources) > 0 and
           Enum.all?(sources, fn {extension, source_kind} ->
             is_binary(extension) and extension != "" and
               Regex.match?(~r/\A\.[a-z0-9]+\z/, extension) and
               String.downcase(extension) == extension and
               source_kind in [:file, :archive]
           end)) do
      raise ArgumentError,
            "import format #{inspect(format)} declares invalid source extensions or source kinds"
    end

    permanent_error_codes = adapter.permanent_error_codes()

    if !(match?(%MapSet{}, permanent_error_codes) and
           Enum.all?(permanent_error_codes, &(is_binary(&1) and &1 != ""))) do
      raise ArgumentError,
            "import adapter #{inspect(adapter)} declares invalid permanent error codes"
    end
  end

  @extension_entries Enum.flat_map(@formats, fn {format, %{parser: parser, sources: sources}} ->
                       Enum.map(sources, fn {extension, source_kind} ->
                         {extension, %{format: format, parser: parser, source_kind: source_kind}}
                       end)
                     end)
  @duplicate_extensions @extension_entries
                        |> Enum.frequencies_by(&elem(&1, 0))
                        |> Enum.filter(fn {_extension, count} -> count > 1 end)
                        |> Enum.map(&elem(&1, 0))
                        |> Enum.sort()

  if @duplicate_extensions != [] do
    raise ArgumentError,
          "import format registry contains ambiguous extensions: #{inspect(@duplicate_extensions)}"
  end

  @extension_sources Map.new(@extension_entries)
  @persisted_formats Map.new(@formats, fn {format, _registration} ->
                       {Atom.to_string(format), format}
                     end)

  @spec registrations() :: [
          %{
            format: atom(),
            parser: module(),
            adapter: module(),
            sources: %{optional(String.t()) => :file | :archive}
          }
        ]
  def registrations do
    @formats
    |> Enum.map(fn {format, registration} -> Map.put(registration, :format, format) end)
    |> Enum.sort_by(& &1.format)
  end

  @spec persisted_formats() :: [String.t()]
  def persisted_formats, do: @persisted_formats |> Map.keys() |> Enum.sort()

  @doc """
  Verifies that a parser returned the format, version, and source kind selected
  by its registry entry.

  The check is repeated at the application boundary so a future parser cannot
  accidentally route its plan through another format's execution adapter.
  """
  @spec validate_parsed_plan(map(), ImportPlan.t()) ::
          :ok | {:error, :unsupported_import_format}
  def validate_parsed_plan(%{format: expected_format, parser: parser, source_kind: expected_source_kind}, %ImportPlan{
        format: plan_format,
        parser_version: plan_parser_version,
        source_kind: plan_source_kind
      }) do
    with {:ok, %{parser: ^parser}} <- Map.fetch(@formats, expected_format),
         ^expected_format <- parser.format(),
         ^expected_format <- plan_format,
         ^plan_parser_version <- parser.parser_version(),
         ^expected_source_kind <- plan_source_kind do
      :ok
    else
      _mismatch -> {:error, :unsupported_import_format}
    end
  end

  def validate_parsed_plan(_source, _plan), do: {:error, :unsupported_import_format}

  @spec parser_for(String.t()) :: {:ok, module()} | {:error, :unsupported_import_format}
  def parser_for(filename) when is_binary(filename) do
    case source_for(filename) do
      {:ok, %{parser: parser}} -> {:ok, parser}
      {:error, :unsupported_import_format} = error -> error
    end
  end

  def parser_for(_filename), do: {:error, :unsupported_import_format}

  @spec source_for(String.t()) ::
          {:ok, %{format: atom(), parser: module(), source_kind: :file | :archive}}
          | {:error, :unsupported_import_format}
  def source_for(filename) when is_binary(filename) do
    case Map.fetch(@extension_sources, filename |> Path.extname() |> String.downcase()) do
      {:ok, source} -> {:ok, source}
      :error -> {:error, :unsupported_import_format}
    end
  end

  def source_for(_filename), do: {:error, :unsupported_import_format}

  @spec encode_persisted(atom()) :: {:ok, String.t()} | {:error, :unsupported_import_format}
  def encode_persisted(format) when is_atom(format) do
    name = Atom.to_string(format)

    if Map.has_key?(@persisted_formats, name),
      do: {:ok, name},
      else: {:error, :unsupported_import_format}
  end

  def encode_persisted(_format), do: {:error, :unsupported_import_format}

  @spec decode_persisted(String.t()) :: {:ok, atom()} | {:error, :unsupported_import_format}
  def decode_persisted(format) when is_binary(format) do
    case Map.fetch(@persisted_formats, format) do
      {:ok, registered_format} -> {:ok, registered_format}
      :error -> {:error, :unsupported_import_format}
    end
  end

  def decode_persisted(_format), do: {:error, :unsupported_import_format}

  @spec fetch(atom()) :: {:ok, module()} | {:error, :unsupported_import_format}
  def fetch(format) when is_atom(format) do
    case Map.fetch(@formats, format) do
      {:ok, %{adapter: adapter}} -> {:ok, adapter}
      :error -> {:error, :unsupported_import_format}
    end
  end

  def fetch(_format), do: {:error, :unsupported_import_format}

  @doc """
  Resolves execution policy for a durable plan.

  Compatibility is format-specific and fail-closed: a known format with an
  unsupported parser version or source kind cannot reach preview, review, or
  materialization. Historical versions remain possible when their adapter
  opts into them explicitly.
  """
  @spec compatible_adapter(ImportPlan.t()) ::
          {:ok, module()} | {:error, :unsupported_import_format}
  def compatible_adapter(%ImportPlan{format: format, parser_version: parser_version, source_kind: source_kind}) do
    with {:ok, %{adapter: adapter, sources: sources}} <- Map.fetch(@formats, format),
         true <- adapter.supports_parser_version?(parser_version),
         true <- source_kind in Map.values(sources) do
      {:ok, adapter}
    else
      _unsupported -> {:error, :unsupported_import_format}
    end
  end

  def compatible_adapter(_plan), do: {:error, :unsupported_import_format}

  @spec permanent_error_code?(atom() | String.t(), String.t()) :: boolean()
  def permanent_error_code?(format, code) when is_binary(code) do
    with {:ok, registered_format} <- normalize_registered_format(format),
         {:ok, %{adapter: adapter}} <- Map.fetch(@formats, registered_format) do
      MapSet.member?(adapter.permanent_error_codes(), code)
    else
      _unknown_format -> false
    end
  end

  def permanent_error_code?(_format, _code), do: false

  defp normalize_registered_format(format) when is_atom(format) do
    if Map.has_key?(@formats, format), do: {:ok, format}, else: :error
  end

  defp normalize_registered_format(format) when is_binary(format), do: decode_persisted(format)
  defp normalize_registered_format(_format), do: :error
end
