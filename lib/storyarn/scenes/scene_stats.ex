defmodule Storyarn.Scenes.SceneStats do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Localization.LocalizableWords
  alias Storyarn.Repo
  alias Storyarn.Scenes.{Scene, SceneConnection, ScenePin, SceneZone}

  # ===========================================================================
  # Stats
  # ===========================================================================

  @doc """
  Returns per-scene zone, pin, and connection counts in a single query.
  Returns `%{scene_id => %{zone_count, pin_count, connection_count}}`.
  """
  def scene_stats_for_project(project_id) do
    from(s in Scene,
      left_join: z in SceneZone,
      on: z.scene_id == s.id,
      left_join: p in ScenePin,
      on: p.scene_id == s.id,
      left_join: c in SceneConnection,
      on: c.scene_id == s.id,
      where: s.project_id == ^project_id and is_nil(s.deleted_at),
      group_by: s.id,
      select:
        {s.id,
         %{
           zone_count: count(z.id, :distinct),
           pin_count: count(p.id, :distinct),
           connection_count: count(c.id, :distinct)
         }}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Returns the count of scenes that have a background image.
  Returns an integer.
  """
  def scenes_with_background_count(project_id) do
    from(s in Scene,
      where:
        s.project_id == ^project_id and is_nil(s.deleted_at) and
          not is_nil(s.background_asset_id),
      select: count(s.id)
    )
    |> Repo.one()
  end

  @doc """
  Returns per-scene counts for all localizable words in each scene.
  """
  defdelegate scene_word_counts(project_id), to: LocalizableWords

  # ===========================================================================
  # Issue Detection
  # ===========================================================================

  @doc """
  Detects issues in scenes for a project.
  Returns `[%{issue_type, scene_id, scene_name, ...}]`.

  Issue types:
  - `:empty_scene` — scene has no zones or pins
  - `:no_background` — scene has no background image
  - `:missing_shortcut` — scene with nil/empty shortcut
  """
  def detect_scene_issues(project_id) do
    empty = detect_empty_scenes(project_id)
    no_bg = detect_no_background(project_id)
    missing = detect_missing_shortcuts(project_id)
    empty ++ no_bg ++ missing
  end

  defp detect_empty_scenes(project_id) do
    from(s in Scene,
      left_join: z in SceneZone,
      on: z.scene_id == s.id,
      left_join: p in ScenePin,
      on: p.scene_id == s.id,
      where: s.project_id == ^project_id and is_nil(s.deleted_at),
      group_by: [s.id, s.name],
      having: count(z.id) == 0 and count(p.id) == 0,
      select: %{issue_type: :empty_scene, scene_id: s.id, scene_name: s.name}
    )
    |> Repo.all()
  end

  defp detect_no_background(project_id) do
    from(s in Scene,
      where:
        s.project_id == ^project_id and is_nil(s.deleted_at) and
          is_nil(s.background_asset_id),
      select: %{issue_type: :no_background, scene_id: s.id, scene_name: s.name}
    )
    |> Repo.all()
  end

  defp detect_missing_shortcuts(project_id) do
    from(s in Scene,
      where:
        s.project_id == ^project_id and is_nil(s.deleted_at) and
          (is_nil(s.shortcut) or s.shortcut == ""),
      select: %{issue_type: :missing_shortcut, scene_id: s.id, scene_name: s.name}
    )
    |> Repo.all()
  end
end
