defmodule StoryarnWeb.BlogLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Blog

  @post_locale "en"

  @impl true
  def mount(_params, _session, socket) do
    posts = Blog.list_posts(@post_locale)
    featured_post = List.first(posts)
    remaining_posts = Enum.drop(posts, 1)

    {:ok,
     socket
     |> assign(
       page_title: dgettext("blog", "Narrative Design Journal"),
       canonical_url: Layouts.absolute_url(~p"/blog"),
       seo_description:
         dgettext(
           "blog",
           "Product thinking, narrative design practice, and lessons from building Storyarn as a connected workspace for interactive stories."
         ),
       featured_post: featured_post,
       has_more_posts: remaining_posts != []
     )
     |> stream(:posts, remaining_posts)}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :seo_metadata, Layouts.live_seo_metadata(assigns))

    ~H"""
    <StoryarnWeb.Components.PublicLayout.public
      flash={@flash}
      socket={@socket}
      seo_metadata={@seo_metadata}
      current_scope={@current_scope}
      theme="dark"
    >
      <section id="blog-index" class="relative overflow-hidden px-6 pb-28 pt-36 sm:pt-44">
        <div class="pointer-events-none absolute inset-x-0 top-0 h-[38rem] bg-[radial-gradient(circle_at_18%_0%,rgba(45,212,191,0.16),transparent_44%),radial-gradient(circle_at_82%_8%,rgba(56,189,248,0.1),transparent_40%)]">
        </div>

        <div class="relative mx-auto w-full max-w-7xl">
          <header class="max-w-4xl">
            <p class="text-sm font-semibold uppercase tracking-[0.18em] text-primary">
              {dgettext("blog", "Inside Storyarn")}
            </p>
            <h1 class="mt-5 text-4xl font-bold leading-[1.05] tracking-[-0.045em] text-balance sm:text-6xl lg:text-7xl">
              {dgettext("blog", "Notes on building a connected narrative design platform.")}
            </h1>
            <p class="mt-7 max-w-2xl text-lg leading-8 text-muted-foreground sm:text-xl">
              {dgettext(
                "blog",
                "Product decisions, narrative production problems, and what we are learning while Storyarn grows."
              )}
            </p>
          </header>

          <div
            :if={is_nil(@featured_post)}
            id="blog-empty-state"
            class="mt-16 rounded-3xl border border-border/70 bg-card/60 p-9 text-muted-foreground"
          >
            {dgettext("blog", "No published articles yet.")}
          </div>

          <article
            :if={@featured_post}
            id="blog-featured-post"
            lang={@featured_post.locale}
            class="group relative mt-16 grid overflow-hidden rounded-[2rem] border border-border/70 bg-card/70 shadow-[0_30px_100px_rgba(0,0,0,0.24)] transition duration-300 hover:-translate-y-1 hover:border-primary/40 lg:grid-cols-[1.02fr_0.98fr]"
          >
            <div class="flex flex-col justify-center p-8 sm:p-12 lg:p-14">
              <div class="flex flex-wrap items-center gap-3 text-sm text-muted-foreground">
                <span
                  lang={@locale}
                  class="font-semibold uppercase tracking-[0.14em] text-primary"
                >
                  {dgettext("blog", "Featured story")}
                </span>
                <span aria-hidden="true">·</span>
                <time datetime={Date.to_iso8601(@featured_post.published_on)}>
                  {format_date(@featured_post.published_on)}
                </time>
                <span aria-hidden="true">·</span>
                <span lang={@locale}>{reading_time(@featured_post.reading_time)}</span>
              </div>

              <h2 class="mt-6 text-3xl font-semibold leading-[1.12] tracking-[-0.035em] text-balance sm:text-5xl">
                <.link
                  navigate={~p"/blog/#{@featured_post.slug}"}
                  class="after:absolute after:inset-0 focus:outline-none focus-visible:rounded-sm focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-primary"
                >
                  {@featured_post.title}
                </.link>
              </h2>
              <p class="mt-6 max-w-2xl text-base leading-7 text-muted-foreground sm:text-lg sm:leading-8">
                {@featured_post.description}
              </p>

              <div class="mt-8 flex flex-wrap items-center justify-between gap-5">
                <div class="flex flex-wrap gap-2">
                  <span
                    :for={tag <- @featured_post.tags}
                    class="badge badge-ghost border border-border/70"
                  >
                    {tag}
                  </span>
                </div>
                <span
                  lang={@locale}
                  class="inline-flex items-center gap-2 text-sm font-semibold text-primary transition-transform group-hover:translate-x-1"
                >
                  {dgettext("blog", "Read the story")} <.icon name="arrow-right" class="size-4" />
                </span>
              </div>
            </div>

            <figure class="relative flex min-h-72 items-center overflow-hidden border-t border-border/70 bg-muted/25 p-4 lg:min-h-[30rem] lg:border-l lg:border-t-0">
              <img
                id="blog-featured-post-image"
                src={@featured_post.image}
                alt={@featured_post.image_alt}
                class="w-full rounded-xl border border-border/60 object-contain shadow-2xl transition duration-700 group-hover:scale-[1.015]"
                loading="eager"
                fetchpriority="high"
              />
            </figure>
          </article>

          <section :if={@has_more_posts} class="mt-20" aria-labelledby="more-stories-title">
            <h2 id="more-stories-title" class="text-2xl font-semibold tracking-tight">
              {dgettext("blog", "More from the journal")}
            </h2>
            <div
              id="blog-posts"
              phx-update="stream"
              class="mt-8 grid gap-6 md:grid-cols-2 lg:grid-cols-3"
            >
              <article
                :for={{dom_id, post} <- @streams.posts}
                id={dom_id}
                lang={post.locale}
                class="group relative overflow-hidden rounded-2xl border border-border/70 bg-card/65 transition duration-300 hover:-translate-y-1 hover:border-primary/40"
              >
                <img
                  src={post.image}
                  alt={post.image_alt}
                  class="aspect-video w-full border-b border-border/70 object-cover object-left-top"
                  loading="lazy"
                />
                <div class="p-7">
                  <div class="flex items-center gap-2 text-xs text-muted-foreground">
                    <time datetime={Date.to_iso8601(post.published_on)}>
                      {format_date(post.published_on)}
                    </time>
                    <span aria-hidden="true">·</span>
                    <span lang={@locale}>{reading_time(post.reading_time)}</span>
                  </div>
                  <h3 class="mt-4 text-2xl font-semibold leading-tight tracking-tight">
                    <.link
                      navigate={~p"/blog/#{post.slug}"}
                      class="after:absolute after:inset-0 focus:outline-none focus-visible:outline-2 focus-visible:outline-primary"
                    >
                      {post.title}
                    </.link>
                  </h3>
                  <p class="mt-4 line-clamp-3 leading-7 text-muted-foreground">{post.description}</p>
                </div>
              </article>
            </div>
          </section>
        </div>
      </section>
    </StoryarnWeb.Components.PublicLayout.public>
    """
  end

  defp format_date(date), do: Calendar.strftime(date, "%B %-d, %Y")

  defp reading_time(count) do
    dngettext("blog", "%{count} min read", "%{count} min read", count, count: count)
  end
end
