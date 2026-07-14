defmodule Storyarn.BlogTest do
  use ExUnit.Case, async: true

  alias Storyarn.Blog

  @slug "introducing-storyarn"

  test "lists published posts with editorial metadata" do
    [post | _] = Blog.list_posts()

    assert post.slug == @slug
    assert post.id == @slug
    assert post.published_on == ~D[2026-07-14]

    assert post.title ==
             "Introducing Storyarn: A Connected Narrative Design Platform"

    assert post.seo_title == "Introducing Storyarn: Narrative Design Platform"

    assert post.description =~ "narrative design platform"
    assert post.author == "Storyarn Team"
    assert post.author_url == "/"
    assert post.image == "/images/docs/project-dashboard-current.png"
    assert post.image_alt =~ "Storyarn project dashboard"
    assert post.updated_on == post.published_on
    assert "Storyarn" in post.tags
    assert "Narrative design" in post.tags
    assert post.reading_time >= 5
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
    refute post.body =~ ~r/<h[23][^>]*>\s*\d+[.\s]/
    refute post.body =~ "<ol>"
  end

  test "returns nil for an unknown slug or locale" do
    assert Blog.get_post("missing") == nil
    assert Blog.get_post(@slug, "es") == nil
  end

  test "rejects an updated date earlier than publication" do
    assert_raise ArgumentError, ~r/updated_on cannot be earlier/, fn ->
      Storyarn.Blog.PostBuilder.build(
        "priv/blog/en/2026-07-14-test-post.md",
        %{title: "Test post", description: "Description", updated_on: "2026-07-13"},
        "<p>Body</p>"
      )
    end
  end
end
