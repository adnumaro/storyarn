defmodule Storyarn.Scenes.ZoneImageExtractor do
  @moduledoc """
  Extracts a cropped + upscaled image fragment from a map's background image,
  bounded to a zone's vertex bounding box.

  Crops directly from the parent map's background image rather than walking up
  to the root ancestor. Intermediate images retain enhanced detail from previous
  upscaling and sharpening steps, producing better visual results at deep levels.

  Returns {:ok, %Asset{}, {width, height}} on success.
  Returns {:error, :no_background_image} when the parent has no background.
  Returns {:error, :image_extraction_failed} on processing failures.
  """

  require Logger

  alias Storyarn.Assets
  alias Storyarn.Assets.Storage
  alias Storyarn.Scenes.SceneZone

  # Target minimum dimension for the output image
  @min_output_size 1000

  @doc """
  Extracts a zone's bounding-box region from the parent map's background image,
  upscales to a minimum usable size, and returns the new Asset with dimensions.

  The `parent_map` must have `:background_asset` preloaded.
  """
  def extract(parent_map, %SceneZone{} = zone, project) do
    zone_bbox = bounding_box(zone.vertices)

    with {:ok, asset} <- get_background_asset(parent_map),
         {:ok, img} <- open_image(asset),
         {:ok, cropped} <- crop_to_bbox(img, zone_bbox),
         {:ok, final} <- ensure_min_size(cropped),
         {:ok, sharpened} <- sharpen(final),
         dims <- {Image.width(sharpened), Image.height(sharpened)},
         {:ok, temp_path} <- write_temp(sharpened),
         {:ok, uploaded_asset} <- upload_and_create_asset(temp_path, zone.name, project) do
      cleanup_temp(temp_path)
      {:ok, uploaded_asset, dims}
    else
      {:error, :no_background_image} = err ->
        err

      {:error, reason} ->
        Logger.warning("[ZoneImageExtractor] Failed: #{inspect(reason)}")
        {:error, :image_extraction_failed}
    end
  end

  @doc "Computes the bounding box of zone vertices as {min_x, min_y, max_x, max_y} in percentages."
  def bounding_box([]), do: {0, 0, 0, 0}

  def bounding_box(vertices) do
    xs = Enum.map(vertices, &access_coord(&1, "x"))
    ys = Enum.map(vertices, &access_coord(&1, "y"))
    {Enum.min(xs), Enum.min(ys), Enum.max(xs), Enum.max(ys)}
  end

  # ---------------------------------------------------------------------------
  # Image processing helpers
  # ---------------------------------------------------------------------------

  defp get_background_asset(%{background_asset_id: nil}), do: {:error, :no_background_image}

  defp get_background_asset(%{background_asset: %{url: url}}) when is_binary(url) do
    {:ok, %{url: url}}
  end

  defp get_background_asset(%{background_asset_id: id}) when is_integer(id) do
    {:error, :no_background_image}
  end

  defp get_background_asset(_), do: {:error, :no_background_image}

  defp open_image(%{url: url}) do
    case resolve_path(url) do
      {:error, _} = err ->
        err

      path when is_binary(path) ->
        case Image.open(path) do
          {:ok, _} = ok -> ok
          {:error, reason} -> {:error, {:open_failed, reason}}
        end
    end
  end

  # Local storage URLs (/uploads/...) need to be resolved to filesystem paths.
  # Validates the resolved path stays within priv/static to prevent path traversal.
  defp resolve_path("/" <> _ = url) do
    base = Path.expand("priv/static")
    resolved = Path.expand(Path.join("priv/static", url))
    if String.starts_with?(resolved, base <> "/"), do: resolved, else: {:error, :path_traversal}
  end

  defp resolve_path(url), do: url

  defp crop_to_bbox(img, {min_x, min_y, max_x, max_y}) do
    {img_w, img_h} = {Image.width(img), Image.height(img)}

    left = round(min_x / 100.0 * img_w)
    top = round(min_y / 100.0 * img_h)
    crop_w = max(1, round((max_x - min_x) / 100.0 * img_w))
    crop_h = max(1, round((max_y - min_y) / 100.0 * img_h))

    # Clamp to image bounds
    left = max(0, min(left, img_w - 1))
    top = max(0, min(top, img_h - 1))
    crop_w = min(crop_w, img_w - left)
    crop_h = min(crop_h, img_h - top)

    Image.crop(img, left, top, crop_w, crop_h)
  end

  defp ensure_min_size(img) do
    w = Image.width(img)
    h = Image.height(img)
    larger = max(w, h)

    if larger < @min_output_size do
      scale = @min_output_size / larger
      Image.resize(img, scale)
    else
      {:ok, img}
    end
  end

  defp sharpen(img) do
    Image.sharpen(img, sigma: 1.5)
  end

  defp write_temp(img) do
    path =
      Path.join(
        System.tmp_dir!(),
        "zone_extract_#{System.unique_integer([:positive])}.webp"
      )

    case Image.write(img, path) do
      {:ok, _} -> {:ok, path}
      {:error, reason} -> {:error, {:write_failed, reason}}
    end
  end

  defp upload_and_create_asset(temp_path, zone_name, project) do
    filename = Assets.sanitize_filename("#{zone_name}_extract.webp")
    key = Assets.generate_key(project, filename)
    content_type = "image/webp"

    with {:ok, binary_data} <- File.read(temp_path),
         {:ok, url} <- Storage.upload(key, binary_data, content_type) do
      Assets.create_asset(project, %{
        filename: filename,
        content_type: content_type,
        size: byte_size(binary_data),
        key: key,
        url: url
      })
    end
  end

  defp cleanup_temp(path) do
    _ = File.rm(path)
    :ok
  end

  @doc "Normalizes zone vertices into child coordinate space (0-100% relative to bounding box)."
  def normalize_vertices_to_bbox(vertices) when length(vertices) < 3, do: nil

  def normalize_vertices_to_bbox(vertices) do
    {min_x, min_y, max_x, max_y} = bounding_box(vertices)
    range_x = max_x - min_x
    range_y = max_y - min_y

    if range_x > 0 and range_y > 0 do
      Enum.map(vertices, fn v ->
        %{
          x: (access_coord(v, "x") - min_x) / range_x * 100,
          y: (access_coord(v, "y") - min_y) / range_y * 100
        }
      end)
    else
      nil
    end
  end

  # Handle both string-keyed maps (from JSONB) and atom-keyed maps
  def access_coord(%{"x" => x}, "x"), do: x
  def access_coord(%{"y" => y}, "y"), do: y
  def access_coord(%{x: x}, "x"), do: x
  def access_coord(%{y: y}, "y"), do: y
end
