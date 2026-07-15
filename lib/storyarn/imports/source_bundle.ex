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
    with {:ok, entries} <- list_zip(binary),
         :ok <- validate_entry_count(entries),
         {:ok, selected} <- validate_entries(entries),
         {:ok, extracted} <- extract_selected(binary, selected),
         {:ok, files} <- normalize_files(extracted),
         :ok <- require_yarn(files) do
      {:ok, %__MODULE__{kind: :archive, files: files}}
    end
  end

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
