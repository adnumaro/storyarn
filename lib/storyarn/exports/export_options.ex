defmodule Storyarn.Exports.ExportOptions do
  @moduledoc """
  Options struct for project export.

  Controls which format to export to, which sections to include,
  and filtering options for selective export.
  """

  @type t :: %__MODULE__{
          format: atom(),
          version: String.t(),
          include_sheets: boolean(),
          include_flows: boolean(),
          include_scenes: boolean(),
          include_screenplays: boolean(),
          include_localization: boolean(),
          include_assets: :references | :embedded | :bundled,
          languages: [String.t()] | :all,
          flow_ids: [integer()] | :all,
          sheet_ids: [integer()] | :all,
          scene_ids: [integer()] | :all,
          validate_before_export: boolean(),
          pretty_print: boolean()
        }

  alias Storyarn.Shared.MapUtils

  @enforce_keys [:format]
  defstruct format: :storyarn,
            version: "1.0.0",
            include_sheets: true,
            include_flows: true,
            include_scenes: true,
            include_screenplays: true,
            include_localization: true,
            include_assets: :references,
            languages: :all,
            flow_ids: :all,
            sheet_ids: :all,
            scene_ids: :all,
            validate_before_export: true,
            pretty_print: true

  @valid_formats ~w(storyarn ink yarn unity godot godot_dialogic unreal articy)a
  @valid_asset_modes ~w(references embedded bundled)a

  @doc """
  Create a new ExportOptions struct from a map of attributes.

  Returns `{:ok, options}` or `{:error, reason}`.

  ## Examples

      iex> ExportOptions.new(%{format: :storyarn})
      {:ok, %ExportOptions{format: :storyarn, ...}}

      iex> ExportOptions.new(%{format: :invalid})
      {:error, {:invalid_format, :invalid}}

  """
  def new(attrs) when is_map(attrs) do
    format = to_atom(attrs[:format] || attrs["format"] || :storyarn)

    with :ok <- validate_format(format),
         :ok <- validate_asset_mode(attrs) do
      opts = %__MODULE__{
        format: format,
        version: attrs[:version] || attrs["version"] || "1.0.0",
        include_sheets: get_bool(attrs, :include_sheets, true),
        include_flows: get_bool(attrs, :include_flows, true),
        include_scenes: get_bool(attrs, :include_scenes, true),
        include_screenplays: get_bool(attrs, :include_screenplays, true),
        include_localization: get_bool(attrs, :include_localization, true),
        include_assets: to_atom(attrs[:include_assets] || attrs["include_assets"] || :references),
        languages: get_list_or_all(attrs, :languages),
        flow_ids: get_ids_or_all(attrs, :flow_ids),
        sheet_ids: get_ids_or_all(attrs, :sheet_ids),
        scene_ids: get_ids_or_all(attrs, :scene_ids),
        validate_before_export: get_bool(attrs, :validate_before_export, true),
        pretty_print: get_bool(attrs, :pretty_print, true)
      }

      {:ok, opts}
    end
  end

  @doc """
  Returns the list of valid export format atoms.
  """
  def valid_formats, do: @valid_formats

  @doc """
  Check if a section should be included based on options.
  """
  def include_section?(%__MODULE__{} = opts, section) do
    case section do
      :sheets -> opts.include_sheets
      :flows -> opts.include_flows
      :scenes -> opts.include_scenes
      :screenplays -> opts.include_screenplays
      :localization -> opts.include_localization
      :assets -> opts.include_assets != false
      _ -> false
    end
  end

  defp validate_format(format) when format in @valid_formats, do: :ok
  defp validate_format(format), do: {:error, {:invalid_format, format}}

  defp validate_asset_mode(attrs) do
    mode = to_atom(attrs[:include_assets] || attrs["include_assets"] || :references)

    if mode in @valid_asset_modes do
      :ok
    else
      {:error, {:invalid_asset_mode, mode}}
    end
  end

  defp get_bool(attrs, key, default) do
    str_key = to_string(key)
    val = attrs[key]
    val = if is_nil(val), do: attrs[str_key], else: val
    if is_nil(val), do: default, else: !!val
  end

  defp get_list_or_all(attrs, key) do
    str_key = to_string(key)
    val = attrs[key] || attrs[str_key]

    case val do
      :all -> :all
      "all" -> :all
      nil -> :all
      list when is_list(list) -> list
      _ -> :all
    end
  end

  defp get_ids_or_all(attrs, key) do
    str_key = to_string(key)
    val = attrs[key] || attrs[str_key]

    case val do
      :all -> :all
      "all" -> :all
      nil -> :all
      list when is_list(list) -> Enum.map(list, &MapUtils.parse_int/1)
      _ -> :all
    end
  end

  defp to_atom(val) when is_atom(val), do: val

  defp to_atom(val) when is_binary(val) do
    String.to_existing_atom(val)
  rescue
    ArgumentError -> val
  end
end
