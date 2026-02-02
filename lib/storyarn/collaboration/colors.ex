defmodule Storyarn.Collaboration.Colors do
  @moduledoc false

  @doc """
  Returns a deterministic color for a user based on their ID.
  Uses a 12-color palette designed for visibility on both light and dark themes.
  """
  @spec for_user(integer()) :: String.t()
  def for_user(user_id) when is_integer(user_id) do
    Enum.at(palette(), rem(user_id, length(palette())))
  end

  @doc """
  Returns the full color palette used for user colors.
  """
  @spec palette() :: [String.t()]
  def palette do
    [
      # red-500
      "#ef4444",
      # orange-500
      "#f97316",
      # amber-500
      "#f59e0b",
      # lime-500
      "#84cc16",
      # green-500
      "#22c55e",
      # teal-500
      "#14b8a6",
      # cyan-500
      "#06b6d4",
      # blue-500
      "#3b82f6",
      # indigo-500
      "#6366f1",
      # violet-500
      "#8b5cf6",
      # fuchsia-500
      "#d946ef",
      # pink-500
      "#ec4899"
    ]
  end

  @doc """
  Returns a lighter version of the user's color (for cursor trails, etc.).
  """
  @spec for_user_light(integer()) :: String.t()
  def for_user_light(user_id) when is_integer(user_id) do
    Enum.at(palette_light(), rem(user_id, length(palette_light())))
  end

  @spec palette_light() :: [String.t()]
  defp palette_light do
    [
      # red-300
      "#fca5a5",
      # orange-300
      "#fdba74",
      # amber-300
      "#fcd34d",
      # lime-300
      "#bef264",
      # green-300
      "#86efac",
      # teal-300
      "#5eead4",
      # cyan-300
      "#67e8f9",
      # blue-300
      "#93c5fd",
      # indigo-300
      "#a5b4fc",
      # violet-300
      "#c4b5fd",
      # fuchsia-300
      "#f0abfc",
      # pink-300
      "#f9a8d4"
    ]
  end
end
