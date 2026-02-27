defmodule StoryarnWeb.Components.ConfigPopovers.DateConfigTest do
  @moduledoc """
  Component tests for the date config popover.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.Components.BlockComponents.ConfigPopovers.DateConfig

  defp make_block(attrs \\ %{}) do
    Map.merge(
      %{
        id: 1,
        type: "date",
        is_constant: false,
        scope: "self",
        required: false,
        variable_name: "birthday",
        inherited_from_block_id: nil,
        detached: false,
        config: %{"label" => "Birthday", "min_date" => "2000-01-01", "max_date" => "2030-12-31"}
      },
      attrs
    )
  end

  describe "date_config/1" do
    test "renders min_date and max_date inputs with values" do
      html =
        render_component(&DateConfig.date_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ ~s(value="2000-01-01")
      assert html =~ ~s(value="2030-12-31")
      assert html =~ "min_date"
      assert html =~ "max_date"
    end

    test "renders empty when dates are nil" do
      html =
        render_component(&DateConfig.date_config/1,
          block: make_block(%{config: %{"label" => "Birthday"}}),
          can_edit: true
        )

      assert html =~ "min_date"
      assert html =~ "max_date"
      refute html =~ ~s(value="2000)
    end

    test "does not render advanced section (moved to toolbar)" do
      html =
        render_component(&DateConfig.date_config/1,
          block: make_block(),
          can_edit: true
        )

      refute html =~ "Advanced"
      refute html =~ "change_block_scope"
    end

    test "data-blur-event attributes are correct" do
      html =
        render_component(&DateConfig.date_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ ~s(data-blur-event="save_config_field")
      assert html =~ "block_id"
    end

    test "inputs are disabled when can_edit is false" do
      html =
        render_component(&DateConfig.date_config/1,
          block: make_block(),
          can_edit: false
        )

      assert html =~ "disabled"
    end
  end
end
