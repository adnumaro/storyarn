defmodule StoryarnWeb.Components.PageComponents do
  @moduledoc """
  Shared components and helpers for page display and navigation.
  """
  use Phoenix.Component

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]

  alias Storyarn.Assets.Asset

  @doc """
  Normalizes a parent_id value, converting empty strings to nil.

  ## Examples

      iex> normalize_parent_id("")
      nil

      iex> normalize_parent_id(nil)
      nil

      iex> normalize_parent_id("123")
      "123"
  """
  def normalize_parent_id(""), do: nil
  def normalize_parent_id(nil), do: nil
  def normalize_parent_id(parent_id), do: parent_id

  @avatar_sizes %{
    "sm" => "size-4",
    "md" => "size-5",
    "lg" => "size-6",
    "xl" => "size-10"
  }

  @doc """
  Renders a page avatar image or falls back to a default file icon.

  ## Examples

      <.page_avatar avatar_asset={@page.avatar_asset} />
      <.page_avatar avatar_asset={@page.avatar_asset} size="xl" />
      <.page_avatar avatar_asset={nil} name="Character" />
  """
  attr :avatar_asset, :any, default: nil
  attr :name, :string, default: nil
  attr :size, :string, values: ["sm", "md", "lg", "xl"], default: "md"

  def page_avatar(assigns) do
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
      alt={@name || "Page avatar"}
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
