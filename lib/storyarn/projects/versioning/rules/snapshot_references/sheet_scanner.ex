defmodule Storyarn.Projects.Versioning.SnapshotReferences.SheetScanner do
  @moduledoc "Extracts portable references from a Sheet snapshot without I/O."

  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Projects.References.EntityReferenceExtraction

  @spec scan(map()) :: [map()]
  def scan(snapshot) do
    refs =
      []
      |> add_avatar_refs(snapshot)
      |> add_hidden_block_refs(snapshot)
      |> maybe_add_ref(:asset, snapshot["banner_asset_id"], dgettext("sheets", "Banner image"))

    (snapshot["blocks"] || [])
    |> Enum.with_index(1)
    |> Enum.reduce(refs, fn {block, idx}, acc ->
      acc
      |> maybe_add_ref(
        :block,
        block["inherited_from_block_id"],
        dgettext("sheets", "Block #%{n} — inherited source", n: idx)
      )
      |> add_block_value_refs(block, idx)
      |> add_gallery_refs(block, idx)
    end)
  end

  defp add_avatar_refs(refs, %{"avatars" => avatars}) when is_list(avatars) and avatars != [] do
    Enum.reduce(avatars, refs, fn avatar, acc ->
      maybe_add_ref(acc, :asset, avatar["asset_id"], dgettext("sheets", "Avatar image"))
    end)
  end

  defp add_avatar_refs(refs, snapshot) do
    maybe_add_ref(refs, :asset, snapshot["avatar_asset_id"], dgettext("sheets", "Avatar image"))
  end

  defp add_hidden_block_refs(refs, snapshot) do
    Enum.reduce(snapshot["hidden_inherited_block_ids"] || [], refs, fn block_id, acc ->
      maybe_add_ref(
        acc,
        :block,
        block_id,
        dgettext("sheets", "Hidden inherited block")
      )
    end)
  end

  defp add_gallery_refs(refs, %{"gallery_images" => images}, block_index) when is_list(images) do
    Enum.reduce(images, refs, fn image, acc ->
      maybe_add_ref(acc, :asset, image["asset_id"], dgettext("sheets", "Block #%{n} gallery image", n: block_index))
    end)
  end

  defp add_gallery_refs(refs, _block, _block_index), do: refs

  defp add_block_value_refs(refs, block, block_index) do
    case EntityReferenceExtraction.extract_block_value_references(block["type"], block["value"]) do
      {:ok, references} ->
        Enum.reduce(references, refs, fn reference, acc ->
          maybe_add_ref(
            acc,
            reference_type(reference.type),
            reference.id,
            block_reference_context(reference.context, block_index)
          )
        end)

      {:error, reason} ->
        [
          %{
            type: :reference,
            id: malformed_reference_id(reason),
            context:
              dgettext(
                "sheets",
                "Block #%{n} — malformed embedded reference",
                n: block_index
              )
          }
          | refs
        ]
    end
  end

  defp reference_type("sheet"), do: :sheet
  defp reference_type("flow"), do: :flow

  defp block_reference_context("value", block_index) do
    dgettext("sheets", "Block #%{n} — reference target", n: block_index)
  end

  defp block_reference_context("content", block_index) do
    dgettext("sheets", "Block #%{n} — rich-text mention", n: block_index)
  end

  defp malformed_reference_id({:invalid_project_reference, _context, id})
       when is_integer(id) or is_binary(id) or is_nil(id), do: id

  defp malformed_reference_id({:invalid_project_reference, _context, details}), do: inspect(details)

  defp malformed_reference_id(_reason), do: nil

  defp maybe_add_ref(refs, _type, nil, _context), do: refs

  defp maybe_add_ref(refs, type, id, context), do: [%{type: type, id: id, context: context} | refs]
end
