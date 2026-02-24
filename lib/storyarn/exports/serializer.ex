defmodule Storyarn.Exports.Serializer do
  @moduledoc """
  Behaviour for export format serializers.

  All export formats implement this behaviour. Engine formats are plugin-style —
  each module self-registers, so adding a new engine never touches the core export logic.

  ## Two modes

  - `serialize/2` for tests and small sync exports (in-memory)
  - `serialize_to_file/4` for production streaming (constant memory)
  """

  @type output :: binary() | [{filename :: String.t(), content :: binary()}]

  @doc """
  Serialize project data to the target format in memory.
  Used for small projects (sync export) and tests.
  """
  @callback serialize(project_data :: map(), options :: Storyarn.Exports.ExportOptions.t()) ::
              {:ok, output()} | {:error, term()}

  @doc """
  Serialize project data to the target format, writing to a file path.
  Used for large projects with streaming. The callbacks keyword list
  may include a `progress_fn` for progress reporting.
  """
  @callback serialize_to_file(
              data :: term(),
              file_path :: Path.t(),
              options :: Storyarn.Exports.ExportOptions.t(),
              callbacks :: keyword()
            ) :: :ok | {:error, term()}

  @doc "MIME content type for the exported file."
  @callback content_type() :: String.t()

  @doc ~S'File extension without leading dot (e.g., "json", "ink", "yarn").'
  @callback file_extension() :: String.t()

  @doc "Human-readable format name for the UI (e.g., \"Storyarn JSON\")."
  @callback format_label() :: String.t()

  @doc "Which content sections this format supports."
  @callback supported_sections() ::
              [:sheets | :flows | :scenes | :screenplays | :localization | :assets]
end
