defmodule StoryarnWeb.PublicURLsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Blog
  alias StoryarnWeb.BlogURLs
  alias StoryarnWeb.Layouts
  alias StoryarnWeb.PublicURLs

  describe "canonical public paths" do
    test "keeps English unprefixed and prefixes Spanish" do
      assert PublicURLs.home_path("en") == "/"
      assert PublicURLs.home_path("es") == "/es"
      assert PublicURLs.contact_path("en") == "/contact"
      assert PublicURLs.contact_path("es") == "/es/contact"
      assert PublicURLs.privacy_path("es") == "/es/privacy"
      assert PublicURLs.terms_path("es") == "/es/terms"
      assert PublicURLs.docs_index_path("es") == "/es/docs"
      assert PublicURLs.blog_index_path("es") == "/es/blog"
    end

    test "builds documentation paths from content fields" do
      assert PublicURLs.docs_path("en", "world-building", ["sheets", "overview"]) ==
               "/docs/world-building/sheets/overview"

      assert PublicURLs.docs_path("es", "world-building", "sheets/overview") ==
               "/es/docs/world-building/sheets/overview"

      assert PublicURLs.docs_path(%{
               locale: "es",
               category: "welcome",
               path: ["start-here"]
             }) == "/es/docs/welcome/start-here"
    end

    test "builds post paths from either fields or an article" do
      post = Blog.get_post("introducing-storyarn", "en")

      assert PublicURLs.blog_post_path("en", "introducing-storyarn") ==
               "/blog/introducing-storyarn"

      assert PublicURLs.blog_post_path("es", "presentamos-storyarn") ==
               "/es/blog/presentamos-storyarn"

      assert PublicURLs.blog_post_path(post) == "/blog/introducing-storyarn"
    end

    test "rejects locales that are not published publicly" do
      assert_raise ArgumentError, ~r/unsupported public locale/, fn ->
        PublicURLs.contact_path("fr")
      end
    end

    test "blog navigation falls back until a locale has published posts" do
      assert BlogURLs.index_path("fr") == "/blog"
    end

    test "hands the current public locale to non-indexable auth destinations" do
      assert PublicURLs.locale_handoff_path("/users/register", "es") ==
               "/users/register?locale=es"

      assert PublicURLs.locale_handoff_path("/users/log-in?return_to=%2Fworkspaces#form", "en") ==
               "/users/log-in?locale=en&return_to=%2Fworkspaces#form"
    end
  end

  describe "locale detection" do
    test "recognizes every canonical public surface" do
      for path <- ["/", "/contact", "/privacy", "/terms", "/docs", "/docs/welcome/start-here", "/blog"] do
        assert PublicURLs.locale_from_path(path) == "en"
      end

      for path <- [
            "/es",
            "/es/contact",
            "/es/privacy",
            "/es/terms",
            "/es/docs/welcome/start-here",
            "/es/blog/presentamos-storyarn"
          ] do
        assert PublicURLs.locale_from_path(path) == "es"
      end
    end

    test "does not claim auth, invitation, private, or default-locale alias paths" do
      for path <- [
            "/users/log-in",
            "/projects/invitations/token",
            "/workspaces/example",
            "/en",
            "/en/docs/welcome/start-here"
          ] do
        assert PublicURLs.locale_from_path(path) == nil
      end
    end

    test "ignores query and fragment when reading a URI" do
      assert PublicURLs.locale_from_uri("https://storyarn.com/es/docs?from=blog#top") == "es"
      assert PublicURLs.locale_from_uri("/blog?utm_source=test") == "en"
    end
  end

  describe "localize_path/2" do
    test "adds, replaces, and removes locale prefixes" do
      assert PublicURLs.localize_path("/docs/welcome/start-here", "es") ==
               "/es/docs/welcome/start-here"

      assert PublicURLs.localize_path("/es/docs/welcome/start-here", "en") ==
               "/docs/welcome/start-here"

      assert PublicURLs.localize_path("/en/docs/welcome/start-here", "es") ==
               "/es/docs/welcome/start-here"

      assert PublicURLs.localize_path("/", "es") == "/es"
      assert PublicURLs.localize_path("/es", "en") == "/"
    end

    test "preserves query strings and fragments" do
      assert PublicURLs.localize_path("/docs/search?q=flow%20node#results", "es") ==
               "/es/docs/search?q=flow%20node#results"

      assert PublicURLs.localize_path("/es/blog?ref=header#latest", "en") ==
               "/blog?ref=header#latest"
    end

    test "does not localize private, auth, asset, external, or anchor-only destinations" do
      for path <- [
            "/users/log-in?return_to=%2Fworkspaces",
            "/workspaces/example",
            "/images/logo.svg",
            "https://example.com/docs",
            "//cdn.example.com/image.webp",
            "#features"
          ] do
        assert PublicURLs.localize_path(path, "es") == path
      end
    end
  end

  describe "language relationships" do
    test "builds language switcher links with native labels" do
      assert PublicURLs.language_links([{"en", "/contact"}, {"es", "/es/contact"}]) == [
               %{locale: "en", language_tag: "en", label: "English", path: "/contact"},
               %{locale: "es", language_tag: "es", label: "Español", path: "/es/contact"}
             ]
    end

    test "builds reciprocal absolute alternates and x-default" do
      assert PublicURLs.alternate_links([{"en", "/contact"}, {"es", "/es/contact"}]) == [
               %{hreflang: "en", href: Layouts.absolute_url("/contact")},
               %{hreflang: "es", href: Layouts.absolute_url("/es/contact")},
               %{hreflang: "x-default", href: Layouts.absolute_url("/contact")}
             ]
    end

    test "omits x-default when no default translation exists" do
      assert PublicURLs.alternate_links([{"es", "/es/contact"}]) == [
               %{hreflang: "es", href: Layouts.absolute_url("/es/contact")}
             ]
    end
  end
end
