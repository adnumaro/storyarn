defmodule Storyarn.Shared.WordCountTest do
  use ExUnit.Case, async: true

  alias Storyarn.Shared.WordCount

  describe "for_block_value/1" do
    test "counts atom-keyed rich text content" do
      assert WordCount.for_block_value(%{content: "<p>Runtime text value</p>"}) == 3
    end
  end

  describe "for_block/2" do
    test "counts string-keyed persisted block values" do
      assert WordCount.for_block("rich_text", %{"content" => "<p>Persisted text value</p>"}) == 3
      assert WordCount.for_block("number", %{"content" => "Ignored text"}) == 0
    end
  end
end
