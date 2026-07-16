defmodule Storyarn.Imports.ParserRegistry do
  @moduledoc false

  alias Storyarn.Imports.Parsers.StoryarnJSON
  alias Storyarn.Imports.Parsers.Yarn

  @spec parser_for(String.t()) :: {:ok, module()} | {:error, :unsupported_import_format}
  def parser_for(filename) when is_binary(filename) do
    case filename |> Path.extname() |> String.downcase() do
      ".json" -> {:ok, StoryarnJSON}
      ".yarn" -> {:ok, Yarn}
      ".zip" -> {:ok, Yarn}
      _other -> {:error, :unsupported_import_format}
    end
  end
end
