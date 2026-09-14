defmodule Storyarn.Ideation.Ideas.Rules.Band do
  @moduledoc false

  # A note lives under its round header. Positions are relative to that
  # header, so the top edge must not go above it. A band is as tall as its
  # content, so nothing bounds a note below.
  def check(%{"y" => y}) when is_number(y) and y < 0, do: {:error, :outside_band}
  def check(_canvas), do: :ok
end
