defmodule Storyarn.Projects.Imports.ParserRegistry do
  @moduledoc """
  Compatibility entry point for selecting a parser from an uploaded filename.

  Parser and post-parse adapter registration share one closed source of truth in
  `Storyarn.Projects.Imports.FormatRegistry`, so a newly accepted parser cannot
  produce plans that execution does not recognize.
  """

  alias Storyarn.Projects.Imports.FormatRegistry

  @spec parser_for(String.t()) :: {:ok, module()} | {:error, :unsupported_import_format}
  defdelegate parser_for(filename), to: FormatRegistry
end
