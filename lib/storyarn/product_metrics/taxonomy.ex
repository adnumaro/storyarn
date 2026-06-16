defmodule Storyarn.ProductMetrics.Taxonomy do
  @moduledoc """
  Stable product metric options collected during access requests and project creation.
  """

  @professions [
    "narrative_designer",
    "game_designer",
    "writer",
    "screenwriter",
    "developer",
    "producer",
    "student",
    "other"
  ]

  @primary_interests [
    "game_narrative",
    "interactive_fiction",
    "worldbuilding",
    "screenplay_film",
    "novel_writing",
    "team_collaboration",
    "other"
  ]

  @discovery_sources [
    "search",
    "x_twitter",
    "reddit",
    "discord",
    "youtube",
    "friend_colleague",
    "article_blog",
    "other"
  ]

  @current_tools [
    "none",
    "articy_draft",
    "arcweave",
    "twine",
    "notion",
    "miro_figjam",
    "final_draft_celtx",
    "other"
  ]

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

  def professions, do: @professions
  def primary_interests, do: @primary_interests
  def discovery_sources, do: @discovery_sources
  def current_tools, do: @current_tools
  def project_types, do: @project_types
  def project_subtypes, do: @project_subtypes
  def project_subtypes(project_type), do: Map.get(@project_subtypes, project_type, [])

  def waitlist_options do
    %{
      professions: professions(),
      primary_interests: primary_interests(),
      discovery_sources: discovery_sources(),
      current_tools: current_tools()
    }
  end

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
