defmodule Storyarn.TestSelectionTest do
  use ExUnit.Case, async: true

  alias Storyarn.MixProject

  test "E2E tag selectors accept both bare tags and ExUnit's string-valued true" do
    assert ExUnit.Filters.parse(["e2e:true"]) == [{:e2e, "true"}]

    for option <- ["--include", "--only"], tag <- ["e2e", "e2e:true"] do
      assert MixProject.e2e_tests_requested?([option, tag])
    end

    refute MixProject.e2e_tests_requested?(["--include", "e2e:false"])
  end

  test "E2E file locations activate browser mode without requiring an E2E tag option" do
    for path <- [
          "test/e2e/blog_test.exs:16",
          "./test/e2e/blog_test.exs:16:30",
          Path.expand("test/e2e/blog_test.exs") <> ":16"
        ] do
      assert MixProject.e2e_tests_requested?([path, "--seed", "7", "--trace"])
    end

    assert MixProject.e2e_tests_requested?([
             "--include",
             "location:test/e2e/blog_test.exs:16"
           ])

    assert MixProject.e2e_tests_requested?([
             "test/e2e/blog_test.exs",
             "test/mix/test_runtime_config_test.exs:17"
           ])

    assert MixProject.e2e_tests_requested?([
             "test/e2e/blog_test.exs",
             "--include",
             "line:16"
           ])
  end

  test "line filters activate browser mode when a search directory contains E2E tests" do
    for option <- ["--include", "--only"],
        path <- ["test", ".", Path.expand("test"), Path.expand("."), "test/e2e"] do
      assert MixProject.e2e_tests_requested?([path, option, "line:16"])
    end

    for option <- ["--include", "--only"],
        path <- ["test/mix", "test/storyarn", "test/mix/test_runtime_config_test.exs"] do
      refute MixProject.e2e_tests_requested?([path, option, "line:16"])
    end

    refute MixProject.e2e_tests_requested?(["--include", "location:test:16"])
    refute MixProject.e2e_tests_requested?(["--include", "location:.:16"])
  end

  test "ordinary selections and bare E2E paths keep default E2E exclusions" do
    for args <- [
          [],
          ["--seed", "7", "--warnings-as-errors"],
          ["test"],
          ["test/e2e"],
          ["test/e2e/blog_test.exs"],
          ["test/mix/test_runtime_config_test.exs:17"],
          ["test/e2e_other/blog_test.exs:16"],
          ["test/e2e/../mix/test_runtime_config_test.exs:17"],
          ["--only", "ysc_validation"]
        ] do
      refute MixProject.e2e_tests_requested?(args), inspect(args)
    end
  end
end
