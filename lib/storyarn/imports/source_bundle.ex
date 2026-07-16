defmodule Storyarn.Imports.SourceBundle do
  @moduledoc """
  Validates and opens an uploaded Yarn source without touching the filesystem.

  ZIP metadata is checked before extraction. Paths, archive nesting, entry
  count, expansion ratio, individual size, and total expanded size are all
  bounded to limit traversal and decompression-bomb attacks.
  """

  @max_upload_bytes 50_000_000
  @max_entry_bytes 10_000_000
  @max_expanded_bytes 50_000_000
  @max_entries 500
  @max_expansion_ratio 200
  @max_zip_comment_bytes 65_535
  @max_central_directory_bytes 2_000_000
  @max_zip_entry_name_bytes 1_024
  @zip_eocd_bytes 22
  @zip64_sentinel_16 0xFFFF
  @zip64_sentinel_32 0xFFFFFFFF
  @allowed_extensions MapSet.new([".yarn", ".yarnproject", ".csv", ".json"])
  @archive_extensions MapSet.new([".zip", ".tar", ".gz", ".tgz", ".7z", ".rar"])

  @enforce_keys [:kind, :files]
  defstruct [:kind, :files]

  @type source_file :: %{alias: String.t(), extension: String.t(), content: binary()}
  @type t :: %__MODULE__{kind: :file | :archive, files: [source_file()]}

  @spec open(String.t(), binary()) :: {:ok, t()} | {:error, atom()}
  def open(filename, binary) when is_binary(filename) and is_binary(binary) do
    cond do
      byte_size(binary) > @max_upload_bytes ->
        {:error, :file_too_large}

      filename |> Path.extname() |> String.downcase() == ".yarn" ->
        open_text(binary, ".yarn")

      filename |> Path.extname() |> String.downcase() == ".json" ->
        open_text(binary, ".json")

      filename |> Path.extname() |> String.downcase() == ".zip" ->
        open_zip(binary)

      true ->
        {:error, :unsupported_import_format}
    end
  end

  @spec yarn_files(t()) :: [source_file()]
  def yarn_files(%__MODULE__{files: files}) do
    Enum.filter(files, &(&1.extension == ".yarn"))
  end

  defp open_text(binary, extension) do
    with {:ok, content} <- normalize_text(binary) do
      {:ok,
       %__MODULE__{
         kind: :file,
         files: [%{alias: "source_1", extension: extension, content: content}]
       }}
    end
  end

  defp open_zip(binary) do
    with :ok <- preflight_zip(binary),
         {:ok, entries} <- list_zip(binary),
         :ok <- validate_entry_count(entries),
         {:ok, selected} <- validate_entries(entries),
         {:ok, extracted} <- extract_selected(binary, selected),
         {:ok, files} <- normalize_files(extracted),
         :ok <- require_yarn(files) do
      {:ok, %__MODULE__{kind: :archive, files: files}}
    end
  end

  defp preflight_zip(binary) do
    with {:ok, eocd} <- find_eocd(binary),
         :ok <- validate_eocd(binary, eocd) do
      validate_central_directory(binary, eocd)
    end
  end

  defp find_eocd(binary) do
    binary_size = byte_size(binary)
    tail_size = min(binary_size, @zip_eocd_bytes + @max_zip_comment_bytes)
    tail_offset = binary_size - tail_size
    tail = binary_part(binary, tail_offset, tail_size)

    candidates =
      tail
      |> :binary.matches(<<0x50, 0x4B, 0x05, 0x06>>)
      |> Enum.map(fn {relative_offset, _length} -> tail_offset + relative_offset end)
      |> Enum.filter(&complete_eocd?(binary, &1))

    case candidates do
      [offset] -> parse_eocd(binary, offset)
      _other -> {:error, :invalid_archive}
    end
  end

  defp complete_eocd?(binary, offset) do
    if offset + @zip_eocd_bytes <= byte_size(binary) do
      <<comment_length::little-unsigned-integer-size(16)>> = binary_part(binary, offset + 20, 2)
      offset + @zip_eocd_bytes + comment_length == byte_size(binary)
    else
      false
    end
  end

  defp parse_eocd(binary, offset) do
    size = byte_size(binary) - offset

    case binary_part(binary, offset, size) do
      <<0x50, 0x4B, 0x05, 0x06, disk_number::little-unsigned-integer-size(16),
        central_directory_disk::little-unsigned-integer-size(16), entries_on_disk::little-unsigned-integer-size(16),
        total_entries::little-unsigned-integer-size(16), central_directory_size::little-unsigned-integer-size(32),
        central_directory_offset::little-unsigned-integer-size(32), comment_length::little-unsigned-integer-size(16),
        _comment::binary-size(comment_length)>> ->
        {:ok,
         %{
           offset: offset,
           disk_number: disk_number,
           central_directory_disk: central_directory_disk,
           entries_on_disk: entries_on_disk,
           total_entries: total_entries,
           central_directory_size: central_directory_size,
           central_directory_offset: central_directory_offset
         }}

      _other ->
        {:error, :invalid_archive}
    end
  end

  defp validate_eocd(binary, eocd) do
    with :ok <- validate_no_zip64(binary, eocd),
         :ok <- validate_single_disk(eocd),
         :ok <- validate_eocd_entry_count(eocd) do
      validate_central_directory_bounds(eocd)
    end
  end

  defp validate_no_zip64(binary, eocd) do
    if zip64_locator?(binary, eocd.offset) or zip64_eocd_values?(eocd),
      do: {:error, :invalid_archive},
      else: :ok
  end

  defp validate_single_disk(%{disk_number: 0, central_directory_disk: 0}), do: :ok
  defp validate_single_disk(_eocd), do: {:error, :invalid_archive}

  defp validate_eocd_entry_count(%{entries_on_disk: count, total_entries: count}) when count > @max_entries,
    do: {:error, :archive_too_many_entries}

  defp validate_eocd_entry_count(%{entries_on_disk: count, total_entries: count}), do: :ok
  defp validate_eocd_entry_count(_eocd), do: {:error, :invalid_archive}

  defp validate_central_directory_bounds(%{central_directory_size: size}) when size > @max_central_directory_bytes,
    do: {:error, :invalid_archive}

  defp validate_central_directory_bounds(%{
         offset: eocd_offset,
         central_directory_offset: directory_offset,
         central_directory_size: directory_size
       })
       when directory_offset + directory_size == eocd_offset, do: :ok

  defp validate_central_directory_bounds(_eocd), do: {:error, :invalid_archive}

  defp zip64_locator?(binary, eocd_offset) when eocd_offset >= 20 do
    binary_part(binary, eocd_offset - 20, 4) == <<0x50, 0x4B, 0x06, 0x07>>
  end

  defp zip64_locator?(_binary, _eocd_offset), do: false

  defp zip64_eocd_values?(eocd) do
    eocd.entries_on_disk == @zip64_sentinel_16 or
      eocd.total_entries == @zip64_sentinel_16 or
      eocd.central_directory_size == @zip64_sentinel_32 or
      eocd.central_directory_offset == @zip64_sentinel_32
  end

  defp validate_central_directory(_binary, %{total_entries: 0, central_directory_size: 0}), do: :ok

  defp validate_central_directory(binary, eocd) do
    directory =
      binary_part(binary, eocd.central_directory_offset, eocd.central_directory_size)

    validate_central_entries(
      directory,
      eocd.total_entries,
      binary,
      eocd.central_directory_offset
    )
  rescue
    ArgumentError -> {:error, :invalid_archive}
  end

  defp validate_central_entries(directory, 0, _archive, _central_directory_offset) do
    validate_central_directory_signature(directory)
  end

  defp validate_central_entries(
         <<0x50, 0x4B, 0x01, 0x02, _version_made_by::little-unsigned-integer-size(16),
           _version_needed::little-unsigned-integer-size(16), _flags::little-unsigned-integer-size(16),
           _compression_method::little-unsigned-integer-size(16), _modified_time::little-unsigned-integer-size(16),
           _modified_date::little-unsigned-integer-size(16), _crc32::little-unsigned-integer-size(32),
           compressed_size::little-unsigned-integer-size(32), uncompressed_size::little-unsigned-integer-size(32),
           name_length::little-unsigned-integer-size(16), extra_length::little-unsigned-integer-size(16),
           comment_length::little-unsigned-integer-size(16), disk_start::little-unsigned-integer-size(16),
           _internal_attrs::little-unsigned-integer-size(16), _external_attrs::little-unsigned-integer-size(32),
           local_header_offset::little-unsigned-integer-size(32), rest::binary>>,
         remaining_entries,
         archive,
         central_directory_offset
       )
       when remaining_entries > 0 do
    metadata = %{
      compressed_size: compressed_size,
      uncompressed_size: uncompressed_size,
      name_length: name_length,
      extra_length: extra_length,
      comment_length: comment_length,
      disk_start: disk_start,
      local_header_offset: local_header_offset
    }

    with :ok <- validate_central_metadata_lengths(metadata, rest),
         :ok <- validate_central_storage_fields(metadata),
         :ok <- validate_local_header_reference(metadata, archive, central_directory_offset),
         {:ok, extra, remaining} <- take_central_metadata(rest, metadata),
         :ok <- validate_extra_fields(extra) do
      validate_central_entries(
        remaining,
        remaining_entries - 1,
        archive,
        central_directory_offset
      )
    end
  end

  defp validate_central_entries(_directory, _remaining, _archive, _central_directory_offset),
    do: {:error, :invalid_archive}

  defp validate_central_directory_signature(<<>>), do: :ok

  defp validate_central_directory_signature(
         <<0x50, 0x4B, 0x05, 0x05, signature_size::little-unsigned-integer-size(16),
           _signature::binary-size(signature_size)>>
       ), do: :ok

  defp validate_central_directory_signature(_directory), do: {:error, :invalid_archive}

  defp validate_central_metadata_lengths(%{name_length: length}, _rest)
       when length == 0 or length > @max_zip_entry_name_bytes, do: {:error, :invalid_archive}

  defp validate_central_metadata_lengths(metadata, rest) do
    metadata_size = metadata.name_length + metadata.extra_length + metadata.comment_length

    if metadata_size <= byte_size(rest), do: :ok, else: {:error, :invalid_archive}
  end

  defp validate_central_storage_fields(%{compressed_size: @zip64_sentinel_32}), do: {:error, :invalid_archive}

  defp validate_central_storage_fields(%{uncompressed_size: @zip64_sentinel_32}), do: {:error, :invalid_archive}

  defp validate_central_storage_fields(%{local_header_offset: @zip64_sentinel_32}), do: {:error, :invalid_archive}

  defp validate_central_storage_fields(%{disk_start: @zip64_sentinel_16}), do: {:error, :invalid_archive}

  defp validate_central_storage_fields(%{disk_start: 0}), do: :ok
  defp validate_central_storage_fields(_metadata), do: {:error, :invalid_archive}

  defp validate_local_header_reference(metadata, archive, central_directory_offset) do
    if valid_local_header?(archive, metadata.local_header_offset, central_directory_offset),
      do: :ok,
      else: {:error, :invalid_archive}
  end

  defp take_central_metadata(rest, metadata) do
    <<_name::binary-size(metadata.name_length), extra::binary-size(metadata.extra_length),
      _comment::binary-size(metadata.comment_length), remaining::binary>> = rest

    {:ok, extra, remaining}
  end

  defp valid_local_header?(archive, offset, central_directory_offset) do
    offset + 30 <= central_directory_offset and
      binary_part(archive, offset, 4) == <<0x50, 0x4B, 0x03, 0x04>>
  rescue
    ArgumentError -> false
  end

  defp validate_extra_fields(<<>>), do: :ok

  defp validate_extra_fields(
         <<field_id::little-unsigned-integer-size(16), field_size::little-unsigned-integer-size(16), rest::binary>>
       )
       when field_size <= byte_size(rest) do
    <<_field::binary-size(field_size), remaining::binary>> = rest

    if field_id == 0x0001,
      do: {:error, :invalid_archive},
      else: validate_extra_fields(remaining)
  end

  defp validate_extra_fields(_extra), do: {:error, :invalid_archive}

  defp list_zip(binary) do
    case :zip.list_dir(binary) do
      {:ok, entries} -> {:ok, Enum.filter(entries, &match?({:zip_file, _, _, _, _, _}, &1))}
      {:error, _reason} -> {:error, :invalid_archive}
    end
  rescue
    _exception -> {:error, :invalid_archive}
  catch
    _kind, _reason -> {:error, :invalid_archive}
  end

  defp validate_entry_count(entries) when length(entries) <= @max_entries, do: :ok
  defp validate_entry_count(_entries), do: {:error, :archive_too_many_entries}

  defp validate_entries(entries) do
    entries
    |> Enum.reduce_while({:ok, [], MapSet.new(), 0}, &validate_entry/2)
    |> case do
      {:ok, selected, _names, _total} -> {:ok, Enum.reverse(selected)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_entry(entry, {:ok, acc, names, total}) do
    with {:ok, metadata} <- entry_metadata(entry),
         :ok <- validate_path(metadata.name),
         :ok <- validate_type(metadata.type),
         :ok <- validate_nested_archive(metadata.extension),
         :ok <- validate_entry_size(metadata.size),
         :ok <- validate_expansion_ratio(metadata.size, metadata.compressed_size),
         :ok <- validate_duplicate(metadata.name, names),
         :ok <- validate_total(total + metadata.size) do
      selected = maybe_select_entry(acc, metadata)
      names = MapSet.put(names, String.downcase(metadata.name))
      {:cont, {:ok, selected, names, total + metadata.size}}
    else
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp maybe_select_entry(acc, %{type: :regular, extension: extension} = metadata) do
    if MapSet.member?(@allowed_extensions, extension), do: [metadata | acc], else: acc
  end

  defp maybe_select_entry(acc, _metadata), do: acc

  defp entry_metadata({:zip_file, raw_name, info, _comment, _offset, compressed_size}) do
    with {:ok, name} <- zip_name(raw_name),
         true <- is_tuple(info) and tuple_size(info) >= 3 do
      {:ok,
       %{
         raw_name: raw_name,
         name: name,
         extension: name |> Path.extname() |> String.downcase(),
         size: elem(info, 1),
         type: elem(info, 2),
         compressed_size: compressed_size
       }}
    else
      _other -> {:error, :invalid_archive_entry}
    end
  end

  defp zip_name(raw_name) do
    case :unicode.characters_to_binary(raw_name) do
      name when is_binary(name) -> {:ok, name}
      _other -> {:error, :invalid_archive_path}
    end
  rescue
    _exception -> {:error, :invalid_archive_path}
  end

  defp validate_path(name) do
    segments = String.split(name, "/", trim: true)

    cond do
      name == "" -> {:error, :invalid_archive_path}
      String.contains?(name, [<<0>>, "\\"]) -> {:error, :invalid_archive_path}
      Path.type(name) != :relative -> {:error, :invalid_archive_path}
      Enum.any?(segments, &(&1 in [".", ".."])) -> {:error, :invalid_archive_path}
      true -> :ok
    end
  end

  defp validate_type(:regular), do: :ok
  defp validate_type(:directory), do: :ok
  defp validate_type(_type), do: {:error, :unsupported_archive_entry}

  defp validate_nested_archive(extension) do
    if MapSet.member?(@archive_extensions, extension),
      do: {:error, :nested_archive_not_allowed},
      else: :ok
  end

  defp validate_entry_size(size) when is_integer(size) and size >= 0 and size <= @max_entry_bytes, do: :ok
  defp validate_entry_size(_size), do: {:error, :archive_entry_too_large}

  defp validate_expansion_ratio(0, _compressed_size), do: :ok

  defp validate_expansion_ratio(size, compressed_size) when is_integer(compressed_size) and compressed_size > 0 do
    if size / compressed_size <= @max_expansion_ratio,
      do: :ok,
      else: {:error, :archive_expansion_ratio_exceeded}
  end

  defp validate_expansion_ratio(_size, _compressed_size), do: {:error, :invalid_archive_entry}

  defp validate_duplicate(name, names) do
    if MapSet.member?(names, String.downcase(name)),
      do: {:error, :duplicate_archive_entry},
      else: :ok
  end

  defp validate_total(total) when total <= @max_expanded_bytes, do: :ok
  defp validate_total(_total), do: {:error, :archive_too_large}

  defp extract_selected(_binary, []), do: {:ok, []}

  defp extract_selected(binary, selected) do
    names = Enum.map(selected, & &1.raw_name)

    case :zip.extract(binary, [:memory, :skip_directories, {:file_list, names}]) do
      {:ok, extracted} -> {:ok, extracted}
      {:error, _reason} -> {:error, :invalid_archive}
    end
  rescue
    _exception -> {:error, :invalid_archive}
  catch
    _kind, _reason -> {:error, :invalid_archive}
  end

  defp normalize_files(extracted) do
    extracted
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {{raw_name, content}, index}, {:ok, acc} ->
      with {:ok, name} <- zip_name(raw_name),
           {:ok, content} <- normalize_text(content) do
        file = %{
          alias: "source_#{index}",
          extension: name |> Path.extname() |> String.downcase(),
          content: content
        }

        {:cont, {:ok, [file | acc]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, files} -> {:ok, Enum.reverse(files)}
      error -> error
    end
  end

  defp normalize_text(binary) do
    binary =
      if String.starts_with?(binary, <<0xEF, 0xBB, 0xBF>>),
        do: binary_part(binary, 3, byte_size(binary) - 3),
        else: binary

    if String.valid?(binary) do
      {:ok, String.replace(binary, ["\r\n", "\r"], "\n")}
    else
      {:error, :invalid_text_encoding}
    end
  end

  defp require_yarn(files) do
    if Enum.any?(files, &(&1.extension == ".yarn")),
      do: :ok,
      else: {:error, :archive_missing_yarn_files}
  end
end
