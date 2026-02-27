defmodule StoryarnWeb.Components.ConfigPopovers.ReferenceConfigTest do
  @moduledoc """
  Component tests for the reference config popover.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.Components.BlockComponents.ConfigPopovers.ReferenceConfig

  defp make_block(attrs \\ %{}) do
    Map.merge(
      %{
        id: 1,
        type: "reference",
        is_constant: false,
        scope: "self",
        required: false,
        variable_name: nil,
        inherited_from_block_id: nil,
        detached: false,
        config: %{"label" => "Link", "allowed_types" => ["sheet", "flow"]}
      },
      attrs
    )
  end

  describe "reference_config/1" do
    test "renders sheets and flows checkboxes" do
      html =
        render_component(&ReferenceConfig.reference_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ "Sheets"
      assert html =~ "Flows"
      assert html =~ "toggle_allowed_type"
    end

    test "both checked by default" do
      html =
        render_component(&ReferenceConfig.reference_config/1,
          block: make_block(),
          can_edit: true
        )

      # Both checkboxes should be checked
      assert html =~ "checked"
    end

    test "shows unchecked when type not in allowed_types" do
      html =
        render_component(&ReferenceConfig.reference_config/1,
          block: make_block(%{config: %{"label" => "Link", "allowed_types" => ["sheet"]}}),
          can_edit: true
        )

      # Only sheet checkbox should be checked, flow should not
      assert html =~ "Sheets"
      assert html =~ "Flows"
    end

    test "renders advanced section" do
      html =
        render_component(&ReferenceConfig.reference_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ "Advanced"
    end

    test "checkboxes have data-close-on-click=false" do
      html =
        render_component(&ReferenceConfig.reference_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ ~s(data-close-on-click="false")
    end

    test "inputs are disabled when can_edit is false" do
      html =
        render_component(&ReferenceConfig.reference_config/1,
          block: make_block(),
          can_edit: false
        )

      assert html =~ "disabled"
    end
  end
end
