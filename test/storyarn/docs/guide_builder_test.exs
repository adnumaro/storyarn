defmodule Storyarn.Docs.GuideBuilderTest do
  use ExUnit.Case, async: true

  alias Storyarn.Docs
  alias Storyarn.Docs.GuideBuilder

  test "published Spanish guides emit localized internal documentation links" do
    guides = Docs.list_guides("es")

    assert Enum.any?(guides, &String.contains?(&1.body, ~s(href="/es/docs/)))

    for guide <- guides do
      refute guide.body =~ ~r/href="\/docs(?:\/|[?#"])/
    end
  end

  test "localizes safe public links and preserves query strings and fragments" do
    guide =
      build_guide(
        "es",
        """
        <h2>Navigation</h2>
        <p>
          <a id="docs" href="/docs/narrative-design/debug-mode?panel=variables#breakpoints">Docs</a>
          <a id="blog" href="/blog/introducing-storyarn?from=docs#model">Blog</a>
          <a id="register" href="/users/register?from=docs#account">Register</a>
        </p>
        """
      )

    assert guide.body =~ ~s(<h2 id="navigation">)

    assert link_attributes(guide.body, "docs") == %{
             "data-phx-link" => "redirect",
             "data-phx-link-state" => "push",
             "href" => "/es/docs/narrative-design/debug-mode?panel=variables#breakpoints",
             "id" => "docs"
           }

    assert link_attributes(guide.body, "blog")["href"] ==
             "/es/blog/introducing-storyarn?from=docs#model"

    assert link_attributes(guide.body, "register") == %{
             "data-phx-link" => "redirect",
             "data-phx-link-state" => "push",
             "href" => "/users/register?from=docs#account",
             "id" => "register"
           }
  end

  test "keeps English public links unprefixed and enables safe live navigation" do
    guide = build_guide("en", ~s(<a id="docs" href="/docs/welcome/start-here#intro">Docs</a>))

    assert link_attributes(guide.body, "docs") == %{
             "data-phx-link" => "redirect",
             "data-phx-link-state" => "push",
             "href" => "/docs/welcome/start-here#intro",
             "id" => "docs"
           }
  end

  test "localizes public destinations without enabling live navigation for unsafe links" do
    guide =
      build_guide(
        "es",
        """
        <p>
          <a id="external" href="https://example.com/docs">External</a>
          <a id="protocol-relative" href="//cdn.example.com/file">CDN</a>
          <a id="mailto" href="mailto:hello@example.com">Email</a>
          <a id="fragment" href="#intro">Jump</a>
          <a id="target" href="/docs/welcome/start-here" target="_blank">Target</a>
          <a id="download" href="/docs/welcome/start-here" download>Download</a>
          <a id="exempt" href="/docs/welcome/start-here" data-live-link-exempt>Exempt</a>
        </p>
        """
      )

    for {id, href} <- [
          {"external", "https://example.com/docs"},
          {"protocol-relative", "//cdn.example.com/file"},
          {"mailto", "mailto:hello@example.com"},
          {"fragment", "#intro"},
          {"target", "/es/docs/welcome/start-here"},
          {"download", "/es/docs/welcome/start-here"},
          {"exempt", "/es/docs/welcome/start-here"}
        ] do
      attrs = link_attributes(guide.body, id)

      assert attrs["href"] == href
      refute Map.has_key?(attrs, "data-phx-link")
      refute Map.has_key?(attrs, "data-phx-link-state")
    end

    assert link_attributes(guide.body, "target")["target"] == "_blank"
    assert Map.has_key?(link_attributes(guide.body, "download"), "download")
    assert Map.has_key?(link_attributes(guide.body, "exempt"), "data-live-link-exempt")
  end

  defp build_guide(locale, body) do
    GuideBuilder.build(
      "priv/docs/#{locale}/welcome/00-link-test.md",
      %{
        title: "Link test",
        category_label: "Welcome",
        order: 0,
        description: "Description"
      },
      body
    )
  end

  defp link_attributes(body, id) do
    {:ok, nodes} = Floki.parse_fragment(body)
    [{"a", attrs, _children}] = Floki.find(nodes, "##{id}")
    Map.new(attrs)
  end
end
