defmodule StoryarnTest.AI.GraphemeTokenizer do
  @moduledoc false

  def count(encoded) when is_binary(encoded), do: encoded |> String.graphemes() |> length()
end
