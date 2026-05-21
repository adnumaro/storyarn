defmodule StoryarnWeb.Components.CoreComponentsTest do
  @moduledoc """
  Tests for CoreComponents global LiveView JS helpers.
  """

  use StoryarnWeb.ConnCase, async: true

  alias Phoenix.LiveView.JS
  alias StoryarnWeb.Components.CoreComponents

  describe "show/2" do
    test "returns JS struct" do
      result = CoreComponents.show("#my-element")
      assert %JS{} = result
    end

    test "accepts JS struct as first argument" do
      result = CoreComponents.show(%JS{}, "#my-element")
      assert %JS{} = result
    end
  end

  describe "hide/2" do
    test "returns JS struct" do
      result = CoreComponents.hide("#my-element")
      assert %JS{} = result
    end

    test "accepts JS struct as first argument" do
      result = CoreComponents.hide(%JS{}, "#my-element")
      assert %JS{} = result
    end
  end
end
