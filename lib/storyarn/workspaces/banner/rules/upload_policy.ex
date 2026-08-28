defmodule Storyarn.Workspaces.Banner.Rules.UploadPolicy do
  @moduledoc false

  @upload_limits Application.compile_env!(:storyarn, __MODULE__)
  @max_file_size Keyword.fetch!(@upload_limits, :max_file_size)
  @accepted_content_types ~w(image/jpeg image/png image/gif image/webp)
  @content_type_by_loader %{
    "jpegload" => "image/jpeg",
    "pngload" => "image/png",
    "gifload" => "image/gif",
    "nsgifload" => "image/gif",
    "webpload" => "image/webp"
  }

  @type validated_upload :: %{
          filename: String.t(),
          content_type: String.t(),
          binary: binary()
        }

  @spec validate(map()) :: {:ok, validated_upload()} | {:error, :invalid_banner_upload}
  def validate(attrs) do
    filename = value(attrs, :filename)
    content_type = value(attrs, :content_type)
    data = value(attrs, :data)

    with true <- valid_upload_strings?(filename, content_type, data),
         {:ok, safe_filename} <- sanitize_filename(filename),
         true <- accepted_content_type?(content_type),
         true <- MIME.from_path(safe_filename) == content_type,
         [header, encoded] <- String.split(data, ",", parts: 2),
         true <- header == "data:#{content_type};base64",
         :ok <- validate_encoded_size(encoded),
         {:ok, binary} <- Base.decode64(encoded),
         true <- byte_size(binary) > 0 and byte_size(binary) <= @max_file_size,
         {:ok, ^content_type} <- content_type_from_binary(binary) do
      {:ok, %{filename: safe_filename, content_type: content_type, binary: binary}}
    else
      _ -> {:error, :invalid_banner_upload}
    end
  end

  @spec accepted_content_type?(term()) :: boolean()
  def accepted_content_type?(content_type), do: content_type in @accepted_content_types

  defp valid_upload_strings?(filename, content_type, data) do
    is_binary(filename) and String.valid?(filename) and String.trim(filename) != "" and
      byte_size(filename) <= 255 and is_binary(content_type) and String.valid?(content_type) and
      is_binary(data) and String.valid?(data)
  end

  defp sanitize_filename(filename) do
    sanitized =
      filename
      |> String.split(~r/[\/\\]/)
      |> List.last()
      |> String.replace(~r/[^\w\.\-]/u, "_")
      |> String.downcase()
      |> String.slice(0, 180)

    if sanitized in ["", ".", ".."],
      do: {:error, :invalid_filename},
      else: {:ok, sanitized}
  end

  defp validate_encoded_size(encoded) when is_binary(encoded) do
    max_encoded_size = 4 * div(@max_file_size + 2, 3)
    if byte_size(encoded) <= max_encoded_size, do: :ok, else: {:error, :too_large}
  end

  defp validate_encoded_size(_encoded), do: {:error, :too_large}

  defp content_type_from_binary(binary) do
    with {:ok, image} <- Image.open(binary),
         {:ok, loader} <- Vix.Vips.Image.header_value(image, "vips-loader"),
         content_type when is_binary(content_type) <- content_type_for_loader(loader) do
      {:ok, content_type}
    else
      _ -> {:error, :unsupported_image}
    end
  end

  defp content_type_for_loader(loader) when is_binary(loader) do
    loader
    |> String.replace_suffix("_buffer", "")
    |> then(&Map.get(@content_type_by_loader, &1))
  end

  defp content_type_for_loader(_loader), do: nil

  defp value(attrs, key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
  end
end
