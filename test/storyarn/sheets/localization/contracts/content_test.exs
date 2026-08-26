defmodule Storyarn.Sheets.Localization.Contracts.ContentTest do
  use ExUnit.Case, async: true

  alias Storyarn.Sheets.Localization

  test "the runtime contract includes only exported text variables" do
    assert Localization.localizable_block_types() == ["text", "rich_text"]

    assert Localization.localizable_block?(%{
             type: "rich_text",
             is_constant: false,
             variable_name: "biography",
             deleted_at: nil
           })

    refute Localization.localizable_block?(%{
             type: "text",
             is_constant: true,
             variable_name: "editor_note",
             deleted_at: nil
           })

    refute Localization.localizable_block?(%{
             type: "text",
             is_constant: false,
             variable_name: "  ",
             deleted_at: nil
           })

    refute Localization.localizable_block?(%{
             type: "select",
             is_constant: false,
             variable_name: "class",
             deleted_at: nil
           })
  end

  test "Sheet-owned word counting supports both public and persisted value shapes" do
    assert Localization.word_count_for_block("rich_text", %{content: "<p>One two</p>"}) == 2
    assert Localization.word_count_for_block("text", %{"content" => "Three words here"}) == 3
    assert Localization.word_count_for_block("number", %{"content" => "Ignored"}) == 0
  end
end
