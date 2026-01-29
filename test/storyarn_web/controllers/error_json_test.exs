defmodule StoryarnWeb.ErrorJSONTest do
  use StoryarnWeb.ConnCase, async: true

  test "renders 404" do
    assert StoryarnWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert StoryarnWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
