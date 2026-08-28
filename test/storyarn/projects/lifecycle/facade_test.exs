defmodule Storyarn.Projects.LifecycleFacadeTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Lifecycle

  test "exposes project naming through the lifecycle boundary" do
    assert Lifecycle.slugify_project_name("El Último Proyecto") == "el-ultimo-proyecto"
  end

  test "exposes source-language reference data without changing its shape" do
    assert Lifecycle.source_language_option("es", "Español") == %{
             flagCode: "es",
             label: "Español",
             languageTag: "es",
             shortLabel: "ES",
             value: "es"
           }
  end
end
