defmodule Storyarn.Platform.ProductMetricsTaxonomyTest do
  use ExUnit.Case, async: true

  alias Storyarn.Platform

  test "exposes the stable project metric taxonomy through the Platform facade" do
    assert Platform.product_metric_project_types() == ["game", "film", "novel", "other"]

    assert %{
             project_types: ["game", "film", "novel", "other"],
             project_subtypes: %{
               "film" => film_subtypes,
               "game" => game_subtypes,
               "novel" => novel_subtypes,
               "other" => []
             }
           } = Platform.product_metric_project_options()

    assert "rpg" in game_subtypes
    assert "feature_film" in film_subtypes
    assert "fantasy" in novel_subtypes
  end

  test "validates subtype membership without accepting unknown categories" do
    assert Platform.known_product_metric_project_subtype?("game", "rpg")
    refute Platform.known_product_metric_project_subtype?("game", "feature_film")
    refute Platform.known_product_metric_project_subtype?("unknown", "rpg")
  end
end
