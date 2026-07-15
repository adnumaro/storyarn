defmodule StoryarnWeb.BlogLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Blog
  alias Storyarn.Publication.Locales, as: PublicLocales
  alias Storyarn.Shared.HtmlSanitizer
  alias StoryarnWeb.BlogFormatting
  alias StoryarnWeb.BlogURLs
  alias StoryarnWeb.PublicURLs

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"slug" => slug}, uri, socket) do
    locale = BlogURLs.locale_from_uri(uri) || raise Ecto.NoResultsError, queryable: "blog_locales"
    Gettext.put_locale(Storyarn.Gettext, locale)

    case Blog.get_post(slug, locale) do
      nil ->
        raise Ecto.NoResultsError, queryable: "blog_posts"

      post ->
        canonical_url = Layouts.absolute_url(BlogURLs.post_path(post))
        image_url = Layouts.absolute_url(post.image)

        {:noreply,
         assign(socket,
           locale: locale,
           page_title: post.seo_title,
           canonical_url: canonical_url,
           seo_description: post.description,
           seo_image_url: image_url,
           seo_type: "article",
           seo_published_on: post.published_on,
           seo_modified_on: post.updated_on,
           seo_article_tags: post.tags,
           seo_alternate_links: BlogURLs.post_alternate_links(post),
           seo_json_ld: structured_data(post, canonical_url, image_url),
           language_links: BlogURLs.post_language_links(post),
           post: post
         )}
    end
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
      language_links={@language_links}
      theme="dark"
    >
      <article
        id="blog-post"
        lang={PublicLocales.language_tag(@post.locale)}
        class="relative overflow-hidden pb-28 pt-36 sm:pt-44"
      >
        <div class="pointer-events-none absolute inset-x-0 top-0 h-[42rem] bg-[radial-gradient(circle_at_50%_0%,rgba(45,212,191,0.15),transparent_58%)]">
        </div>

        <header class="relative mx-auto w-full max-w-4xl px-6 text-center">
          <div class="flex items-center justify-start">
            <.link
              id="blog-back-link"
              navigate={BlogURLs.index_path(@post.locale)}
              lang={PublicLocales.language_tag(@locale)}
              class="inline-flex items-center gap-2 text-sm font-medium text-muted-foreground transition-colors hover:text-foreground"
            >
              <.icon name="arrow-left" class="size-4" /> {dgettext("blog", "Back to the journal")}
            </.link>
          </div>

          <div class="mt-10 flex flex-wrap items-center justify-center gap-3 text-sm text-muted-foreground">
            <span class="font-semibold uppercase tracking-[0.14em] text-primary">Storyarn</span>
            <span aria-hidden="true">·</span>
            <time datetime={Date.to_iso8601(@post.published_on)}>
              {BlogFormatting.format_date(@post.published_on, @locale)}
            </time>
            <span aria-hidden="true">·</span>
            <span lang={PublicLocales.language_tag(@locale)}>
              {reading_time(@post.reading_time)}
            </span>
          </div>

          <h1 class="mt-7 text-4xl font-bold leading-[1.04] tracking-[-0.045em] text-balance sm:text-6xl lg:text-7xl">
            {@post.title}
          </h1>
          <p class="mx-auto mt-7 max-w-3xl text-xl leading-8 text-muted-foreground">
            {@post.description}
          </p>

          <div class="mt-8 flex flex-wrap items-center justify-center gap-3">
            <span
              lang={PublicLocales.language_tag(@locale)}
              class="text-sm font-medium text-foreground"
            >
              {dgettext("blog", "By %{author}", author: @post.author)}
            </span>
            <span
              :for={tag <- @post.tags}
              class="badge badge-outline border-border/80 text-muted-foreground"
            >
              {tag}
            </span>
          </div>
        </header>

        <figure class="relative mx-auto mt-14 w-[min(calc(100%-48px),1152px)] overflow-hidden rounded-[2rem] border border-border/70 bg-card shadow-[0_32px_120px_rgba(0,0,0,0.34)]">
          <img
            id="blog-post-hero"
            src={@post.image}
            alt={@post.image_alt}
            class="aspect-video w-full object-cover object-left-top"
            loading="eager"
            fetchpriority="high"
          />
        </figure>

        <div class="relative mx-auto mt-16 w-full max-w-3xl px-6">
          <div id="blog-post-content" class="blog-content">
            {raw(HtmlSanitizer.sanitize_html(@post.body))}
          </div>

          <aside
            lang={PublicLocales.language_tag(@locale)}
            class="mt-20 overflow-hidden rounded-3xl border border-primary/20 bg-[radial-gradient(circle_at_100%_0%,rgba(45,212,191,0.16),transparent_45%),rgba(45,212,191,0.04)] p-8 sm:p-10"
          >
            <p class="text-sm font-semibold uppercase tracking-[0.18em] text-primary">
              {dgettext("blog", "Storyarn is in open beta")}
            </p>
            <h2 class="mt-4 text-3xl font-semibold leading-tight tracking-[-0.025em] text-balance">
              {dgettext("blog", "Bring the whole narrative into one connected project.")}
            </h2>
            <p class="mt-4 max-w-xl leading-7 text-muted-foreground">
              {dgettext(
                "blog",
                "Registration is open, Storyarn is free during early access, and no invitation is required."
              )}
            </p>
            <.link
              id="blog-register-cta"
              navigate={PublicURLs.locale_handoff_path(~p"/users/register", @locale)}
              class="btn btn-primary mt-7 rounded-full px-6"
            >
              {dgettext("blog", "Create your Storyarn account")}
              <.icon
                name="arrow-right"
                class="size-4"
              />
            </.link>
          </aside>
        </div>
      </article>
    </StoryarnWeb.Components.PublicLayout.public>
    """
  end

  defp reading_time(count) do
    dngettext("blog", "%{count} min read", "%{count} min read", count, count: count)
  end

  defp structured_data(post, canonical_url, image_url) do
    organization_url = Layouts.absolute_url(~p"/")

    %{
      "@context" => "https://schema.org",
      "@type" => "BlogPosting",
      "author" => %{
        "@type" => "Organization",
        "name" => post.author,
        "url" => Layouts.absolute_url(post.author_url)
      },
      "dateModified" => Date.to_iso8601(post.updated_on),
      "datePublished" => Date.to_iso8601(post.published_on),
      "description" => post.description,
      "headline" => post.title,
      "image" => [image_url],
      "inLanguage" => PublicLocales.language_tag(post.locale),
      "keywords" => post.tags,
      "mainEntityOfPage" => %{"@id" => canonical_url, "@type" => "WebPage"},
      "publisher" => %{
        "@type" => "Organization",
        "logo" => %{
          "@type" => "ImageObject",
          "url" => Layouts.absolute_url(~p"/images/logos/favicon-192.png")
        },
        "name" => "Storyarn",
        "url" => organization_url
      },
      "url" => canonical_url
    }
  end
end
