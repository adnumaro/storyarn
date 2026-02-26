defmodule Storyarn.Exports.ExportOptionsTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Exports.ExportOptions

  # =============================================================================
  # new/1 — valid formats
  # =============================================================================

  describe "new/1 with valid formats" do
    test "creates options with default values" do
      {:ok, opts} = ExportOptions.new(%{format: :storyarn})

      assert opts.format == :storyarn
      assert opts.version == "1.0.0"
      assert opts.include_sheets == true
      assert opts.include_flows == true
      assert opts.include_scenes == true
      assert opts.include_screenplays == true
      assert opts.include_localization == true
      assert opts.include_assets == :references
      assert opts.languages == :all
      assert opts.flow_ids == :all
      assert opts.sheet_ids == :all
      assert opts.scene_ids == :all
      assert opts.validate_before_export == true
      assert opts.pretty_print == true
    end

    test "accepts all valid format atoms" do
      valid = ~w(storyarn ink yarn unity godot godot_dialogic unreal articy)a

      for format <- valid do
        assert {:ok, %ExportOptions{format: ^format}} = ExportOptions.new(%{format: format})
      end
    end

    test "accepts string format keys" do
      {:ok, opts} = ExportOptions.new(%{"format" => "ink"})
      assert opts.format == :ink
    end

    test "defaults format to storyarn when not provided" do
      {:ok, opts} = ExportOptions.new(%{})
      assert opts.format == :storyarn
    end
  end

  # =============================================================================
  # new/1 — invalid inputs
  # =============================================================================

  describe "new/1 with invalid inputs" do
    test "rejects invalid format atom" do
      assert {:error, {:invalid_format, :invalid_format}} =
               ExportOptions.new(%{format: :invalid_format})
    end

    test "rejects invalid format string that is not an existing atom" do
      # Strings that aren't existing atoms should be rejected
      assert {:error, {:invalid_format, "definitely_not_a_format_atom_xyz"}} =
               ExportOptions.new(%{format: "definitely_not_a_format_atom_xyz"})
    end

    test "rejects invalid asset mode" do
      assert {:error, {:invalid_asset_mode, :invalid_mode}} =
               ExportOptions.new(%{format: :storyarn, include_assets: :invalid_mode})
    end

    test "rejects invalid asset mode string that is not an existing atom" do
      assert {:error, {:invalid_asset_mode, "not_a_real_asset_mode_xyz"}} =
               ExportOptions.new(%{
                 "format" => "storyarn",
                 "include_assets" => "not_a_real_asset_mode_xyz"
               })
    end
  end

  # =============================================================================
  # new/1 — boolean coercion
  # =============================================================================

  describe "new/1 boolean coercion" do
    test "false values for include flags" do
      {:ok, opts} =
        ExportOptions.new(%{
          format: :storyarn,
          include_sheets: false,
          include_flows: false,
          include_scenes: false,
          include_screenplays: false,
          include_localization: false
        })

      assert opts.include_sheets == false
      assert opts.include_flows == false
      assert opts.include_scenes == false
      assert opts.include_screenplays == false
      assert opts.include_localization == false
    end

    test "truthy values are coerced to true" do
      {:ok, opts} =
        ExportOptions.new(%{
          format: :storyarn,
          include_sheets: "yes",
          validate_before_export: 1
        })

      assert opts.include_sheets == true
      assert opts.validate_before_export == true
    end

    test "nil values use default (true)" do
      {:ok, opts} =
        ExportOptions.new(%{
          format: :storyarn,
          include_sheets: nil
        })

      assert opts.include_sheets == true
    end

    test "string keys work for boolean flags" do
      {:ok, opts} =
        ExportOptions.new(%{
          "format" => "ink",
          "include_sheets" => false,
          "include_flows" => false,
          "validate_before_export" => false,
          "pretty_print" => false
        })

      assert opts.include_sheets == false
      assert opts.include_flows == false
      assert opts.validate_before_export == false
      assert opts.pretty_print == false
    end
  end

  # =============================================================================
  # new/1 — list and ID parsing
  # =============================================================================

  describe "new/1 list and ID parsing" do
    test "languages as list" do
      {:ok, opts} = ExportOptions.new(%{format: :storyarn, languages: ["en", "es"]})
      assert opts.languages == ["en", "es"]
    end

    test "languages as :all atom" do
      {:ok, opts} = ExportOptions.new(%{format: :storyarn, languages: :all})
      assert opts.languages == :all
    end

    test "languages as 'all' string" do
      {:ok, opts} = ExportOptions.new(%{format: :storyarn, languages: "all"})
      assert opts.languages == :all
    end

    test "languages nil defaults to :all" do
      {:ok, opts} = ExportOptions.new(%{format: :storyarn, languages: nil})
      assert opts.languages == :all
    end

    test "languages with non-list value defaults to :all" do
      {:ok, opts} = ExportOptions.new(%{format: :storyarn, languages: 42})
      assert opts.languages == :all
    end

    test "flow_ids as integer list" do
      {:ok, opts} = ExportOptions.new(%{format: :storyarn, flow_ids: [1, 2, 3]})
      assert opts.flow_ids == [1, 2, 3]
    end

    test "flow_ids as string integer list gets parsed" do
      {:ok, opts} = ExportOptions.new(%{format: :storyarn, flow_ids: ["1", "2", "3"]})
      assert opts.flow_ids == [1, 2, 3]
    end

    test "flow_ids as :all atom" do
      {:ok, opts} = ExportOptions.new(%{format: :storyarn, flow_ids: :all})
      assert opts.flow_ids == :all
    end

    test "flow_ids as 'all' string" do
      {:ok, opts} = ExportOptions.new(%{format: :storyarn, flow_ids: "all"})
      assert opts.flow_ids == :all
    end

    test "flow_ids nil defaults to :all" do
      {:ok, opts} = ExportOptions.new(%{format: :storyarn, flow_ids: nil})
      assert opts.flow_ids == :all
    end

    test "flow_ids with non-list value defaults to :all" do
      {:ok, opts} = ExportOptions.new(%{format: :storyarn, flow_ids: "something"})
      assert opts.flow_ids == :all
    end

    test "sheet_ids as list" do
      {:ok, opts} = ExportOptions.new(%{format: :storyarn, sheet_ids: [10, 20]})
      assert opts.sheet_ids == [10, 20]
    end

    test "scene_ids as list" do
      {:ok, opts} = ExportOptions.new(%{format: :storyarn, scene_ids: [5]})
      assert opts.scene_ids == [5]
    end

    test "string keys for IDs work" do
      {:ok, opts} =
        ExportOptions.new(%{
          "format" => "storyarn",
          "flow_ids" => ["1", "2"],
          "sheet_ids" => [3, 4]
        })

      assert opts.flow_ids == [1, 2]
      assert opts.sheet_ids == [3, 4]
    end
  end

  # =============================================================================
  # new/1 — version and asset mode
  # =============================================================================

  describe "new/1 version and asset mode" do
    test "custom version string" do
      {:ok, opts} = ExportOptions.new(%{format: :storyarn, version: "2.0.0"})
      assert opts.version == "2.0.0"
    end

    test "version from string key" do
      {:ok, opts} = ExportOptions.new(%{"format" => "storyarn", "version" => "3.0.0"})
      assert opts.version == "3.0.0"
    end

    test "asset mode embedded" do
      {:ok, opts} = ExportOptions.new(%{format: :storyarn, include_assets: :embedded})
      assert opts.include_assets == :embedded
    end

    test "asset mode bundled" do
      {:ok, opts} = ExportOptions.new(%{format: :storyarn, include_assets: :bundled})
      assert opts.include_assets == :bundled
    end

    test "asset mode from string key" do
      {:ok, opts} = ExportOptions.new(%{"format" => "ink", "include_assets" => "references"})
      assert opts.include_assets == :references
    end
  end

  # =============================================================================
  # valid_formats/0
  # =============================================================================

  describe "valid_formats/0" do
    test "returns list of atoms" do
      formats = ExportOptions.valid_formats()
      assert is_list(formats)
      assert :storyarn in formats
      assert :ink in formats
      assert :yarn in formats
      assert :unity in formats
      assert :godot in formats
      assert :unreal in formats
      assert :articy in formats
    end
  end

  # =============================================================================
  # include_section?/2
  # =============================================================================

  describe "include_section?/2" do
    test "sheets section" do
      {:ok, opts} = ExportOptions.new(%{format: :storyarn, include_sheets: true})
      assert ExportOptions.include_section?(opts, :sheets) == true

      {:ok, opts} = ExportOptions.new(%{format: :storyarn, include_sheets: false})
      assert ExportOptions.include_section?(opts, :sheets) == false
    end

    test "flows section" do
      {:ok, opts} = ExportOptions.new(%{format: :storyarn, include_flows: true})
      assert ExportOptions.include_section?(opts, :flows) == true

      {:ok, opts} = ExportOptions.new(%{format: :storyarn, include_flows: false})
      assert ExportOptions.include_section?(opts, :flows) == false
    end

    test "scenes section" do
      {:ok, opts} = ExportOptions.new(%{format: :storyarn, include_scenes: true})
      assert ExportOptions.include_section?(opts, :scenes) == true

      {:ok, opts} = ExportOptions.new(%{format: :storyarn, include_scenes: false})
      assert ExportOptions.include_section?(opts, :scenes) == false
    end

    test "screenplays section" do
      {:ok, opts} = ExportOptions.new(%{format: :storyarn, include_screenplays: true})
      assert ExportOptions.include_section?(opts, :screenplays) == true

      {:ok, opts} = ExportOptions.new(%{format: :storyarn, include_screenplays: false})
      assert ExportOptions.include_section?(opts, :screenplays) == false
    end

    test "localization section" do
      {:ok, opts} = ExportOptions.new(%{format: :storyarn, include_localization: true})
      assert ExportOptions.include_section?(opts, :localization) == true

      {:ok, opts} = ExportOptions.new(%{format: :storyarn, include_localization: false})
      assert ExportOptions.include_section?(opts, :localization) == false
    end

    test "assets section is true when mode is not false" do
      {:ok, opts} = ExportOptions.new(%{format: :storyarn, include_assets: :references})
      assert ExportOptions.include_section?(opts, :assets) == true

      {:ok, opts} = ExportOptions.new(%{format: :storyarn, include_assets: :embedded})
      assert ExportOptions.include_section?(opts, :assets) == true
    end

    test "unknown section returns false" do
      {:ok, opts} = ExportOptions.new(%{format: :storyarn})
      assert ExportOptions.include_section?(opts, :unknown) == false
      assert ExportOptions.include_section?(opts, :something_else) == false
    end
  end

  # =============================================================================
  # Atom coercion
  # =============================================================================

  describe "atom coercion" do
    test "string format that is an existing atom works" do
      {:ok, opts} = ExportOptions.new(%{format: "ink"})
      assert opts.format == :ink
    end

    test "atom format passes through" do
      {:ok, opts} = ExportOptions.new(%{format: :yarn})
      assert opts.format == :yarn
    end
  end
end
