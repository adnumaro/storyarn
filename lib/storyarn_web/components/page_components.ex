defmodule StoryarnWeb.Components.PageComponents do
  @moduledoc """
  Shared components and helpers for page display and navigation.
  """
  use Phoenix.Component

  import StoryarnWeb.CoreComponents, only: [icon: 1]

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

  @page_icon_sizes %{
    "sm" => {"size-4", "text-sm"},
    "md" => {"size-5", "text-base"},
    "lg" => {"size-6", "text-lg"},
    "xl" => {"size-10", "text-5xl"}
  }

  @doc """
  Renders a page icon, either as an emoji or a default file icon.

  ## Examples

      <.page_icon icon="📄" />
      <.page_icon icon={@page.icon} size="lg" />
      <.page_icon size="xl" />
  """
  attr :icon, :string, default: nil
  attr :size, :string, values: ["sm", "md", "lg", "xl"], default: "md"

  def page_icon(assigns) do
    {size_class, text_size} = Map.get(@page_icon_sizes, assigns.size, {"size-5", "text-base"})
    is_emoji = assigns.icon && assigns.icon not in [nil, "", "page"]

    assigns =
      assigns
      |> assign(:size_class, size_class)
      |> assign(:text_size, text_size)
      |> assign(:is_emoji, is_emoji)

    ~H"""
    <span :if={@is_emoji} class={@text_size}>{@icon}</span>
    <.icon :if={!@is_emoji} name="file" class={"#{@size_class} opacity-60"} />
    """
  end
end
