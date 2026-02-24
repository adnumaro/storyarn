defmodule Storyarn.Imports do
  @moduledoc """
  The Imports context.

  Handles importing project data from external files. Supports parsing,
  previewing, conflict detection, and execution of imports.

  ## Import flow

  1. `parse_file/1` — Detect format and parse the file
  2. `preview/2` — Generate preview with conflict detection
  3. `execute/3` — Run the import with a conflict strategy
  """

  alias Storyarn.Imports.Parsers.StoryarnJSON, as: StoryarnJSONParser

  # 50 MB limit to prevent memory exhaustion from oversized import files
  @max_import_size 50_000_000

  @doc """
  Parse an import file and detect its format.

  Returns `{:ok, %{format: atom, data: map}}` or `{:error, reason}`.
  """
  def parse_file(binary) when is_binary(binary) do
    if byte_size(binary) > @max_import_size do
      {:error, :file_too_large}
    else
      # For now, only Storyarn JSON is supported
      case StoryarnJSONParser.parse(binary) do
        {:ok, data} -> {:ok, %{format: :storyarn, data: data}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Preview what an import would do without executing it.

  Returns a preview struct with entity counts and detected conflicts.
  """
  def preview(project_id, parsed_data) do
    StoryarnJSONParser.preview(project_id, parsed_data)
  end

  @doc """
  Execute an import into a project.

  ## Authorization

  Caller MUST verify the current user has `:edit_content` permission on the
  target project before calling this function. The Imports context does not
  enforce authorization — that responsibility belongs to the LiveView layer.

  ## Options

  - `:conflict_strategy` — `:skip` | `:overwrite` | `:rename` (default: `:skip`)

  Returns `{:ok, result}` or `{:error, reason}`.
  """
  def execute(project, parsed_data, opts \\ []) do
    StoryarnJSONParser.execute(project, parsed_data, opts)
  end
end
