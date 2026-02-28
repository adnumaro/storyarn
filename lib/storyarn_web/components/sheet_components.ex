defmodule StoryarnWeb.Components.SheetComponents do
  @moduledoc """
  Shared components and helpers for sheet display and navigation.
  """
  use StoryarnWeb, :html

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset

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
  defp has_avatar?(%Asset{} = asset), do: Assets.image?(asset)
  defp has_avatar?(_), do: false

  @doc """
  Renders a floating breadcrumb pill for sheet ancestors — matches the map/flow info bar style.
  Used in the `top_bar_extra` slot of the focus layout.
  """
  attr :ancestors, :list, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true

  def sheet_breadcrumb(assigns) do
    ~H"""
    <div class="hidden lg:flex items-center gap-1 surface-panel px-3 py-1.5">
      <span
        :for={{ancestor, idx} <- Enum.with_index(@ancestors)}
        class="flex items-center gap-1 text-xs text-base-content/60"
      >
        <span :if={idx > 0} class="opacity-50">/</span>
        <.link
          navigate={
            ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/sheets/#{ancestor.id}"
          }
          class="hover:text-base-content flex items-center gap-1 truncate max-w-[120px]"
        >
          <.sheet_avatar avatar_asset={ancestor.avatar_asset} name={ancestor.name} size="sm" />
          {ancestor.name}
        </.link>
      </span>
    </div>
    """
  end
end
