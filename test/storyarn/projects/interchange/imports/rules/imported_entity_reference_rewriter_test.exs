defmodule Storyarn.Projects.Imports.ImportedEntityReferenceRewriterTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Imports.ImportedEntityReferenceRewriter

  describe "validate/1 scene zones" do
    test "rejects non-list zone collections with a stable error" do
      for invalid_zones <- [%{}, "invalid", 17, true] do
        data = %{"scenes" => [%{"zones" => invalid_zones}]}

        assert {:error, :import_reference_contract_mismatch} =
                 ImportedEntityReferenceRewriter.validate(data)
      end
    end

    test "rejects non-map entries inside a zone collection with a stable error" do
      for invalid_zone <- [nil, "invalid", [], 17] do
        data = %{"scenes" => [%{"zones" => [%{}, invalid_zone]}]}

        assert {:error, :import_reference_contract_mismatch} =
                 ImportedEntityReferenceRewriter.validate(data)
      end
    end

    test "accepts absent, null, empty, and map-only zone collections" do
      for scene <- [%{}, %{"zones" => nil}, %{"zones" => []}, %{"zones" => [%{}]}] do
        assert :ok = ImportedEntityReferenceRewriter.validate(%{"scenes" => [scene]})
      end
    end
  end
end
