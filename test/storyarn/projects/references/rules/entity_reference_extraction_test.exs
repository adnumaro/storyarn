defmodule Storyarn.Projects.References.EntityReferenceExtractionTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.References.EntityReferenceExtraction

  describe "extract_block_value_references/2" do
    test "preserves encoded reference IDs and accepts atom-keyed legacy values" do
      assert {:ok, [%{type: "sheet", id: "0042", context: "value"}]} =
               EntityReferenceExtraction.extract_block_value_references("reference", %{
                 target_type: :sheet,
                 target_id: "0042"
               })
    end

    test "prefers canonical string keys when legacy atom keys coexist" do
      assert {:ok, [%{type: "flow", id: "22", context: "value"}]} =
               EntityReferenceExtraction.extract_block_value_references("reference", %{
                 "target_type" => "flow",
                 "target_id" => "22",
                 target_type: :sheet,
                 target_id: "11"
               })
    end

    test "keeps absent and unrelated reference surfaces empty" do
      assert {:ok, []} =
               EntityReferenceExtraction.extract_block_value_references("reference", %{
                 "target_type" => nil,
                 "target_id" => ""
               })

      assert {:ok, []} = EntityReferenceExtraction.extract_block_value_references("text", nil)
    end

    test "rejects non-map values for supported block types with the original diagnostics" do
      assert {:error, {:invalid_project_reference, {:block, :value, "reference"}, []}} =
               EntityReferenceExtraction.extract_block_value_references("reference", [])

      assert {:error, {:invalid_project_reference, {:block, :value, "rich_text"}, nil}} =
               EntityReferenceExtraction.extract_block_value_references("rich_text", nil)
    end

    test "preserves rich-text mention order and contexts" do
      content =
        ~s(<p><span class="mention" data-type="sheet" data-id="10">Sheet</span><span class="mention" data-type="flow" data-id="20">Flow</span></p>)

      assert {:ok,
              [
                %{type: "sheet", id: "10", context: "content"},
                %{type: "flow", id: "20", context: "content"}
              ]} =
               EntityReferenceExtraction.extract_block_value_references("rich_text", %{
                 "content" => content
               })
    end

    test "retains exact malformed reference diagnostics" do
      assert {:error, {:invalid_project_reference, {:block, :value, "scene"}, 80}} =
               EntityReferenceExtraction.extract_block_value_references("reference", %{
                 "target_type" => "scene",
                 "target_id" => 80
               })

      too_large = 9_223_372_036_854_775_808

      assert {:error, {:invalid_project_reference, {:block, :value, "sheet"}, ^too_large}} =
               EntityReferenceExtraction.extract_block_value_references("reference", %{
                 "target_type" => "sheet",
                 "target_id" => too_large
               })
    end

    test "accepts the maximum PostgreSQL bigint while preserving its encoded form" do
      max_pg_bigint = "9223372036854775807"

      assert {:ok, [%{type: "sheet", id: ^max_pg_bigint, context: "value"}]} =
               EntityReferenceExtraction.extract_block_value_references("reference", %{
                 "target_type" => "sheet",
                 "target_id" => max_pg_bigint
               })
    end

    test "retains exact invalid rich-text diagnostic shapes" do
      assert {:error, {:invalid_project_reference, {:block, :content, :invalid_html}, 42}} =
               EntityReferenceExtraction.extract_block_value_references("rich_text", %{
                 "content" => 42
               })

      blank_id = ~s(<span class="mention" data-type="sheet" data-id=" ">Blank</span>)

      assert {:error, {:invalid_project_reference, {:block, :content, "sheet"}, " "}} =
               EntityReferenceExtraction.extract_block_value_references("rich_text", %{
                 "content" => blank_id
               })

      duplicate_type =
        ~s(<span class="mention" data-type="sheet" data-type="flow" data-id="42">Duplicate</span>)

      assert {:error,
              {:invalid_project_reference, {:block, :content, :malformed_mention}, %{type: ["sheet", "flow"], id: ["42"]}}} =
               EntityReferenceExtraction.extract_block_value_references("rich_text", %{
                 "content" => duplicate_type
               })
    end
  end
end
