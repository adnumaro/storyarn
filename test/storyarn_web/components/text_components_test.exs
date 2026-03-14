defmodule StoryarnWeb.Components.TextComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.HTML, only: [safe_to_string: 1]

  alias StoryarnWeb.Components.TextComponents

  test "joins the last two words with a non-breaking space" do
    assert safe_to_string(TextComponents.widont("Discover the product pillars")) ==
             "Discover the product\u00A0pillars"
  end

  test "returns a single word unchanged" do
    assert safe_to_string(TextComponents.widont("Storyarn")) == "Storyarn"
  end

  test "escapes HTML before inserting the non-breaking space" do
    assert safe_to_string(TextComponents.widont("Safe <b>tag</b> text")) ==
             "Safe &lt;b&gt;tag&lt;/b&gt;\u00A0text"
  end
end
