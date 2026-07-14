defmodule Storyarn.BlogTest do
  use ExUnit.Case, async: true

  alias Storyarn.Blog

  @slug "test-branching-dialogue-before-export"

  test "lists published posts with editorial metadata" do
    [post | _] = Blog.list_posts()

    assert post.slug == @slug
    assert post.id == @slug
    assert post.published_on == ~D[2026-07-14]
    assert post.title == "How to Test Branching Dialogue Before Exporting It to Your Game Engine"
    assert post.description =~ "testing branching dialogue"
    assert post.author == "Storyarn Team"
    assert post.author_url == "/"
    assert post.image == "/images/landing/storyarn-lab-hero.webp"
    assert post.updated_on == post.published_on
    assert "Narrative design" in post.tags
    assert post.reading_time >= 1
  end

  test "gets a post by slug with rendered heading anchors" do
    post = Blog.get_post(@slug)

    assert post.body =~ ~s(<h2 id="1-define-the-states-that-control-the-conversation">)
    assert post.body =~ ~s(href="/docs/narrative-design/debug-mode")
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
