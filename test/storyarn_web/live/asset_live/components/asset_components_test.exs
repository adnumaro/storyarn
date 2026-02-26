defmodule StoryarnWeb.AssetLive.Components.AssetComponentsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Storyarn.Assets.Asset
  alias StoryarnWeb.AssetLive.Components.AssetComponents

  describe "format_size/1" do
    test "returns empty string for nil" do
      assert AssetComponents.format_size(nil) == ""
    end

    test "formats bytes" do
      assert AssetComponents.format_size(500) == "500 B"
    end

    test "formats kilobytes" do
      assert AssetComponents.format_size(2_048) == "2.0 KB"
    end

    test "formats megabytes" do
      assert AssetComponents.format_size(2_097_152) == "2.0 MB"
    end
  end

  describe "type_label/1" do
    test "returns Image for image assets" do
      asset = %Asset{content_type: "image/png"}
      assert AssetComponents.type_label(asset) =~ "Image"
    end

    test "returns Audio for audio assets" do
      asset = %Asset{content_type: "audio/mpeg"}
      assert AssetComponents.type_label(asset) =~ "Audio"
    end

    test "returns File for other content types" do
      asset = %Asset{content_type: "application/pdf"}
      assert AssetComponents.type_label(asset) =~ "File"
    end
  end

  describe "type_badge_class/1" do
    test "returns badge-primary for images" do
      asset = %Asset{content_type: "image/jpeg"}
      assert AssetComponents.type_badge_class(asset) == "badge-primary"
    end

    test "returns badge-secondary for audio" do
      asset = %Asset{content_type: "audio/wav"}
      assert AssetComponents.type_badge_class(asset) == "badge-secondary"
    end

    test "returns badge-ghost for other types" do
      asset = %Asset{content_type: "application/pdf"}
      assert AssetComponents.type_badge_class(asset) == "badge-ghost"
    end
  end

  describe "asset_card/1" do
    test "renders file icon for non-image non-audio assets" do
      asset = %Asset{
        id: 1,
        filename: "document.pdf",
        content_type: "application/pdf",
        size: 1024,
        url: "/test/doc.pdf"
      }

      html = render_component(&AssetComponents.asset_card/1, asset: asset, selected: false)

      assert html =~ "document.pdf"
      assert html =~ "file"
    end

    test "renders image for image assets" do
      asset = %Asset{
        id: 1,
        filename: "photo.png",
        content_type: "image/png",
        size: 2048,
        url: "/test/photo.png"
      }

      html = render_component(&AssetComponents.asset_card/1, asset: asset, selected: false)

      assert html =~ "photo.png"
      assert html =~ "/test/photo.png"
    end
  end

  describe "detail_panel/1" do
    test "renders file icon for non-image non-audio assets in detail panel" do
      asset = %Asset{
        id: 1,
        filename: "report.pdf",
        content_type: "application/pdf",
        size: 5_000,
        url: "/test/report.pdf",
        inserted_at: ~U[2025-01-15 10:00:00Z]
      }

      usages = %{flow_nodes: [], sheet_avatars: [], sheet_banners: []}

      html =
        render_component(&AssetComponents.detail_panel/1,
          asset: asset,
          usages: usages,
          workspace: %{slug: "ws"},
          project: %{slug: "proj"},
          can_edit: false
        )

      assert html =~ "report.pdf"
      assert html =~ "application/pdf"
      # Renders file icon for non-image, non-audio
      assert html =~ "file"
    end

    test "renders banner usage links" do
      asset = %Asset{
        id: 1,
        filename: "banner.png",
        content_type: "image/png",
        size: 5_000,
        url: "/test/banner.png",
        inserted_at: ~U[2025-01-15 10:00:00Z]
      }

      usages = %{
        flow_nodes: [],
        sheet_avatars: [],
        sheet_banners: [%{id: 42, name: "Character Sheet"}]
      }

      html =
        render_component(&AssetComponents.detail_panel/1,
          asset: asset,
          usages: usages,
          workspace: %{slug: "ws"},
          project: %{slug: "proj"},
          can_edit: false
        )

      assert html =~ "Character Sheet"
      assert html =~ "banner"
      assert html =~ "/sheets/42"
    end
  end
end
