defmodule Storyarn.Projects.LifecycleFacadeTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Lifecycle

  test "exposes project naming through the lifecycle boundary" do
    assert Lifecycle.slugify_project_name("El Último Proyecto") == "el-ultimo-proyecto"
  end
end
