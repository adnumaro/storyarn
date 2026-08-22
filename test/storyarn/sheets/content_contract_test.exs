defmodule Storyarn.Sheets.ContentContractTest do
  use ExUnit.Case, async: true

  alias Storyarn.Sheets
  alias Storyarn.Sheets.ContentContract

  test "the runtime contract includes only exported text variables" do
    assert Sheets.localizable_block_types() == ["text", "rich_text"]

    assert ContentContract.localizable_block?(%{
             type: "rich_text",
             is_constant: false,
             variable_name: "biography",
             deleted_at: nil
           })

    refute ContentContract.localizable_block?(%{
             type: "text",
             is_constant: true,
             variable_name: "editor_note",
             deleted_at: nil
           })

    refute ContentContract.localizable_block?(%{
             type: "text",
             is_constant: false,
             variable_name: "  ",
             deleted_at: nil
           })

    refute ContentContract.localizable_block?(%{
             type: "select",
             is_constant: false,
             variable_name: "class",
             deleted_at: nil
           })
  end

  test "Sheet-owned word counting supports both public and persisted value shapes" do
    assert Sheets.block_word_count("rich_text", %{content: "<p>One two</p>"}) == 2
    assert Sheets.block_word_count("text", %{"content" => "Three words here"}) == 3
    assert Sheets.block_word_count("number", %{"content" => "Ignored"}) == 0
  end
end
