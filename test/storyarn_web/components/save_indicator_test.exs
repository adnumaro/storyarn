defmodule StoryarnWeb.Components.SaveIndicatorTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.Components.SaveIndicator

  describe "inline variant" do
    test "renders nothing when status is :idle" do
      html = render_component(&SaveIndicator.save_indicator/1, status: :idle, variant: :inline)
      refute html =~ "Saving"
      refute html =~ "Saved"
    end

    test "renders saving state with spinner" do
      html = render_component(&SaveIndicator.save_indicator/1, status: :saving, variant: :inline)
      assert html =~ "Saving"
      assert html =~ "loading-spinner"
    end

    test "renders saved state with success text" do
      html = render_component(&SaveIndicator.save_indicator/1, status: :saved, variant: :inline)
      assert html =~ "Saved"
      assert html =~ "text-success"
    end

    test "does not show spinner when saved" do
      html = render_component(&SaveIndicator.save_indicator/1, status: :saved, variant: :inline)
      refute html =~ "loading-spinner"
    end

    test "does not show check icon when saving" do
      html = render_component(&SaveIndicator.save_indicator/1, status: :saving, variant: :inline)
      refute html =~ "text-success"
    end
  end

  describe "floating variant" do
    test "renders nothing when status is :idle" do
      html =
        render_component(&SaveIndicator.save_indicator/1, status: :idle, variant: :floating)

      refute html =~ "Saving"
      refute html =~ "Saved"
    end

    test "renders saving state with background" do
      html =
        render_component(&SaveIndicator.save_indicator/1, status: :saving, variant: :floating)

      assert html =~ "Saving"
      assert html =~ "loading-spinner"
      assert html =~ "bg-base-200"
    end

    test "renders saved state with success background" do
      html =
        render_component(&SaveIndicator.save_indicator/1, status: :saved, variant: :floating)

      assert html =~ "Saved"
      assert html =~ "bg-success/10"
      assert html =~ "text-success"
    end

    test "has absolute positioning for floating container" do
      html =
        render_component(&SaveIndicator.save_indicator/1, status: :saving, variant: :floating)

      assert html =~ "absolute top-2 right-0"
    end

    test "has fade-in animation" do
      html =
        render_component(&SaveIndicator.save_indicator/1, status: :saving, variant: :floating)

      assert html =~ "animate-in fade-in duration-300"
    end
  end

  describe "default variant" do
    test "defaults to :inline when variant not specified" do
      html = render_component(&SaveIndicator.save_indicator/1, status: :saving)
      # Inline variant does NOT have absolute positioning
      refute html =~ "absolute"
      assert html =~ "Saving"
    end
  end
end
