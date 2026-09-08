defmodule Storyarn.Ideation.Ideas.Rules.Canvas do
  @moduledoc false
  @colors ~w(yellow coral mint blue violet paper)

  def normalize(attrs) when is_map(attrs) do
    attrs |> Map.put_new("width", 280) |> Map.put_new("color", "yellow") |> validate()
  end

  def normalize(_), do: {:error, :invalid_canvas}

  defp validate(%{"x" => x, "y" => y, "width" => width, "color" => color} = attrs)
       when is_number(x) and is_number(y) and is_number(width) and abs(x) <= 1_000_000 and abs(y) <= 1_000_000 and
              width >= 180 and width <= 800 and color in @colors do
    {:ok, Map.take(attrs, ~w(x y width color))}
  end

  defp validate(_), do: {:error, :invalid_canvas}
end
