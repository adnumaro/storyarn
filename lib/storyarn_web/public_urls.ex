defmodule StoryarnWeb.PublicURLs do
  @moduledoc """
  Canonical paths and language relationships for Storyarn's public pages.

  The default locale keeps the existing unprefixed URLs. Every other public
  locale receives a stable prefix, so one URL always renders one language.
  The access pages (log-in, registration, password reset, invitations) follow
  the same rule; they are not indexable, but their language is still the path.
  """

  alias Storyarn.Public.Publication.Locales, as: PublicLocales
  alias Storyarn.Public.Publication.PathLocalizer
  alias StoryarnWeb.Layouts
  alias StoryarnWeb.PublicLanguageMetadata

  @spec home_path(String.t()) :: String.t()
  def home_path(locale \\ PublicLocales.default_locale()), do: localized_path(locale, "/")

  @spec contact_path(String.t()) :: String.t()
  def contact_path(locale \\ PublicLocales.default_locale()), do: localized_path(locale, "/contact")

  @spec privacy_path(String.t()) :: String.t()
  def privacy_path(locale \\ PublicLocales.default_locale()), do: localized_path(locale, "/privacy")

  @spec terms_path(String.t()) :: String.t()
  def terms_path(locale \\ PublicLocales.default_locale()), do: localized_path(locale, "/terms")

  @spec docs_index_path(String.t()) :: String.t()
  def docs_index_path(locale \\ PublicLocales.default_locale()), do: localized_path(locale, "/docs")

  @spec docs_path(map()) :: String.t()
  def docs_path(%{locale: locale} = guide), do: docs_path(locale, guide)

  def docs_path(%{category: category, path: path}), do: docs_path(PublicLocales.default_locale(), category, path)

  @spec docs_path(String.t(), map()) :: String.t()
  def docs_path(locale, %{category: category, path: path}), do: docs_path(locale, category, path)

  @spec docs_path(String.t(), String.t()) :: String.t()
  def docs_path(category, path), do: docs_path(PublicLocales.default_locale(), category, path)

  @spec docs_path(String.t(), String.t(), String.t() | [String.t()]) :: String.t()
  def docs_path(locale, category, path) do
    suffix = path |> path_segments() |> Enum.join("/")
    localized_path(locale, "/docs/#{trim_segment(category)}/#{suffix}")
  end

  @doc "Returns the canonical blog index for a public locale."
  @spec blog_index_path(String.t()) :: String.t()
  def blog_index_path(locale \\ PublicLocales.default_locale()), do: localized_path(locale, "/blog")

  @spec blog_post_path(map()) :: String.t()
  def blog_post_path(%{locale: locale, slug: slug}), do: blog_post_path(locale, slug)

  @spec blog_post_path(String.t(), String.t()) :: String.t()
  def blog_post_path(locale, slug), do: localized_path(locale, "/blog/#{trim_segment(slug)}")

  @doc "The published locale for a Gettext locale; unpublished ones use the public default."
  @spec public_locale(term()) :: String.t()
  defdelegate public_locale(locale), to: PublicLocales, as: :normalize

  @spec login_path(String.t()) :: String.t()
  def login_path(locale \\ PublicLocales.default_locale()), do: localized_path(locale, "/users/log-in")

  @doc "Public registration, optionally carrying query parameters such as a chosen plan."
  @spec registration_path(String.t(), keyword() | map()) :: String.t()
  def registration_path(locale \\ PublicLocales.default_locale(), query \\ []) do
    locale |> localized_path("/users/register") |> with_query(query)
  end

  @doc "Password setup for an invited account, returning to the invitation afterwards."
  @spec invited_registration_path(String.t(), String.t(), String.t()) :: String.t()
  def invited_registration_path(locale, registration_token, return_to) do
    locale
    |> localized_path("/users/register/#{trim_segment(registration_token)}")
    |> with_query(return_to: return_to)
  end

  @spec reset_password_path(String.t()) :: String.t()
  def reset_password_path(locale \\ PublicLocales.default_locale()), do: localized_path(locale, "/users/reset-password")

  @spec reset_password_path(String.t(), String.t()) :: String.t()
  def reset_password_path(locale, token), do: localized_path(locale, "/users/reset-password/#{trim_segment(token)}")

  @spec workspace_invitation_path(String.t(), String.t()) :: String.t()
  def workspace_invitation_path(locale, token),
    do: localized_path(locale, "/workspaces/invitations/#{trim_segment(token)}")

  @spec project_invitation_path(String.t(), String.t()) :: String.t()
  def project_invitation_path(locale, token), do: localized_path(locale, "/projects/invitations/#{trim_segment(token)}")

  @doc "Extracts a public locale from a URI. Non-public paths return nil."
  @spec locale_from_uri(String.t() | URI.t()) :: String.t() | nil
  def locale_from_uri(%URI{path: path}), do: locale_from_path(path || "")

  def locale_from_uri(uri) when is_binary(uri) do
    uri
    |> URI.parse()
    |> locale_from_uri()
  end

  def locale_from_uri(_uri), do: nil

  @doc "Extracts the authoritative locale from a canonical public path."
  @spec locale_from_path(String.t()) :: String.t() | nil
  def locale_from_path(path) when is_binary(path) do
    case String.split(path, "/", trim: true) do
      [] -> PublicLocales.default_locale()
      [segment | rest] -> locale_from_prefix(PublicLocales.localized_locale_from_path_segment(segment), path, rest)
    end
  end

  def locale_from_path(_path), do: nil

  # An unprefixed path is the default locale when it belongs to the public
  # surface; a prefixed one only when what follows the prefix does.
  defp locale_from_prefix(nil, path, _rest) do
    if PathLocalizer.localizable?(path), do: PublicLocales.default_locale()
  end

  defp locale_from_prefix(locale, _path, []), do: locale

  defp locale_from_prefix(locale, _path, rest) do
    if PathLocalizer.localizable?(Enum.join(rest, "/")), do: locale
  end

  @doc """
  Moves a local path to the requested locale while preserving query and fragment.

  Existing public locale prefixes are replaced, including the non-canonical
  default prefix used by redirect aliases.
  """
  @spec localize_path(String.t(), String.t()) :: String.t()
  defdelegate localize_path(path, locale), to: PathLocalizer, as: :localize

  @doc "Whether a path, prefixed or not, is an access page whose language is the visitor's preference."
  @spec access_path?(String.t()) :: boolean()
  def access_path?(path) when is_binary(path), do: path |> PathLocalizer.unprefixed() |> PathLocalizer.access_path?()

  @doc "Removes a leading public locale segment from a path."
  @spec unprefixed_path(String.t()) :: String.t()
  defdelegate unprefixed_path(path), to: PathLocalizer, as: :unprefixed

  @doc "Builds language-switcher entries from `{locale, path}` pairs."
  @spec language_links([{String.t(), String.t()}]) :: [map()]
  def language_links(locale_paths) when is_list(locale_paths) do
    Enum.map(locale_paths, fn {locale, path} ->
      locale = validate_locale!(locale)
      language_tag = PublicLocales.language_tag(locale)

      %{
        locale: locale,
        language_tag: language_tag,
        label: PublicLanguageMetadata.native_name(language_tag),
        path: path
      }
    end)
  end

  @doc "Builds absolute reciprocal hreflang entries, including x-default."
  @spec alternate_links([{String.t(), String.t()}]) :: [map()]
  def alternate_links(locale_paths) when is_list(locale_paths) do
    links = language_links(locale_paths)

    alternates =
      Enum.map(links, fn link ->
        %{hreflang: link.language_tag, href: Layouts.absolute_url(link.path)}
      end)

    case Enum.find(links, &(&1.locale == PublicLocales.default_locale())) do
      nil -> alternates
      default -> alternates ++ [%{hreflang: "x-default", href: Layouts.absolute_url(default.path)}]
    end
  end

  defp localized_path(locale, path), do: PathLocalizer.localized_path(locale, path)

  defp path_segments(path) when is_list(path), do: Enum.map(path, &trim_segment/1)

  defp path_segments(path) when is_binary(path) do
    path
    |> String.split("/", trim: true)
    |> Enum.map(&trim_segment/1)
  end

  defp trim_segment(segment) when is_binary(segment), do: String.trim(segment, "/")

  defp validate_locale!(locale) do
    if PublicLocales.valid?(locale) do
      locale
    else
      raise ArgumentError, "unsupported public locale: #{inspect(locale)}"
    end
  end

  defp with_query(path, []), do: path
  defp with_query(path, query) when query == %{}, do: path
  defp with_query(path, query), do: path <> "?" <> URI.encode_query(query)
end
