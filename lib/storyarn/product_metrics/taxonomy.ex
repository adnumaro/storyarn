defmodule Storyarn.ProductMetrics.Taxonomy do
  @moduledoc """
  Stable product metric options collected during project creation.
  """

  @project_types ["game", "film", "novel", "other"]

  @project_subtypes %{
    "game" => [
      "crpg",
      "rpg",
      "jrpg",
      "point_click_adventure",
      "visual_novel",
      "interactive_fiction",
      "narrative_adventure",
      "tabletop_rpg",
      "other"
    ],
    "film" => [
      "feature_film",
      "short_film",
      "series_tv",
      "documentary",
      "animation",
      "commercial_branded",
      "other"
    ],
    "novel" => [
      "choose_your_own_adventure",
      "interactive_novel",
      "fantasy",
      "science_fiction",
      "historical",
      "biographical",
      "mystery_thriller",
      "romance",
      "literary_fiction",
      "other"
    ],
    "other" => []
  }

  def project_types, do: @project_types
  def project_subtypes, do: @project_subtypes
  def project_subtypes(project_type), do: Map.get(@project_subtypes, project_type, [])

  def project_options do
    %{
      project_types: project_types(),
      project_subtypes: project_subtypes()
    }
  end

  def known_project_type?(project_type), do: project_type in @project_types

  def known_project_subtype?(project_type, project_subtype) do
    project_subtype in project_subtypes(project_type)
  end
end
