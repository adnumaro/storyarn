defmodule Storyarn.Blog do
  @moduledoc """
  Public API for Storyarn's editorial blog.

  Posts are compiled from Markdown in `priv/blog/` at build time. The blog is
  intentionally read-only: publishing a post is a content change and does not
  require a database or an administration surface.
  """

  alias Storyarn.Blog.Post

  defdelegate list_posts(locale \\ "en"), to: Post
  defdelegate get_post(slug, locale \\ "en"), to: Post
end
