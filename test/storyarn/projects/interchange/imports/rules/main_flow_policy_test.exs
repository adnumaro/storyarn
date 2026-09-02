defmodule Storyarn.Projects.Imports.MainFlowPolicyTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Imports.MainFlowPolicy

  describe "preview/3" do
    test "preserves an existing main unless overwrite replaces its shortcut" do
      flows = [flow("start", true), flow("current-main", false)]
      existing_main = %{shortcut: "current-main"}

      assert %{
               additive: %{
                 skip: "preserve_existing",
                 rename: "preserve_existing",
                 overwrite: "replace_existing"
               },
               replace_project: "import_candidate"
             } = MainFlowPolicy.preview(flows, existing_main, ["current-main"])
    end

    test "accounts for a skipped candidate when the target has no main" do
      assert %{additive: %{skip: "none", overwrite: "import_candidate", rename: "import_candidate"}} =
               MainFlowPolicy.preview([flow("start", true)], nil, ["start"])
    end

    test "imports a non-conflicting candidate with skip when the target has no main" do
      assert %{additive: %{skip: "import_candidate"}} =
               MainFlowPolicy.preview([flow("start", true)], nil, [])
    end

    test "preserves an existing main when overwrite does not replace its shortcut" do
      assert %{additive: %{overwrite: "preserve_existing"}} =
               MainFlowPolicy.preview(
                 [flow("start", true), flow("other", false)],
                 %{shortcut: "current-main"},
                 []
               )
    end

    test "does not invent a main flow without an adapter candidate" do
      assert %{
               additive: %{skip: "none", overwrite: "none", rename: "none"},
               replace_project: "none"
             } = MainFlowPolicy.preview([flow("prologue", false)], nil, [])
    end
  end

  describe "resolve/4" do
    test "accepts only the first nominated flow when no main exists" do
      state = MainFlowPolicy.initial_state(nil)
      {true, state} = MainFlowPolicy.resolve(flow("start", true), "start", :rename, state)
      {false, _state} = MainFlowPolicy.resolve(flow("other", true), "other", :rename, state)
    end

    test "preserves an existing main and transfers its role only on overwrite" do
      state = MainFlowPolicy.initial_state(%{shortcut: "main"})

      {false, state} = MainFlowPolicy.resolve(flow("start", true), "start", :rename, state)
      {false, state} = MainFlowPolicy.resolve(flow("other", true), "other", :overwrite, state)
      {true, state} = MainFlowPolicy.resolve(flow("main", false), "main", :overwrite, state)
      {false, _state} = MainFlowPolicy.resolve(flow("later", true), "later", :rename, state)
    end

    test "allows a surviving candidate for skip and overwrite when no main exists" do
      for strategy <- [:skip, :overwrite] do
        state = MainFlowPolicy.initial_state(nil)

        assert {true, %{main_claimed?: true}} =
                 MainFlowPolicy.resolve(flow("start", true), "start", strategy, state)
      end
    end
  end

  defp flow(shortcut, is_main), do: %{"shortcut" => shortcut, "is_main" => is_main}
end
