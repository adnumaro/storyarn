defmodule StoryarnWeb.Components.SheetComponents do
  @moduledoc """
  Shared components and helpers for sheet display and navigation.
  """
  use Phoenix.Component

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]

  alias Storyarn.Assets.Asset

  @doc """
  Safely parses an integer from a string, empty string, or nil.

  ## Examples

      iex> parse_int("")
      nil

      iex> parse_int(nil)
      nil

      iex> parse_int("123")
      123

      iex> parse_int(42)
      42
  """
  def parse_int(""), do: nil
  def parse_int(nil), do: nil
  def parse_int(val) when is_integer(val), do: val

  def parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> int
      _ -> nil
    end
  end

  @doc """
  Normalizes a parent_id value, converting empty strings to nil.
  Delegates to parse_int/1 for safe integer parsing.
  """
  def normalize_parent_id(val), do: parse_int(val)

  @avatar_sizes %{
    "sm" => "size-4",
    "md" => "size-5",
    "lg" => "size-6",
    "xl" => "size-10"
  }

  @doc """
  Renders a sheet avatar image or falls back to a default file icon.

  ## Examples

      <.sheet_avatar avatar_asset={@sheet.avatar_asset} />
      <.sheet_avatar avatar_asset={@sheet.avatar_asset} size="xl" />
      <.sheet_avatar avatar_asset={nil} name="Character" />
  """
  attr :avatar_asset, :any, default: nil
  attr :name, :string, default: nil
  attr :size, :string, values: ["sm", "md", "lg", "xl"], default: "md"

  def sheet_avatar(assigns) do
    size_class = Map.get(@avatar_sizes, assigns.size, "size-5")
    has_avatar = has_avatar?(assigns.avatar_asset)

    assigns =
      assigns
      |> assign(:size_class, size_class)
      |> assign(:has_avatar, has_avatar)

    ~H"""
    <img
      :if={@has_avatar}
      src={@avatar_asset.url}
      alt={@name || "Sheet avatar"}
      class={["rounded object-cover", @size_class]}
    />
    <.icon :if={!@has_avatar} name="file" class={"#{@size_class} opacity-60"} />
    """
  end

  defp has_avatar?(nil), do: false
  defp has_avatar?(%Ecto.Association.NotLoaded{}), do: false
  defp has_avatar?(%Asset{} = asset), do: Asset.image?(asset)
  defp has_avatar?(_), do: false
end
