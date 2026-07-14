defmodule Storyarn.Blog do
  @moduledoc """
  Public API for Storyarn's editorial blog.

  Posts are compiled from Markdown in `priv/blog/` at build time. The blog is
  intentionally read-only: publishing a post is a content change and does not
  require a database or an administration surface.
  """

  alias Storyarn.Blog.Post

  def list_posts, do: Post.list_posts()
  defdelegate list_posts(locale), to: Post

  def get_post(slug), do: Post.get_post(slug)
  defdelegate get_post(slug, locale), to: Post
end
