defmodule StoryarnWeb.BlogLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Blog

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: gettext("Storyarn Blog"),
       seo_description:
         gettext(
           "Practical articles about branching dialogue, narrative design, worldbuilding, localization, testing, and game engine export."
         )
     )
     |> stream(:posts, Blog.list_posts())}
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
      <section id="blog-index" class="relative overflow-hidden px-6 pb-24 pt-36 sm:pt-44">
        <div class="pointer-events-none absolute inset-x-0 top-0 -z-0 h-[34rem] bg-[radial-gradient(circle_at_50%_0%,rgba(45,212,191,0.12),transparent_62%)]">
        </div>

        <div class="relative z-10 mx-auto w-full max-w-6xl">
          <div class="max-w-3xl">
            <div class="badge badge-outline border-primary/30 bg-primary/5 px-3 py-3 text-primary">
              Narrative production notes
            </div>
            <h1 class="mt-6 text-4xl font-bold tracking-[-0.04em] text-balance sm:text-6xl">
              Better systems for interactive stories.
            </h1>
            <p class="mt-6 max-w-2xl text-lg leading-8 text-muted-foreground sm:text-xl">
              Practical guides for designing, testing, localizing, and delivering branching narrative without losing control of the project.
            </p>
          </div>

          <div id="blog-posts" phx-update="stream" class="mt-16 grid gap-6 lg:grid-cols-2">
            <article
              :for={{dom_id, post} <- @streams.posts}
              id={dom_id}
              class="group relative overflow-hidden rounded-3xl border border-border/70 bg-card/60 p-7 shadow-sm transition duration-300 hover:-translate-y-1 hover:border-primary/40 hover:shadow-[0_24px_80px_rgba(0,0,0,0.28)] sm:p-9"
            >
              <div class="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-primary/60 to-transparent opacity-0 transition-opacity group-hover:opacity-100">
              </div>

              <div class="flex flex-wrap items-center gap-3 text-sm text-muted-foreground">
                <time datetime={Date.to_iso8601(post.published_on)}>
                  {format_date(post.published_on)}
                </time>
                <span aria-hidden="true">·</span>
                <span>
                  {ngettext("%{count} min read", "%{count} min read", post.reading_time,
                    count: post.reading_time
                  )}
                </span>
              </div>

              <h2 class="mt-5 text-2xl font-semibold leading-tight tracking-tight text-balance sm:text-3xl">
                <.link
                  navigate={~p"/blog/#{post.slug}"}
                  class="after:absolute after:inset-0 focus:outline-none"
                >
                  {post.title}
                </.link>
              </h2>
              <p class="mt-4 text-base leading-7 text-muted-foreground">{post.description}</p>

              <div class="mt-7 flex flex-wrap items-end justify-between gap-5">
                <div class="flex flex-wrap gap-2">
                  <span :for={tag <- post.tags} class="badge badge-ghost border border-border/70">
                    {tag}
                  </span>
                </div>
                <span class="inline-flex items-center gap-2 text-sm font-semibold text-primary transition-transform group-hover:translate-x-1">
                  Read article <.icon name="arrow-right" class="size-4" />
                </span>
              </div>
            </article>
          </div>
        </div>
      </section>
    </StoryarnWeb.Components.PublicLayout.public>
    """
  end

  defp format_date(date), do: Calendar.strftime(date, "%B %-d, %Y")
end
