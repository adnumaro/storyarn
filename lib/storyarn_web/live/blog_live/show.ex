defmodule StoryarnWeb.BlogLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Blog
  alias Storyarn.Shared.HtmlSanitizer

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(%{"slug" => slug}, _uri, socket) do
    case Blog.get_post(slug) do
      nil ->
        raise Ecto.NoResultsError, queryable: "blog_posts"

      post ->
        {:noreply,
         assign(socket,
           page_title: post.title,
           seo_description: post.description,
           seo_type: "article",
           seo_published_on: post.published_on,
           seo_article_author: post.author,
           seo_article_tags: post.tags,
           post: post
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.PublicLayout.public
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      theme="dark"
      native
    >
      <article id="blog-post" class="relative overflow-hidden px-6 pb-24 pt-36 sm:pt-44">
        <div class="pointer-events-none absolute inset-x-0 top-0 -z-0 h-[34rem] bg-[radial-gradient(circle_at_50%_0%,rgba(45,212,191,0.12),transparent_62%)]">
        </div>

        <div class="relative z-10 mx-auto w-full max-w-3xl">
          <.link
            id="blog-back-link"
            navigate={~p"/blog"}
            class="inline-flex items-center gap-2 text-sm font-medium text-muted-foreground transition-colors hover:text-foreground"
          >
            <.icon name="arrow-left" class="size-4" /> Back to the blog
          </.link>

          <header class="mt-10 border-b border-border/70 pb-10">
            <div class="flex flex-wrap items-center gap-3 text-sm text-muted-foreground">
              <time datetime={Date.to_iso8601(@post.published_on)}>
                {format_date(@post.published_on)}
              </time>
              <span aria-hidden="true">·</span>
              <span>
                {ngettext("%{count} min read", "%{count} min read", @post.reading_time,
                  count: @post.reading_time
                )}
              </span>
            </div>

            <h1 class="mt-6 text-4xl font-bold leading-[1.08] tracking-[-0.04em] text-balance sm:text-6xl">
              {@post.title}
            </h1>
            <p class="mt-6 text-xl leading-8 text-muted-foreground">{@post.description}</p>

            <div class="mt-7 flex flex-wrap items-center gap-3">
              <span class="text-sm font-medium text-foreground">By {@post.author}</span>
              <span
                :for={tag <- @post.tags}
                class="badge badge-outline border-border/80 text-muted-foreground"
              >
                {tag}
              </span>
            </div>
          </header>

          <div id="blog-post-content" class="docs-content mt-10 max-w-none">
            {raw(HtmlSanitizer.sanitize_html(@post.body))}
          </div>

          <aside class="mt-16 rounded-3xl border border-primary/20 bg-primary/5 p-7 sm:p-9">
            <p class="text-sm font-semibold uppercase tracking-[0.18em] text-primary">
              Keep exploring
            </p>
            <h2 class="mt-3 text-2xl font-semibold tracking-tight">
              Build and test the flow in one connected workspace.
            </h2>
            <p class="mt-3 leading-7 text-muted-foreground">
              Explore Storyarn's documentation or join the early-access list to bring your narrative workflow together.
            </p>
            <div class="mt-6 flex flex-wrap gap-3">
              <.link navigate={~p"/docs"} class="btn btn-primary rounded-full">
                Explore the docs
              </.link>
              <a href="/#waitlist" class="btn btn-ghost rounded-full">Request access</a>
            </div>
          </aside>
        </div>
      </article>
    </StoryarnWeb.Components.PublicLayout.public>
    """
  end

  defp format_date(date), do: Calendar.strftime(date, "%B %-d, %Y")
end
