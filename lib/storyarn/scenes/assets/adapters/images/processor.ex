defmodule Storyarn.Scenes.Assets.Adapters.Images.Processor do
  @moduledoc false

  @default_quality 85
  @web_optimized_types ~w(image/webp image/jpeg)

  def available? do
    Code.ensure_loaded?(Image)
  rescue
    _error -> false
  end

  def dimensions(path) when is_binary(path) do
    case Image.open(path) do
      {:ok, image} -> {:ok, %{width: Image.width(image), height: Image.height(image)}}
      {:error, reason} -> {:error, format_error(reason)}
    end
  end

  def needs_scene_background_variant?(content_type), do: content_type not in @web_optimized_types

  @spec to_webp(binary()) :: {:ok, binary()} | {:error, term()}
  # sobelow_skip ["Traversal.FileModule"]
  def to_webp(binary) when is_binary(binary) do
    input = temporary_path("scene-input")
    output = temporary_path("scene-output") <> ".webp"

    try do
      File.write!(input, binary)

      with {:ok, image} <- Image.open(input),
           {:ok, _image} <- Image.write(image, output, quality: @default_quality) do
        {:ok, File.read!(output)}
      else
        {:error, reason} -> {:error, format_error(reason)}
      end
    after
      File.rm(input)
      File.rm(output)
    end
  end

  defp temporary_path(prefix) do
    Path.join(System.tmp_dir!(), "storyarn-#{prefix}-#{Ecto.UUID.generate()}")
  end

  defp format_error(%Vix.Vips.Image.Error{message: message}), do: message
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
