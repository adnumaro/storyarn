defmodule StoryarnWeb.Components.BlockComponents.GalleryBlocks do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: Storyarn.Gettext

  import StoryarnWeb.Components.CoreComponents,
    only: [block_label: 1, icon: 1, modal: 1, confirm_modal: 1, show_modal: 1, hide_modal: 2]

  import StoryarnWeb.Components.UIComponents, only: [optimization_warning_dialog: 1]

  alias Phoenix.LiveView.JS
  alias Storyarn.Assets

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :gallery_images, :list, default: []
  attr :target, :any, default: nil
  attr :component_id, :string, default: nil

  def gallery_block(assigns) do
    label = get_in(assigns.block.config, ["label"]) || ""
    is_constant = assigns.block.is_constant || false

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:is_constant, is_constant)

    ~H"""
    <div>
      <.block_label
        label={@label}
        is_constant={@is_constant}
        block_type={@block.type}
        block_id={@block.id}
        can_edit={@can_edit}
        target={@target}
      />

      <%= if @gallery_images == [] do %>
        <div class="text-sm text-base-content/40 py-4 text-center border border-dashed border-base-300 rounded-lg">
          <.icon name="images" class="size-5 mb-1 opacity-40" />
          <p>{dgettext("sheets", "No images yet")}</p>
        </div>
      <% else %>
        <div
          class="grid gap-2"
          style="grid-template-columns: repeat(auto-fill, minmax(80px, 1fr));"
          id={"gallery-grid-#{@block.id}"}
          phx-hook="GallerySortable"
          data-block-id={@block.id}
          data-target={"##{@component_id}"}
        >
          <div
            :for={gi <- @gallery_images}
            class="relative group/thumb aspect-square rounded-lg overflow-hidden cursor-pointer border border-base-300 hover:border-primary/50 transition-colors"
            data-id={gi.id}
            phx-click={show_modal("gallery-detail-#{gi.id}")}
          >
            <img
              src={Assets.display_url(gi.asset)}
              alt={gi.label || gi.asset.filename}
              class="w-full h-full object-cover"
              loading="lazy"
            />
            <div
              :if={gi.label && gi.label != ""}
              class="absolute bottom-0 left-0 right-0 bg-base-300/80 px-1 py-0.5 text-xs truncate"
            >
              {gi.label}
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Add images button --%>
      <div :if={@can_edit} class="mt-2">
        <label class="btn btn-ghost btn-xs gap-1 cursor-pointer">
          <.icon name="plus" class="size-3.5" />
          {dgettext("sheets", "Add images")}
          <input
            type="file"
            accept="image/*"
            multiple
            class="hidden"
            id={"gallery-upload-#{@block.id}"}
            phx-hook="GalleryUpload"
            data-block-id={@block.id}
            data-target={"##{@component_id}"}
          />
        </label>
      </div>

      <.optimization_warning_dialog
        id="optimization-warning-gallery"
        message={
          dgettext(
            "sheets",
            "For best results, upload WebP or JPEG images. PNG files will be automatically converted, and the optimized copies will count toward your storage limit."
          )
        }
      />

      <%!-- Detail modals for each image --%>
      <.gallery_detail_modal
        :for={gi <- @gallery_images}
        gallery_image={gi}
        can_edit={@can_edit}
        target={@target}
        block_id={@block.id}
      />
    </div>
    """
  end

  attr :gallery_image, :map, required: true
  attr :can_edit, :boolean, required: true
  attr :target, :any, default: nil
  attr :block_id, :integer, required: true

  defp gallery_detail_modal(assigns) do
    ~H"""
    <.modal id={"gallery-detail-#{@gallery_image.id}"}>
      <div class="flex flex-col gap-4">
        <%!-- Large preview --%>
        <div class="flex justify-center bg-base-300/30 rounded-lg overflow-hidden max-h-[60vh]">
          <img
            src={@gallery_image.asset.url}
            alt={@gallery_image.label || @gallery_image.asset.filename}
            class="max-w-full max-h-[60vh] object-contain"
          />
        </div>

        <%!-- Filename --%>
        <p class="text-xs text-base-content/50 truncate">
          {@gallery_image.asset.filename}
        </p>

        <%!-- Label input --%>
        <div>
          <label class="label text-xs">{dgettext("sheets", "Label")}</label>
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            value={@gallery_image.label || ""}
            placeholder={dgettext("sheets", "Optional label...")}
            disabled={!@can_edit}
            phx-blur="update_gallery_image"
            phx-value-gallery-image-id={@gallery_image.id}
            phx-value-field="label"
            phx-target={@target}
          />
        </div>

        <%!-- Description textarea --%>
        <div>
          <label class="label text-xs">{dgettext("sheets", "Description")}</label>
          <textarea
            class="textarea textarea-bordered textarea-sm w-full"
            rows="3"
            placeholder={dgettext("sheets", "Optional description...")}
            disabled={!@can_edit}
            phx-blur="update_gallery_image"
            phx-value-gallery-image-id={@gallery_image.id}
            phx-value-field="description"
            phx-target={@target}
          >{@gallery_image.description || ""}</textarea>
        </div>

        <%!-- Actions --%>
        <div :if={@can_edit} class="flex justify-end">
          <button
            type="button"
            class="btn btn-error btn-sm btn-outline gap-1"
            phx-click={show_modal("confirm-delete-gallery-#{@gallery_image.id}")}
          >
            <.icon name="trash-2" class="size-3.5" />
            {dgettext("sheets", "Delete")}
          </button>
        </div>
      </div>
    </.modal>

    <.confirm_modal
      :if={@can_edit}
      id={"confirm-delete-gallery-#{@gallery_image.id}"}
      title={dgettext("sheets", "Delete image")}
      message={dgettext("sheets", "Are you sure you want to remove this image from the gallery?")}
      confirm_text={dgettext("sheets", "Delete")}
      confirm_variant="error"
      on_confirm={
        JS.push("remove_gallery_image",
          value: %{gallery_image_id: @gallery_image.id, block_id: @block_id},
          target: @target
        )
        |> hide_modal("confirm-delete-gallery-#{@gallery_image.id}")
        |> hide_modal("gallery-detail-#{@gallery_image.id}")
      }
    />
    """
  end
end
