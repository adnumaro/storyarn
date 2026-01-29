defmodule Storyarn.Assets.ImageProcessor do
  @moduledoc """
  Image processing utilities using ImageMagick via Mogrify.

  Provides thumbnail generation, resizing, and metadata extraction.

  ## Requirements

  ImageMagick must be installed on the system:

      # macOS
      brew install imagemagick

      # Ubuntu/Debian
      apt-get install imagemagick
  """

  @thumbnail_size 200
  @max_dimension 2048

  @doc """
  Generates a thumbnail for an image.

  Returns `{:ok, thumbnail_path}` or `{:error, reason}`.
  """
  def generate_thumbnail(source_path, opts \\ []) do
    size = Keyword.get(opts, :size, @thumbnail_size)
    output_path = Keyword.get(opts, :output_path, thumbnail_path(source_path))

    try do
      source_path
      |> Mogrify.open()
      |> Mogrify.resize_to_limit("#{size}x#{size}")
      |> Mogrify.quality("85")
      |> Mogrify.format("jpeg")
      |> Mogrify.save(path: output_path)

      {:ok, output_path}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @doc """
  Resizes an image to fit within maximum dimensions.

  Returns `{:ok, resized_path}` or `{:error, reason}`.
  """
  def resize(source_path, opts \\ []) do
    max_width = Keyword.get(opts, :max_width, @max_dimension)
    max_height = Keyword.get(opts, :max_height, @max_dimension)
    output_path = Keyword.get(opts, :output_path, source_path)

    try do
      source_path
      |> Mogrify.open()
      |> Mogrify.resize_to_limit("#{max_width}x#{max_height}")
      |> Mogrify.save(path: output_path)

      {:ok, output_path}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @doc """
  Extracts dimensions from an image.

  Returns `{:ok, %{width: w, height: h}}` or `{:error, reason}`.
  """
  def get_dimensions(path) do
    image = Mogrify.open(path) |> Mogrify.verbose()
    {:ok, %{width: image.width, height: image.height}}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Processes an uploaded image: generates thumbnail and extracts metadata.

  Returns `{:ok, %{thumbnail_path: path, metadata: map}}` or `{:error, reason}`.
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
  Optimizes an image for web (strips metadata, converts to efficient format).

  Returns `{:ok, optimized_path}` or `{:error, reason}`.
  """
  def optimize(source_path, opts \\ []) do
    output_path = Keyword.get(opts, :output_path, source_path)
    quality = Keyword.get(opts, :quality, 85)

    try do
      source_path
      |> Mogrify.open()
      |> Mogrify.custom("strip")
      |> Mogrify.quality("#{quality}")
      |> Mogrify.save(path: output_path)

      {:ok, output_path}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @doc """
  Checks if ImageMagick is available on the system.
  """
  def imagemagick_available? do
    case System.find_executable("convert") do
      nil -> false
      _path -> true
    end
  end

  defp thumbnail_path(source_path) do
    dir = Path.dirname(source_path)
    ext = Path.extname(source_path)
    base = Path.basename(source_path, ext)
    Path.join(dir, "#{base}_thumb.jpg")
  end
end
