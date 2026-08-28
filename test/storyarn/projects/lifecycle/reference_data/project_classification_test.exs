defmodule Storyarn.Projects.ProjectClassificationTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects
  alias Storyarn.Projects.ProjectClassification

  test "owns the stable classification used to validate and render projects" do
    assert ProjectClassification.project_types() == ["game", "film", "novel", "other"]

    assert %{
             project_types: ["game", "film", "novel", "other"],
             project_subtypes: %{
               "film" => film_subtypes,
               "game" => game_subtypes,
               "novel" => novel_subtypes,
               "other" => []
             }
           } = Projects.project_classification_options()

    assert "rpg" in game_subtypes
    assert "feature_film" in film_subtypes
    assert "fantasy" in novel_subtypes
  end

  test "rejects subtype membership from a different project classification" do
    assert ProjectClassification.known_project_subtype?("game", "rpg")
    refute ProjectClassification.known_project_subtype?("game", "feature_film")
    refute ProjectClassification.known_project_subtype?("unknown", "rpg")
  end
end
