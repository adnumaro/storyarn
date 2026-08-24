defmodule Storyarn.Scenes.ShortcutGenerator do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Platform.Shared.MapUtils
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Scenes.TreeOperations

  def prepare_create(attrs, project_id, exclude_id) do
    if Map.has_key?(attrs, "shortcut") or attrs["name"] in [nil, ""] do
      attrs
    else
      Map.put(attrs, "shortcut", generate_scene(attrs["name"], project_id, exclude_id))
    end
  end

  def prepare_update(%Scene{} = scene, attrs) do
    attrs = MapUtils.stringify_keys(attrs)
    new_name = attrs["name"]

    cond do
      Map.has_key?(attrs, "shortcut") -> attrs
      renamed?(scene, new_name) -> Map.put(attrs, "shortcut", generate_scene(new_name, scene.project_id, scene.id))
      missing_shortcut?(scene) -> Map.put(attrs, "shortcut", generate_scene(scene.name, scene.project_id, scene.id))
      true -> attrs
    end
  end

  def assign_position(attrs, project_id, parent_id) do
    attrs = MapUtils.stringify_keys(attrs)

    if Map.has_key?(attrs, "position"),
      do: attrs,
      else: Map.put(attrs, "position", TreeOperations.next_position(project_id, parent_id))
  end

  def generate_scene(name, project_id, exclude_id \\ nil),
    do: generate(name, list_entity_shortcuts(Scene, project_id, exclude_id))

  def generate_pin(label, scene_id, exclude_id \\ nil),
    do: generate(label, list_element_shortcuts(ScenePin, scene_id, exclude_id))

  def generate_zone(name, scene_id, exclude_id \\ nil),
    do: generate(name, list_element_shortcuts(SceneZone, scene_id, exclude_id))

  defp renamed?(%Scene{name: current_name}, new_name),
    do: is_binary(new_name) and new_name != "" and new_name != current_name

  defp missing_shortcut?(%Scene{shortcut: shortcut}), do: shortcut in [nil, ""]

  defp list_entity_shortcuts(schema, project_id, exclude_id) do
    schema
    |> where([entity], entity.project_id == ^project_id and is_nil(entity.deleted_at))
    |> where([entity], not is_nil(entity.shortcut))
    |> maybe_exclude(exclude_id)
    |> select([entity], entity.shortcut)
    |> Repo.all()
  end

  defp list_element_shortcuts(schema, scene_id, exclude_id) do
    schema
    |> where([element], element.scene_id == ^scene_id and not is_nil(element.shortcut))
    |> maybe_exclude(exclude_id)
    |> select([element], element.shortcut)
    |> Repo.all()
  end

  defp maybe_exclude(query, nil), do: query
  defp maybe_exclude(query, id), do: where(query, [record], record.id != ^id)

  defp generate(name, existing) do
    base = shortcutify(name)

    cond do
      base == "" -> nil
      base not in existing -> base
      true -> find_unique_suffix(base, existing, 1)
    end
  end

  defp find_unique_suffix(base, existing, counter) do
    candidate = "#{base}-#{counter}"
    if candidate in existing, do: find_unique_suffix(base, existing, counter + 1), else: candidate
  end

  defp shortcutify(nil), do: ""
  defp shortcutify(""), do: ""

  defp shortcutify(name) do
    name
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\-.\s]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.replace(~r/\.+/, ".")
    |> String.replace(~r/^[-.]+|[-.]+$/, "")
  end
end
