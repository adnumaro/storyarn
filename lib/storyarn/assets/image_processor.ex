defmodule Storyarn.Assets.ImageProcessor do
  @moduledoc """
  Image processing utilities using libvips via the Image library.

  Provides thumbnail generation, resizing, and metadata extraction.
  Uses pre-built binaries by default - no system dependencies required.

  ## Security

  libvips has significantly fewer CVEs than ImageMagick (8 vs 638),
  making it a much safer choice for processing untrusted image uploads.
  """

  @thumbnail_size 200
  @max_dimension 2048
  @default_quality 85

  @doc """
  Generates a thumbnail for an image.

  ## Options
    * `:size` - Maximum dimension (default: #{@thumbnail_size})
    * `:output_path` - Path to save thumbnail (auto-generated if not provided)

  ## Examples

      iex> generate_thumbnail("/path/to/image.jpg")
      {:ok, "/path/to/image_thumb.jpg"}

      iex> generate_thumbnail("/path/to/image.jpg", size: 100, output_path: "/tmp/thumb.jpg")
      {:ok, "/tmp/thumb.jpg"}
  """
  def generate_thumbnail(source_path, opts \\ []) do
    size = Keyword.get(opts, :size, @thumbnail_size)
    output_path = Keyword.get(opts, :output_path, thumbnail_path(source_path))

    with {:ok, thumbnail} <- Image.thumbnail(source_path, size, fit: :contain),
         {:ok, _} <- Image.write(thumbnail, output_path, quality: @default_quality) do
      {:ok, output_path}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end

  @doc """
  Resizes an image to fit within maximum dimensions.

  ## Options
    * `:max_width` - Maximum width (default: #{@max_dimension})
    * `:max_height` - Maximum height (default: #{@max_dimension})
    * `:output_path` - Output path (default: source_path, in-place)

  ## Examples

      iex> resize("/path/to/large.jpg", max_width: 1024, max_height: 1024)
      {:ok, "/path/to/large.jpg"}
  """
  def resize(source_path, opts \\ []) do
    max_width = Keyword.get(opts, :max_width, @max_dimension)
    max_height = Keyword.get(opts, :max_height, @max_dimension)
    output_path = Keyword.get(opts, :output_path, source_path)

    case Image.open(source_path) do
      {:ok, image} ->
        resize_image(image, source_path, output_path, max_width, max_height)

      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  defp resize_image(image, source_path, output_path, max_width, max_height) do
    width = Image.width(image)
    height = Image.height(image)
    scale = Enum.min([max_width / width, max_height / height, 1.0])

    if scale < 1.0 do
      do_resize(image, output_path, scale)
    else
      copy_if_needed(source_path, output_path)
    end
  end

  defp do_resize(image, output_path, scale) do
    with {:ok, resized} <- Image.resize(image, scale),
         {:ok, _} <- Image.write(resized, output_path) do
      {:ok, output_path}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end

  defp copy_if_needed(source_path, output_path) do
    if output_path != source_path, do: File.cp!(source_path, output_path)
    {:ok, output_path}
  end

  @doc """
  Extracts dimensions from an image.

  ## Examples

      iex> get_dimensions("/path/to/image.jpg")
      {:ok, %{width: 1920, height: 1080}}

      iex> get_dimensions("/nonexistent.jpg")
      {:error, "No such file or directory"}
  """
  def get_dimensions(path) do
    case Image.open(path) do
      {:ok, image} ->
        {:ok, %{width: Image.width(image), height: Image.height(image)}}

      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  @doc """
  Processes an image: generates thumbnail and extracts metadata.

  ## Options
    * `:thumbnail_output` - Path for thumbnail output

  ## Examples

      iex> process_image("/path/to/image.jpg", thumbnail_output: "/tmp/thumb.jpg")
      {:ok, %{thumbnail_path: "/tmp/thumb.jpg", metadata: %{...}}}
  """
  def process_image(source_path, opts \\ []) do
    thumbnail_output = Keyword.get(opts, :thumbnail_output)

    with {:ok, dimensions} <- get_dimensions(source_path),
         {:ok, thumb_path} <- generate_thumbnail(source_path, output_path: thumbnail_output) do
      metadata = %{
        "width" => dimensions.width,
        "height" => dimensions.height,
        "thumbnail_path" => thumb_path
      }

      {:ok, %{thumbnail_path: thumb_path, metadata: metadata}}
    end
  end

  @doc """
  Optimizes an image for web delivery.

  ## Options
    * `:output_path` - Output path (default: source_path)
    * `:quality` - JPEG/WebP quality 1-100 (default: #{@default_quality})

  ## Examples

      iex> optimize("/path/to/image.jpg", quality: 75)
      {:ok, "/path/to/image.jpg"}
  """
  def optimize(source_path, opts \\ []) do
    output_path = Keyword.get(opts, :output_path, source_path)
    quality = Keyword.get(opts, :quality, @default_quality)

    with {:ok, image} <- Image.open(source_path),
         {:ok, _} <- Image.write(image, output_path, quality: quality, strip_metadata: true) do
      {:ok, output_path}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end

  @doc """
  Checks if the image processing library is available.

  With pre-built binaries, this should always return true unless
  there are NIF loading issues.
  """
  def available? do
    Code.ensure_loaded?(Image)
  rescue
    _ -> false
  end

  # Backward compatibility alias
  @doc false
  @deprecated "Use available?/0 instead"
  def imagemagick_available?, do: available?()

  # Private helpers

  defp thumbnail_path(source_path) do
    dir = Path.dirname(source_path)
    ext = Path.extname(source_path)
    base = Path.basename(source_path, ext)
    Path.join(dir, "#{base}_thumb.jpg")
  end

  defp format_error(%Vix.Vips.Image.Error{message: message}), do: message
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
