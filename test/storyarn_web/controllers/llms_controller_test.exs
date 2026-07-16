defmodule StoryarnWeb.LlmsControllerTest do
  use StoryarnWeb.ConnCase, async: true

  alias Storyarn.Publication.Locales, as: PublicLocales

  test "GET /llms.txt groups canonical public content by locale", %{conn: conn} do
    conn = get(conn, ~p"/llms.txt")
    body = response(conn, 200)

    assert [content_type] = get_resp_header(conn, "content-type")
    assert content_type =~ "text/markdown"
    assert get_resp_header(conn, "cache-control") == ["public, max-age=3600"]

    assert body =~ "# Storyarn"
    assert body =~ "> Storyarn is a narrative design platform"
    assert body =~ "## English (en)"
    assert body =~ "## Español (es)"
    assert body =~ "### Product"
    assert body =~ "### Articles"
    assert body =~ "### Documentation"
    assert body =~ "#### Welcome"
    assert body =~ "## Optional"

    Enum.each(PublicLocales.descriptors(), fn descriptor ->
      assert body =~ "(#{descriptor.language_tag})"
    end)

    assert body =~ ~r"\[Storyarn\]\(http://localhost:\d+/\)"
    assert body =~ ~r"\[Storyarn\]\(http://localhost:\d+/es\)"
    assert body =~ ~r"\[Blog\]\(http://localhost:\d+/blog\)"
    assert body =~ ~r"\[Blog\]\(http://localhost:\d+/es/blog\)"

    assert body =~
             ~r"\[Introducing Storyarn: A Connected Narrative Design Platform\]\(http://localhost:\d+/blog/introducing-storyarn\)"

    assert body =~
             ~r"\[Presentamos Storyarn: una plataforma conectada para el diseño narrativo\]\(http://localhost:\d+/es/blog/presentamos-storyarn\)"

    assert body =~
             ~r"\[What is Storyarn\?\]\(http://localhost:\d+/docs/welcome/what-is-storyarn\)"

    assert body =~
             ~r"\[¿Qué es Storyarn\?\]\(http://localhost:\d+/es/docs/welcome/what-is-storyarn\)"

    assert body =~ ~r"\[Privacy Policy\]\(http://localhost:\d+/privacy\)"
    assert body =~ ~r"\[Privacy Policy\]\(http://localhost:\d+/es/privacy\)"

    refute body =~ ~r"\]\(http://localhost:\d+/docs\)"
    refute body =~ ~r"\]\(http://localhost:\d+/es/docs\)"
    refute body =~ ~r"\]\(http://localhost:\d+/en(?:/|\))"
    refute body =~ "<!DOCTYPE html>"
    refute body =~ "/users/log-in"
    refute body =~ "/projects/invitations"
    refute body =~ "/workspaces/"
  end

  test "locale sections do not mix canonical language paths", %{conn: conn} do
    body = conn |> get(~p"/llms.txt") |> response(200)

    english = section_between(body, "## English (en)", "## Español (es)")
    spanish = section_between(body, "## Español (es)", "## Optional")

    assert english =~ ~r"http://localhost:\d+/docs/"
    assert english =~ ~r"http://localhost:\d+/blog/"
    refute english =~ ~r"http://localhost:\d+/es(?:/|\))"

    assert spanish =~ ~r"http://localhost:\d+/es/docs/"
    assert spanish =~ ~r"http://localhost:\d+/es/blog/"
    refute spanish =~ ~r"http://localhost:\d+/docs/"
    refute spanish =~ ~r"http://localhost:\d+/blog/"
  end

  defp section_between(body, start_heading, end_heading) do
    [_before, section_with_end] = String.split(body, start_heading, parts: 2)
    [section, _after] = String.split(section_with_end, end_heading, parts: 2)
    section
  end
end
