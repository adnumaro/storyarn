defmodule StoryarnWeb.E2E.DocsSEOTest do
  @moduledoc """
  Browser coverage for public docs before and after LiveView connects.
  """

  use PhoenixTest.Playwright.Case, async: false

  @moduletag :e2e

  @guide_path "/docs/welcome/what-is-storyarn"
  @spanish_guide_path "/es/docs/welcome/what-is-storyarn"
  @spanish_next_path "/es/docs/welcome/core-concepts"

  @tag browser_context_opts: [java_script_enabled: false]
  test "docs remain readable and navigable without JavaScript", %{conn: conn} do
    conn
    |> visit(@guide_path)
    |> assert_has("#docs-reading-article h1", text: "What is Storyarn?")
    |> assert_has("#docs-reading-body", text: "narrative design platform")
    |> assert_has("h1", count: 1)
    |> refute_has("body .phx-connected")
    |> click("#docs-reading-language-switcher-trigger")
    |> click("#docs-reading-language-switcher-es")
    |> assert_path(@spanish_guide_path)
    |> assert_has("html[lang='es']")
    |> assert_has("#docs-reading-article h1", text: "¿Qué es Storyarn?")
    |> assert_has("#docs-reading-body", text: "plataforma de diseño narrativo")
    |> assert_has("h1", count: 1)
    |> click("#docs-reading-next-link")
    |> assert_path(@spanish_next_path)
    |> assert_has("#docs-reading-article h1", text: "Conceptos clave")
    |> assert_has("#docs-reading-body", text: "Workspace")
    |> assert_has("h1", count: 1)
  end

  test "connected Vue docs replace the reading view and preserve localized navigation", %{conn: conn} do
    conn
    |> visit(@guide_path)
    |> assert_has("body .phx-connected")
    |> assert_has("#docs-layout")
    |> assert_has("#docs-main h1", text: "What is Storyarn?")
    |> assert_has("#docs-main .docs-content", text: "narrative design platform")
    |> refute_has("#docs-reading-view")
    |> assert_has("h1", count: 1)
    |> click("#docs-language-switcher-trigger")
    |> click("#docs-language-switcher-es")
    |> assert_path(@spanish_guide_path)
    |> assert_has("html[lang='es']")
    |> assert_has("#docs-main h1", text: "¿Qué es Storyarn?")
    |> assert_has("#docs-main .docs-content", text: "plataforma de diseño narrativo")
    |> refute_has("#docs-reading-view")
    |> assert_has("h1", count: 1)
    |> click("#docs-main nav a[href='#{@spanish_next_path}']")
    |> assert_path(@spanish_next_path)
    |> assert_has("#docs-main h1", text: "Conceptos clave")
    |> assert_has("#docs-main .docs-content", text: "Workspace")
    |> refute_has("#docs-reading-view")
    |> assert_has("h1", count: 1)
  end
end
