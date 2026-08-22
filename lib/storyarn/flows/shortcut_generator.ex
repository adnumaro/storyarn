defmodule Storyarn.Flows.ShortcutGenerator do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.TreeOperations
  alias Storyarn.Repo
  alias Storyarn.Shared.MapUtils

  @spec prepare_create(map(), pos_integer(), pos_integer() | nil) :: map()
  def prepare_create(attrs, project_id, exclude_id) do
    if Map.has_key?(attrs, "shortcut") or attrs["name"] in [nil, ""] do
      attrs
    else
      Map.put(attrs, "shortcut", generate(attrs["name"], project_id, exclude_id))
    end
  end

  @spec prepare_update(Flow.t(), map(), boolean() | (-> boolean())) :: map()
  def prepare_update(%Flow{} = flow, attrs, referenced?) do
    attrs = MapUtils.stringify_keys(attrs)
    new_name = attrs["name"]

    cond do
      Map.has_key?(attrs, "shortcut") ->
        attrs

      renamed?(flow, new_name) ->
        Map.put(attrs, "shortcut", shortcut_after_rename(flow, new_name, referenced?))

      missing_shortcut?(flow) ->
        Map.put(attrs, "shortcut", generate(flow.name, flow.project_id, flow.id))

      true ->
        attrs
    end
  end

  defp renamed?(%Flow{name: current_name}, new_name),
    do: is_binary(new_name) and new_name != "" and new_name != current_name

  defp missing_shortcut?(%Flow{shortcut: shortcut, name: name}),
    do: shortcut in [nil, ""] and is_binary(name) and name != ""

  defp shortcut_after_rename(%Flow{shortcut: shortcut} = flow, new_name, referenced?) do
    cond do
      shortcut in [nil, ""] -> generate(new_name, flow.project_id, flow.id)
      referenced?(referenced?) -> shortcut
      true -> generate(new_name, flow.project_id, flow.id)
    end
  end

  @spec assign_position(map(), pos_integer(), pos_integer() | nil) :: map()
  def assign_position(attrs, project_id, parent_id) do
    attrs = MapUtils.stringify_keys(attrs)

    if Map.has_key?(attrs, "position") do
      attrs
    else
      Map.put(attrs, "position", TreeOperations.next_position(project_id, parent_id))
    end
  end

  @spec generate(String.t(), integer(), integer() | nil) :: String.t() | nil
  def generate(name, project_id, exclude_id \\ nil) do
    base = shortcutify(name)

    if base == "" do
      nil
    else
      find_unique(base, list_shortcuts(project_id, exclude_id))
    end
  end

  defp list_shortcuts(project_id, exclude_id) do
    query =
      from flow in Flow,
        where:
          flow.project_id == ^project_id and is_nil(flow.deleted_at) and
            not is_nil(flow.shortcut),
        select: flow.shortcut

    query =
      if exclude_id,
        do: where(query, [flow], flow.id != ^exclude_id),
        else: query

    Repo.all(query)
  end

  defp find_unique(base, existing) do
    if base in existing,
      do: find_unique_suffix(base, existing, 1),
      else: base
  end

  defp find_unique_suffix(base, existing, counter) do
    candidate = "#{base}-#{counter}"

    if candidate in existing,
      do: find_unique_suffix(base, existing, counter + 1),
      else: candidate
  end

  defp referenced?(check) when is_function(check, 0), do: check.()
  defp referenced?(value), do: value == true

  # Flow shortcut normalization is duplicated deliberately. Its compatibility
  # is a Flow-domain contract and must not change when another tool adjusts its
  # identifier rules.
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
