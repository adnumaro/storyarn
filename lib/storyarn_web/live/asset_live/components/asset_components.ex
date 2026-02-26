defmodule StoryarnWeb.AssetLive.Components.AssetComponents do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext
  use StoryarnWeb, :verified_routes

  import StoryarnWeb.Components.CoreComponents

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset

  attr :asset, :map, required: true
  attr :selected, :boolean, default: false

  def asset_card(assigns) do
    ~H"""
    <div
      class={[
        "card bg-base-100 border shadow-sm hover:shadow-md transition-shadow cursor-pointer overflow-hidden",
        @selected && "border-primary ring-2 ring-primary/20",
        !@selected && "border-base-300"
      ]}
      phx-click="select_asset"
      phx-value-id={@asset.id}
    >
      <figure class="h-32 bg-base-200 flex items-center justify-center">
        <img
          :if={Assets.image?(@asset)}
          src={@asset.url}
          alt={@asset.filename}
          class="w-full h-full object-cover"
        />
        <div :if={Assets.audio?(@asset)} class="text-center">
          <.icon name="music" class="size-10 text-base-content/30" />
        </div>
        <div :if={!Assets.image?(@asset) and !Assets.audio?(@asset)} class="text-center">
          <.icon name="file" class="size-10 text-base-content/30" />
        </div>
      </figure>

      <div class="card-body p-3">
        <p class="text-sm font-medium truncate" title={@asset.filename}>{@asset.filename}</p>
        <div class="flex items-center justify-between text-xs text-base-content/60">
          <span>{format_size(@asset.size)}</span>
          <span class={["badge badge-xs", type_badge_class(@asset)]}>{type_label(@asset)}</span>
        </div>
      </div>
    </div>
    """
  end

  attr :asset, :map, required: true
  attr :usages, :map, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :can_edit, :boolean, default: false

  def detail_panel(assigns) do
    total_usages =
      length(assigns.usages.flow_nodes) +
        length(assigns.usages.sheet_avatars) +
        length(assigns.usages.sheet_banners)

    assigns = assign(assigns, :total_usages, total_usages)

    ~H"""
    <div class="w-80 flex-shrink-0 border border-base-300 rounded-lg bg-base-100 p-4 space-y-4 self-start">
      <div class="flex items-center justify-between">
        <h3 class="font-semibold text-sm">{dgettext("assets", "Details")}</h3>
        <button type="button" phx-click="deselect_asset" class="btn btn-ghost btn-xs btn-square">
          <.icon name="x" class="size-4" />
        </button>
      </div>

      <div class="rounded-lg overflow-hidden bg-base-200">
        <img
          :if={Assets.image?(@asset)}
          src={@asset.url}
          alt={@asset.filename}
          class="w-full object-contain max-h-48"
        />
        <div :if={Assets.audio?(@asset)} class="p-4">
          <audio controls class="w-full">
            <source src={@asset.url} type={@asset.content_type} />
          </audio>
        </div>
        <div
          :if={!Assets.image?(@asset) and !Assets.audio?(@asset)}
          class="p-6 flex items-center justify-center"
        >
          <.icon name="file" class="size-12 text-base-content/30" />
        </div>
      </div>

      <dl class="text-sm space-y-2">
        <div>
          <dt class="text-base-content/50">{dgettext("assets", "Filename")}</dt>
          <dd class="font-medium break-all">{@asset.filename}</dd>
        </div>
        <div>
          <dt class="text-base-content/50">{dgettext("assets", "Type")}</dt>
          <dd>{@asset.content_type}</dd>
        </div>
        <div>
          <dt class="text-base-content/50">{dgettext("assets", "Size")}</dt>
          <dd>{format_size(@asset.size)}</dd>
        </div>
        <div>
          <dt class="text-base-content/50">{dgettext("assets", "Uploaded")}</dt>
          <dd>{Calendar.strftime(@asset.inserted_at, "%b %d, %Y")}</dd>
        </div>
      </dl>

      <div class="border-t border-base-300 pt-4">
        <h4 class="text-sm font-medium mb-2 flex items-center gap-2">
          <.icon name="link" class="size-4" />
          {dgettext("assets", "Usage")}
          <span class="badge badge-xs">{@total_usages}</span>
        </h4>

        <div :if={@total_usages == 0} class="text-sm text-base-content/50">
          {dgettext("assets", "Not used anywhere")}
        </div>

        <ul :if={@total_usages > 0} class="text-sm space-y-1">
          <li :for={usage <- @usages.flow_nodes} class="flex items-center gap-2">
            <.icon name="git-branch" class="size-3 text-base-content/50" />
            <.link
              navigate={
                ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows/#{usage.flow_id}"
              }
              class="text-primary hover:underline truncate"
            >
              {usage.flow_name}
            </.link>
          </li>
          <li :for={sheet <- @usages.sheet_avatars} class="flex items-center gap-2">
            <.icon name="user" class="size-3 text-base-content/50" />
            <.link
              navigate={
                ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/sheets/#{sheet.id}"
              }
              class="text-primary hover:underline truncate"
            >
              {sheet.name}
              <span class="text-base-content/40">({dgettext("assets", "avatar")})</span>
            </.link>
          </li>
          <li :for={sheet <- @usages.sheet_banners} class="flex items-center gap-2">
            <.icon name="image" class="size-3 text-base-content/50" />
            <.link
              navigate={
                ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/sheets/#{sheet.id}"
              }
              class="text-primary hover:underline truncate"
            >
              {sheet.name}
              <span class="text-base-content/40">({dgettext("assets", "banner")})</span>
            </.link>
          </li>
        </ul>
      </div>

      <div :if={@can_edit} class="border-t border-base-300 pt-4">
        <button
          type="button"
          class="btn btn-error btn-sm btn-outline w-full"
          phx-click={show_modal("delete-asset-confirm")}
        >
          <.icon name="trash-2" class="size-4" />
          {dgettext("assets", "Delete asset")}
        </button>
      </div>
    </div>
    """
  end

  def format_size(nil), do: ""
  def format_size(bytes) when bytes < 1_024, do: "#{bytes} B"
  def format_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1_024, 1)} KB"
  def format_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  def type_label(%Asset{} = asset) do
    cond do
      Assets.image?(asset) -> dgettext("assets", "Image")
      Assets.audio?(asset) -> dgettext("assets", "Audio")
      true -> dgettext("assets", "File")
    end
  end

  def type_badge_class(%Asset{} = asset) do
    cond do
      Assets.image?(asset) -> "badge-primary"
      Assets.audio?(asset) -> "badge-secondary"
      true -> "badge-ghost"
    end
  end
end
