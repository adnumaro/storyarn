defmodule Storyarn.Sheets.ShortcutGenerator do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Repo
  alias Storyarn.Shared.MapUtils
  alias Storyarn.Sheets.Naming
  alias Storyarn.Sheets.ReferenceTracker
  alias Storyarn.Sheets.Sheet

  def prepare_create(attrs, project_id, exclude_id) do
    if Map.has_key?(attrs, "shortcut") or attrs["name"] in [nil, ""] do
      attrs
    else
      Map.put(attrs, "shortcut", generate_sheet(attrs["name"], project_id, exclude_id))
    end
  end

  def prepare_update(%Sheet{} = sheet, attrs) do
    attrs = MapUtils.stringify_keys(attrs)

    cond do
      Map.has_key?(attrs, "shortcut") ->
        attrs

      renamed?(sheet, attrs["name"]) ->
        regenerate_with_backlink_check(sheet, attrs)

      missing_shortcut?(sheet) ->
        generate_from_current_name(sheet, attrs)

      true ->
        attrs
    end
  end

  def generate_sheet(name, project_id, exclude_id \\ nil) do
    base = Naming.shortcutify(name)

    if base == "" do
      nil
    else
      find_unique(base, list_sheet_shortcuts(project_id, exclude_id))
    end
  end

  # A renamed sheet that other entities reference keeps its shortcut so the
  # references stay valid; unreferenced sheets regenerate from the new name.
  defp regenerate_with_backlink_check(sheet, attrs) do
    referenced? = ReferenceTracker.count_backlinks("sheet", sheet.id) > 0

    shortcut = Naming.maybe_regenerate(sheet.shortcut, attrs["name"], referenced?, &Naming.shortcutify/1)

    shortcut =
      if shortcut == sheet.shortcut do
        shortcut
      else
        generate_sheet(attrs["name"], sheet.project_id, sheet.id)
      end

    Map.put(attrs, "shortcut", shortcut)
  end

  defp generate_from_current_name(%Sheet{name: name} = sheet, attrs) do
    if name && name != "" do
      Map.put(attrs, "shortcut", generate_sheet(name, sheet.project_id, sheet.id))
    else
      attrs
    end
  end

  defp renamed?(%Sheet{name: current_name}, new_name),
    do: is_binary(new_name) and new_name != "" and new_name != current_name

  defp missing_shortcut?(%Sheet{shortcut: shortcut}), do: shortcut in [nil, ""]

  defp list_sheet_shortcuts(project_id, exclude_id) do
    Sheet
    |> where([sheet], sheet.project_id == ^project_id and is_nil(sheet.deleted_at))
    |> where([sheet], not is_nil(sheet.shortcut))
    |> maybe_exclude(exclude_id)
    |> select([sheet], sheet.shortcut)
    |> Repo.all()
  end

  defp maybe_exclude(query, nil), do: query
  defp maybe_exclude(query, id), do: where(query, [sheet], sheet.id != ^id)

  defp find_unique(base, existing) do
    if base in existing, do: find_unique_suffix(base, existing, 1), else: base
  end

  defp find_unique_suffix(base, existing, counter) do
    candidate = "#{base}-#{counter}"
    if candidate in existing, do: find_unique_suffix(base, existing, counter + 1), else: candidate
  end
end
