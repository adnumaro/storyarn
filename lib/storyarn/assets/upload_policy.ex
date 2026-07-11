defmodule Storyarn.Assets.UploadPolicy do
  @moduledoc """
  Upload profiles for image placements.

  A source image can be kept once and then materialized into placement-specific
  assets such as a square avatar or a wide sheet banner.
  """

  @max_image_size 52_428_800
  @multipart_request_overhead 1_048_576
  @image_types ~w(image/jpeg image/png image/gif image/webp)

  @profiles %{
    avatar: %{
      profile: "sheet_avatar_500",
      target: %{width: 500, height: 500, crop: true},
      max_file_size: @max_image_size,
      accept: @image_types
    },
    banner: %{
      profile: "sheet_banner_1920x640",
      target: %{width: 1920, height: 640, crop: true},
      max_file_size: @max_image_size,
      accept: @image_types
    },
    scene_background: %{
      profile: "scene_background_web",
      target: nil,
      max_file_size: @max_image_size,
      accept: @image_types
    }
  }

  @type purpose :: :avatar | :banner | :scene_background
  @type profile :: %{
          profile: String.t(),
          target: map() | nil,
          max_file_size: pos_integer(),
          accept: [String.t()]
        }

  @spec supported_purpose?(atom()) :: boolean()
  def supported_purpose?(purpose), do: Map.has_key?(@profiles, purpose)

  @spec max_file_size() :: pos_integer()
  def max_file_size, do: @max_image_size

  @spec max_request_size() :: pos_integer()
  def max_request_size, do: @max_image_size + @multipart_request_overhead

  @spec profile_for(atom()) :: {:ok, profile()} | {:error, :unsupported_purpose}
  def profile_for(purpose) do
    case Map.fetch(@profiles, purpose) do
      {:ok, profile} -> {:ok, profile}
      :error -> {:error, :unsupported_purpose}
    end
  end

  @spec parse_purpose(atom() | String.t() | nil) :: atom()
  def parse_purpose(:avatar), do: :avatar
  def parse_purpose(:banner), do: :banner
  def parse_purpose(:gallery), do: :gallery
  def parse_purpose(:scene_background), do: :scene_background
  def parse_purpose("avatar"), do: :avatar
  def parse_purpose("banner"), do: :banner
  def parse_purpose("gallery"), do: :gallery
  def parse_purpose("scene_background"), do: :scene_background
  def parse_purpose(_), do: :general

  @spec validate(profile(), map()) :: :ok | {:error, atom()}
  def validate(profile, metadata) do
    cond do
      metadata.content_type not in profile.accept ->
        {:error, :not_accepted}

      metadata.size > profile.max_file_size ->
        {:error, :too_large}

      true ->
        :ok
    end
  end

  @doc """
  Rejects Base64 payloads that cannot decode within the profile file-size limit.

  This check is intentionally performed before decoding so oversized LiveView
  events do not allocate a second, decoded binary in the LiveView process.
  """
  @spec validate_base64_size(profile(), binary()) :: :ok | {:error, :too_large}
  def validate_base64_size(%{max_file_size: max_file_size}, encoded_data)
      when is_integer(max_file_size) and is_binary(encoded_data) do
    max_encoded_size = 4 * div(max_file_size + 2, 3)

    if byte_size(encoded_data) <= max_encoded_size,
      do: :ok,
      else: {:error, :too_large}
  end

  def validate_base64_size(_profile, _encoded_data), do: {:error, :too_large}

  @spec normalize_metadata(map()) :: {:ok, map()} | {:error, atom()}
  def normalize_metadata(attrs) do
    with {:ok, source_hash} <- fetch_hash(attrs),
         {:ok, size} <- fetch_int(attrs, "size"),
         {:ok, width} <- fetch_optional_int(attrs, "width"),
         {:ok, height} <- fetch_optional_int(attrs, "height"),
         {:ok, content_type} <- fetch_string(attrs, "content_type"),
         {:ok, filename} <- fetch_string(attrs, "filename") do
      {:ok,
       %{
         source_hash: source_hash,
         size: size,
         width: width,
         height: height,
         content_type: content_type,
         filename: filename
       }}
    end
  end

  defp fetch_hash(attrs) do
    with {:ok, value} <- fetch_string(attrs, "hash"),
         true <- Regex.match?(~r/\A[0-9a-f]{64}\z/, value) do
      {:ok, value}
    else
      _ -> {:error, :invalid_hash}
    end
  end

  defp fetch_string(attrs, key) do
    case value(attrs, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :invalid_metadata}
    end
  end

  defp fetch_int(attrs, key) do
    case parse_int(value(attrs, key)) do
      int when is_integer(int) and int > 0 -> {:ok, int}
      _ -> {:error, :invalid_metadata}
    end
  end

  defp fetch_optional_int(attrs, key) do
    case parse_int(value(attrs, key)) do
      int when is_integer(int) and int > 0 -> {:ok, int}
      _ -> {:ok, nil}
    end
  end

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

  defp value(attrs, key) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> value
      :error -> atom_key_value(attrs, key)
    end
  end

  defp atom_key_value(attrs, key) do
    attrs
    |> Enum.find_value(fn
      {attr_key, value} when is_atom(attr_key) ->
        if Atom.to_string(attr_key) == key, do: {:ok, value}

      _ ->
        false
    end)
    |> case do
      {:ok, value} -> value
      nil -> nil
    end
  end
end
