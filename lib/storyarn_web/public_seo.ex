defmodule StoryarnWeb.PublicSEO do
  @moduledoc false

  alias Storyarn.Publication.Locales, as: PublicLocales
  alias StoryarnWeb.Layouts
  alias StoryarnWeb.PublicURLs

  def static_page_metadata(locale, page, title, description) do
    paths = Enum.map(PublicLocales.locales(), &{&1, page_path(page, &1)})
    canonical_url = page |> page_path(locale) |> Layouts.absolute_url()

    %{
      locale: locale,
      page_title: title,
      canonical_url: canonical_url,
      seo_description: description,
      seo_alternate_links: PublicURLs.alternate_links(paths),
      language_links: PublicURLs.language_links(paths),
      seo_json_ld: web_page_json_ld(locale, title, description, canonical_url)
    }
  end

  defp page_path(:home, locale), do: PublicURLs.home_path(locale)
  defp page_path(:contact, locale), do: PublicURLs.contact_path(locale)
  defp page_path(:privacy, locale), do: PublicURLs.privacy_path(locale)
  defp page_path(:terms, locale), do: PublicURLs.terms_path(locale)

  defp web_page_json_ld(locale, title, description, canonical_url) do
    %{
      "@context" => "https://schema.org",
      "@type" => "WebPage",
      "description" => description,
      "inLanguage" => PublicLocales.language_tag(locale),
      "isPartOf" => %{
        "@type" => "WebSite",
        "name" => "Storyarn",
        "url" => Layouts.absolute_url(PublicURLs.home_path(PublicLocales.default_locale()))
      },
      "name" => title,
      "url" => canonical_url
    }
  end
end
