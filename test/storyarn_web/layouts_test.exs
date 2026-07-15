defmodule StoryarnWeb.LayoutsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.Components.AuthLayout
  alias StoryarnWeb.Components.PublicLanguageSwitcher
  alias StoryarnWeb.Layouts

  # ── Helpers ──────────────────────────────────────────────────────────

  defp mock_socket do
    %Phoenix.LiveView.Socket{}
  end

  # ── flash_group/1 ───────────────────────────────────────────────────

  describe "root/1" do
    test "renders brand icon metadata for browsers and search surfaces", %{conn: conn} do
      html =
        rendered_to_string(
          Layouts.root(%{
            conn: conn,
            inner_content: ""
          })
        )

      assert html =~ ~s[href="/favicon.ico"]
      assert html =~ ~s[href="/images/logos/favicon-192.png"]
      assert html =~ ~s[sizes="192x192"]
      assert html =~ ~s[href="/images/logos/apple-touch-icon-180.png"]
      assert html =~ ~s[rel="apple-touch-icon"]
      assert html =~ ~s[href="/site.webmanifest"]
      assert html =~ ~s[name="theme-color"]
      assert html =~ ~s[data-public-default-locale="en"]
      assert html =~ ~s[data-public-locales="en,es"]
    end

    test "serves the web app manifest through static paths" do
      assert "site.webmanifest" in StoryarnWeb.static_paths()
      refute "uploads" in StoryarnWeb.static_paths()
    end
  end

  describe "flash_group/1" do
    test "renders flash group container" do
      html =
        render_component(&Layouts.flash_group/1,
          flash: %{},
          socket: mock_socket(),
          id: "flash-group"
        )

      assert html =~ ~s(id="flash-group")
      assert html =~ ~s(aria-live="polite")
    end

    test "passes current flash messages to Vue" do
      html =
        render_component(&Layouts.flash_group/1,
          flash: %{
            "info" => "Saved",
            "warning" => "Check this",
            "error" => "Failed"
          },
          socket: mock_socket(),
          id: "flash-group"
        )

      vue = LiveVue.Test.get_vue(html, name: "live/layouts/flash/FlashGroup")

      assert vue.props["flash"]["info"] == "Saved"
      assert vue.props["flash"]["warning"] == "Check this"
      assert vue.props["flash"]["error"] == "Failed"
    end

    test "renders client and server error flash elements" do
      html =
        render_component(&Layouts.flash_group/1,
          flash: %{},
          socket: mock_socket(),
          id: "flash-group"
        )

      vue = LiveVue.Test.get_vue(html, name: "live/layouts/flash/FlashGroup")

      assert html =~ "#client-error"
      assert html =~ "#server-error"
      assert vue.props["network"]["clientTitle"] == "We can't find the internet"
      assert vue.props["network"]["serverTitle"] == "Something went wrong!"
    end

    test "renders reconnection messaging" do
      html =
        render_component(&Layouts.flash_group/1,
          flash: %{},
          socket: mock_socket(),
          id: "flash-group"
        )

      vue = LiveVue.Test.get_vue(html, name: "live/layouts/flash/FlashGroup")

      assert vue.props["network"]["reconnecting"] == "Attempting to reconnect"
    end
  end

  describe "public language switcher" do
    test "compact labels expose BCP 47 tags instead of Gettext locale names" do
      html =
        render_component(&PublicLanguageSwitcher.switcher/1,
          id: "regional-language-switcher",
          current_locale: "pt_BR",
          compact: true,
          links: [
            %{
              locale: "pt_BR",
              language_tag: "pt-BR",
              label: "Português (Brasil)",
              path: "/pt-br"
            },
            %{
              locale: "zh_Hant",
              language_tag: "zh-Hant",
              label: "繁體中文",
              path: "/zh-hant"
            }
          ]
        )

      document = LazyHTML.from_fragment(html)
      current = LazyHTML.query(document, "#regional-language-switcher-pt_BR")
      alternative = LazyHTML.query(document, "#regional-language-switcher-zh_Hant")

      assert current |> LazyHTML.text() |> String.trim() == "pt-BR"
      assert alternative |> LazyHTML.text() |> String.trim() == "zh-Hant"
      assert LazyHTML.attribute(alternative, "hreflang") == ["zh-Hant"]
    end
  end

  describe "SEO helpers" do
    test "normalizes explicit canonical paths to absolute URLs" do
      assert Layouts.seo_canonical_url(%{canonical_url: "/blog"}) ==
               Layouts.absolute_url("/blog")
    end

    test "marks authentication and invitation paths as non-indexable" do
      assert Layouts.seo_robots(%{conn: %{request_path: "/users/log-in"}}) == "noindex, follow"

      assert Layouts.seo_robots(%{
               conn: %{request_path: "/projects/invitations/secret-token"}
             }) == "noindex, follow"

      assert Layouts.seo_robots(%{conn: %{request_path: "/es/blog"}}) == nil
    end

    test "auth layout preserves a stronger robots policy" do
      metadata =
        Layouts.live_seo_metadata(%{
          locale: "en",
          seo_robots: "noindex, nofollow"
        })

      html =
        render_component(&AuthLayout.auth/1,
          flash: %{},
          socket: mock_socket(),
          seo_metadata: metadata,
          inner_block: []
        )

      robots =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#live-seo-metadata")
        |> LazyHTML.attribute("data-metadata")
        |> List.first()
        |> Jason.decode!()
        |> Map.fetch!("robots")

      assert robots == "noindex, nofollow"
    end

    test "serializes JSON-LD without allowing a script boundary" do
      headline = "</script><script>alert('xss')</script>"

      assert {:safe, json} = Layouts.seo_json_ld(%{seo_json_ld: %{"headline" => headline}})
      refute json =~ "</script>"
      assert Jason.decode!(json)["headline"] == headline
    end

    test "builds the metadata payload used during LiveView navigation" do
      metadata =
        Layouts.live_seo_metadata(%{
          locale: "en",
          page_title: "Article title",
          seo_description: "Article description",
          canonical_url: "/blog/article",
          seo_type: "article",
          seo_image_url: "https://example.test/article.png",
          seo_published_on: ~D[2026-07-14],
          seo_modified_on: ~D[2026-07-15],
          seo_article_tags: ["Storyarn"],
          seo_robots: "noindex, follow",
          seo_alternate_links: [
            %{hreflang: "en", href: "/blog/article?source=test#top"},
            %{hreflang: "es", href: "/es/blog/articulo"}
          ],
          seo_json_ld: %{"@type" => "BlogPosting"}
        })

      assert metadata.locale == "en"
      assert metadata.title == "Article title"
      assert metadata.canonical_url == Layouts.absolute_url("/blog/article")
      assert metadata.type == "article"
      assert metadata.published_time == "2026-07-14"
      assert metadata.modified_time == "2026-07-15"
      assert metadata.article_tags == ["Storyarn"]
      assert metadata.robots == "noindex, follow"

      assert metadata.alternate_links == [
               %{hreflang: "en", href: Layouts.absolute_url("/blog/article")},
               %{hreflang: "es", href: Layouts.absolute_url("/es/blog/articulo")}
             ]

      assert metadata.json_ld == %{"@type" => "BlogPosting"}
    end

    test "normalizes and rejects malformed SEO alternate links" do
      assert Layouts.seo_alternate_links(%{
               seo_alternate_links: [
                 %{hreflang: " en ", href: " /blog/article?source=test#top "},
                 %{hreflang: "en", href: "/blog/duplicate"},
                 %{hreflang: "", href: "/es/blog/articulo"},
                 %{hreflang: "es", href: "javascript:alert(1)"},
                 %{hreflang: nil, href: "/fr/blog/article"}
               ]
             }) == [
               %{hreflang: "en", href: Layouts.absolute_url("/blog/article")}
             ]
    end

    test "renders alternate links in the server document head", %{conn: conn} do
      html =
        rendered_to_string(
          Layouts.root(%{
            conn: conn,
            inner_content: "",
            seo_alternate_links: [
              %{hreflang: "en", href: "/blog/article"},
              %{hreflang: "es", href: "/es/blog/articulo"},
              %{hreflang: "x-default", href: "/blog/article"}
            ]
          })
        )

      document = LazyHTML.from_document(html)

      assert LazyHTML.attribute(
               LazyHTML.query(document, ~s|link[rel="alternate"][hreflang="es"]|),
               "href"
             ) == [Layouts.absolute_url("/es/blog/articulo")]

      assert LazyHTML.attribute(
               LazyHTML.query(document, ~s|link[rel="alternate"][hreflang="en"]|),
               "href"
             ) == [Layouts.absolute_url("/blog/article")]

      assert LazyHTML.attribute(
               LazyHTML.query(document, ~s|link[rel="alternate"][hreflang="x-default"]|),
               "href"
             ) == [Layouts.absolute_url("/blog/article")]
    end

    test "renders a hidden SEO hook with JSON metadata" do
      metadata = %{locale: "en", title: "Storyarn Journal", type: "website"}
      html = render_component(&Layouts.live_seo/1, metadata: metadata)
      document = LazyHTML.from_fragment(html)
      hook = LazyHTML.query(document, "#live-seo-metadata")

      assert LazyHTML.attribute(hook, "phx-hook") == ["SeoMetadata"]
      assert LazyHTML.attribute(hook, "hidden") == [""]

      assert hook
             |> LazyHTML.attribute("data-metadata")
             |> List.first()
             |> Jason.decode!() == %{
               "locale" => "en",
               "title" => "Storyarn Journal",
               "type" => "website"
             }
    end
  end
end
