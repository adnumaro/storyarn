defmodule Storyarn.Publication.Locales do
  @moduledoc """
  Published locales for Storyarn's indexable public surface.

  A descriptor keeps the Gettext catalog name separate from the BCP 47 tag
  used by HTML and SEO and from the canonical URL segment. This matters for
  regional locales such as a `pt_BR` Gettext catalog published as `pt-BR`.

  Public locales are deliberately independent from languages available inside
  the authenticated product. Adding a product locale must not expose an
  incomplete landing page, documentation set, or editorial surface.
  """

  @type descriptor :: %{
          gettext_locale: String.t(),
          language_tag: String.t(),
          path_segment: String.t()
        }

  @config Application.compile_env(:storyarn, __MODULE__, [])
  @default_locale Keyword.fetch!(@config, :default_locale)
  @descriptors Keyword.fetch!(@config, :locales)
  @gettext_locales Gettext.known_locales(Storyarn.Gettext)
  @language_tag_pattern ~r/^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/
  @path_segment_pattern ~r/^[A-Za-z0-9]{2,8}(?:-[A-Za-z0-9]{2,8})*$/

  if !Enum.all?(@descriptors, fn descriptor ->
       is_map(descriptor) and
         Enum.all?([:gettext_locale, :language_tag, :path_segment], fn key ->
           is_binary(Map.get(descriptor, key)) and Map.get(descriptor, key) != ""
         end)
     end) do
    raise ArgumentError,
          "public locale descriptors require :gettext_locale, :language_tag, and :path_segment strings"
  end

  @locales Enum.map(@descriptors, & &1.gettext_locale)
  @language_tags Enum.map(@descriptors, & &1.language_tag)
  @path_segments Enum.map(@descriptors, & &1.path_segment)

  if @default_locale not in @locales do
    raise ArgumentError,
          "public default locale #{inspect(@default_locale)} must be included in :locales"
  end

  for {values, label} <- [
        {@locales, "Gettext locales"},
        {Enum.map(@language_tags, &String.downcase/1), "language tags"},
        {Enum.map(@path_segments, &String.downcase/1), "path segments"}
      ],
      length(Enum.uniq(values)) != length(values) do
    raise ArgumentError, "public locale #{label} must be unique"
  end

  if !Enum.all?(@language_tags, &Regex.match?(@language_tag_pattern, &1)) do
    raise ArgumentError, "public locale language tags must be valid BCP 47-style tags"
  end

  if !Enum.all?(@path_segments, &Regex.match?(@path_segment_pattern, &1)) do
    raise ArgumentError, "public locale path segments contain unsupported characters"
  end

  case @locales -- @gettext_locales do
    [] ->
      :ok

    unsupported ->
      raise ArgumentError,
            "public locales must also be configured in Gettext, unsupported: #{inspect(unsupported)}"
  end

  @by_locale Map.new(@descriptors, &{&1.gettext_locale, &1})
  @by_path_segment Map.new(@descriptors, &{String.downcase(&1.path_segment), &1.gettext_locale})

  @doc "The Gettext locale used by canonical public URLs without a prefix."
  @spec default_locale() :: String.t()
  def default_locale, do: @default_locale

  @doc "Every Gettext locale with a complete, indexable public surface."
  @spec locales() :: [String.t()]
  def locales, do: @locales

  @doc "Full public locale descriptors in configured display order."
  @spec descriptors() :: [descriptor()]
  def descriptors, do: @descriptors

  @doc "Published locales that use a URL prefix."
  @spec localized_locales() :: [String.t()]
  def localized_locales, do: @locales -- [@default_locale]

  @doc "Route pairs as `{gettext_locale, path_segment}` for prefixed locales."
  @spec localized_routes() :: [{String.t(), String.t()}]
  def localized_routes do
    @descriptors
    |> Enum.reject(&(&1.gettext_locale == @default_locale))
    |> Enum.map(&{&1.gettext_locale, &1.path_segment})
  end

  @doc "Whether a Gettext locale is published on the public site."
  @spec valid?(term()) :: boolean()
  def valid?(locale), do: locale in @locales

  @doc "Returns a published locale, falling back to the public default."
  @spec normalize(term()) :: String.t()
  def normalize(locale) do
    if valid?(locale), do: locale, else: @default_locale
  end

  @doc "Returns the BCP 47 language tag for a locale."
  @spec language_tag(String.t()) :: String.t()
  def language_tag(locale) when is_binary(locale) do
    case Map.get(@by_locale, locale) do
      %{language_tag: language_tag} -> language_tag
      nil -> String.replace(locale, "_", "-")
    end
  end

  @doc "Returns the configured canonical path segment for a public locale."
  @spec path_segment(String.t()) :: String.t()
  def path_segment(locale) do
    @by_locale |> Map.fetch!(locale) |> Map.fetch!(:path_segment)
  end

  @doc "Resolves a configured URL segment to its Gettext locale."
  @spec locale_from_path_segment(term()) :: String.t() | nil
  def locale_from_path_segment(segment) when is_binary(segment) do
    Map.get(@by_path_segment, String.downcase(segment))
  end

  def locale_from_path_segment(_segment), do: nil

  @doc "Resolves only canonical prefixed URL segments, excluding the default alias."
  @spec localized_locale_from_path_segment(term()) :: String.t() | nil
  def localized_locale_from_path_segment(segment) do
    case locale_from_path_segment(segment) do
      @default_locale -> nil
      locale -> locale
    end
  end
end
