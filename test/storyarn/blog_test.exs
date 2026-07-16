defmodule Storyarn.BlogTest do
  use ExUnit.Case, async: true

  alias Storyarn.Blog
  alias Storyarn.Blog.PostBuilder

  @slug "introducing-storyarn"
  @debug_image_path Path.expand(
                      "../../priv/static/images/blog/introducing-storyarn-debug-active-node.png",
                      __DIR__
                    )
  @debug_image_sha256 "79d6ab45511ed09be891ce1b89644faabea2ae64893ea5022df39c675b924814"

  test "lists published posts with editorial metadata" do
    [post | _] = Blog.list_posts()

    assert post.slug == @slug
    assert post.id == "introducing-storyarn:en"
    assert post.translation_key == "introducing-storyarn"
    assert post.locale == "en"
    assert post.published_on == ~D[2026-07-14]

    assert post.title ==
             "Introducing Storyarn: A Connected Narrative Design Platform"

    assert post.seo_title == "Introducing Storyarn: Narrative Design Platform"

    assert post.description =~ "narrative design platform"
    assert post.author == "Storyarn Team"
    assert post.author_url == "/"
    assert post.image == "/images/docs/project-dashboard-current.png"
    assert post.image_alt =~ "Storyarn project dashboard"
    assert post.updated_on == ~D[2026-07-15]
    assert "Storyarn" in post.tags
    assert "Narrative design" in post.tags
    assert post.reading_time >= 5
  end

  test "keeps compiled entries separate from posts visible by publication date" do
    compiled_posts = Blog.list_compiled_posts()
    post = Enum.find(compiled_posts, &(&1.id == "introducing-storyarn:en"))

    assert post
    assert post in Blog.list_published_posts(post.published_on)
    refute post in Blog.list_published_posts(Date.add(post.published_on, -1))
    assert post in compiled_posts

    assert Blog.list_all_posts() == Blog.list_published_posts()

    assert MapSet.subset?(
             MapSet.new(Blog.list_published_posts()),
             MapSet.new(compiled_posts)
           )
  end

  test "groups localized articles by a stable translation key" do
    assert Blog.default_locale() == "en"
    assert Blog.published_locales() == ["en", "es"]

    assert [english, spanish] = Blog.list_translations("introducing-storyarn")
    assert english.slug == "introducing-storyarn"
    assert english.id == "introducing-storyarn:en"
    assert spanish.slug == "presentamos-storyarn"
    assert spanish.id == "introducing-storyarn:es"
    assert spanish.title =~ "Presentamos Storyarn"
    assert english.published_on == spanish.published_on
    assert Blog.get_translation("introducing-storyarn", "es") == spanish
  end

  test "gets an editorial post with anchored sections, screenshots, and live internal links" do
    post = Blog.get_post(@slug)

    assert post.body =~ ~s(<h2 id="the-problem-is-not-writing-the-line">)
    assert post.body =~ ~s(<h2 id="a-connected-narrative-model">)
    assert post.body =~ ~s(src="/images/docs/flows-editor-current.png")
    assert post.body =~ ~s(href="/docs/narrative-design/debug-mode")
    assert post.body =~ ~s(data-phx-link="redirect")
    assert post.body =~ "<figure>"
    assert post.body =~ "<figcaption>"
    assert post.body =~ "World Anvil focuses on organizing and presenting"
    assert post.body =~ "articy:draft and Arcweave cover a much broader"
    assert post.body =~ "Yarn Spinner and Ink"
    assert post.body =~ ~s(src="/images/blog/introducing-storyarn-debug-active-node.png")
    assert post.body =~ "active dialogue node"
    refute String.contains?(String.downcase(post.body), "spreadsheet")
    refute post.body =~ ~r/<h[23][^>]*>\s*\d+[.\s]/
    refute post.body =~ "<ol>"
  end

  test "publishes a complete Spanish editorial translation" do
    post = Blog.get_post("presentamos-storyarn", "es")

    assert post.locale == "es"
    assert post.translation_key == "introducing-storyarn"
    assert post.author == "Equipo de Storyarn"
    assert post.body =~ ~s(<h2 id="el-problema-no-es-escribir-la-frase">)
    assert post.updated_on == ~D[2026-07-15]
    assert post.body =~ "World Anvil se centra en organizar y presentar"
    assert post.body =~ "articy:draft y Arcweave cubren un espacio mucho más amplio"
    assert post.body =~ "Yarn Spinner e Ink"
    assert post.body =~ ~s(src="/images/blog/introducing-storyarn-debug-active-node.png")
    assert post.body =~ "un nodo de diálogo activo"
    assert post.body =~ ~s(href="/es/docs/narrative-design/debug-mode")
    assert post.body =~ ~s(data-phx-link="redirect")
    refute String.contains?(String.downcase(post.body), "spreadsheet")
    refute post.body =~ "<ol>"
  end

  test "ships the visually approved debugger image used by both translations" do
    digest =
      @debug_image_path
      |> File.read!()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    assert digest == @debug_image_sha256
  end

  test "localizes safe public links while preserving query strings and fragments" do
    post =
      build_post(
        "es",
        """
        <p>
          <a id="docs" href="/docs/narrative-design/debug-mode?panel=variables#breakpoints">Docs</a>
          <a id="home" href="/?campaign=launch#features">Home</a>
          <a id="contact" href="/contact?from=blog#form">Contact</a>
          <a id="register" href="/users/register?from=blog#account">Register</a>
        </p>
        """
      )

    assert link_attributes(post.body, "docs") == %{
             "data-phx-link" => "redirect",
             "data-phx-link-state" => "push",
             "href" => "/es/docs/narrative-design/debug-mode?panel=variables#breakpoints",
             "id" => "docs"
           }

    assert link_attributes(post.body, "contact")["href"] == "/es/contact?from=blog#form"
    assert link_attributes(post.body, "home")["href"] == "/es?campaign=launch#features"

    assert link_attributes(post.body, "register") == %{
             "data-phx-link" => "redirect",
             "data-phx-link-state" => "push",
             "href" => "/users/register?from=blog#account",
             "id" => "register"
           }
  end

  test "keeps English public links unprefixed and enables safe live navigation" do
    post = build_post("en", ~s(<a id="docs" href="/docs/welcome/start-here#intro">Docs</a>))

    assert link_attributes(post.body, "docs") == %{
             "data-phx-link" => "redirect",
             "data-phx-link-state" => "push",
             "href" => "/docs/welcome/start-here#intro",
             "id" => "docs"
           }
  end

  test "localizes public destinations without enabling live navigation for unsafe links" do
    post =
      build_post(
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
      attrs = link_attributes(post.body, id)

      assert attrs["href"] == href
      refute Map.has_key?(attrs, "data-phx-link")
      refute Map.has_key?(attrs, "data-phx-link-state")
    end

    assert link_attributes(post.body, "target")["target"] == "_blank"
    assert Map.has_key?(link_attributes(post.body, "download"), "download")
    assert Map.has_key?(link_attributes(post.body, "exempt"), "data-live-link-exempt")
  end

  test "returns nil for an unknown slug or locale" do
    assert Blog.get_post("missing") == nil
    assert Blog.get_post(@slug, "es") == nil
  end

  test "rejects an updated date earlier than publication" do
    assert_raise ArgumentError, ~r/updated_on cannot be earlier/, fn ->
      PostBuilder.build(
        "priv/blog/en/2026-07-14-test-post.md",
        %{
          translation_key: "test-post",
          title: "Test post",
          description: "Description",
          updated_on: "2026-07-13"
        },
        "<p>Body</p>"
      )
    end
  end

  test "rejects an invalid translation key" do
    assert_raise ArgumentError, ~r/translation_key must be a lowercase slug/, fn ->
      PostBuilder.build(
        "priv/blog/en/2026-07-14-test-post.md",
        %{translation_key: "Invalid key", title: "Test post", description: "Description"},
        "<p>Body</p>"
      )
    end
  end

  defp build_post(locale, body) do
    PostBuilder.build(
      "priv/blog/#{locale}/2026-07-14-link-test.md",
      %{translation_key: "link-test", title: "Link test", description: "Description"},
      body
    )
  end

  defp link_attributes(body, id) do
    {:ok, nodes} = Floki.parse_fragment(body)
    [{"a", attrs, _children}] = Floki.find(nodes, "##{id}")
    Map.new(attrs)
  end
end
