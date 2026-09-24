defmodule Storyarn.Public.Publication.PathLocalizer do
  @moduledoc """
  Pure canonicalization for paths on Storyarn's public surface.

  The public surface is the indexable content (landing, contact, legal, docs,
  blog) plus the access pages a visitor reaches before signing in: log-in,
  registration, password reset and invitations. Both carry their language in
  the path. Application, asset, external, and fragment-only destinations are
  left untouched.
  """

  alias Storyarn.Public.Publication.Locales

  @public_roots ~w(contact privacy terms docs blog)
  @access_roots [
    ~w(users log-in),
    ~w(users register),
    ~w(users reset-password),
    ~w(projects invitations),
    ~w(workspaces invitations)
  ]

  @spec localize(String.t(), String.t()) :: String.t()
  def localize(path, locale) when is_binary(path) do
    validate_locale!(locale)
    uri = URI.parse(path)

    with nil <- uri.scheme,
         nil <- uri.host,
         uri_path when uri_path not in [nil, ""] <- uri.path,
         unprefixed = uri_path |> ensure_leading_slash() |> strip_locale_prefix(),
         true <- public_path?(unprefixed) do
      URI.to_string(%URI{
        path: localized_path(locale, unprefixed),
        query: uri.query,
        fragment: uri.fragment
      })
    else
      _other -> path
    end
  end

  @doc "Whether an unprefixed path belongs to the public surface and carries a locale prefix."
  @spec localizable?(String.t()) :: boolean()
  def localizable?(path) when is_binary(path), do: path |> ensure_leading_slash() |> public_path?()

  @doc "Whether an unprefixed path is an access page: log-in, registration, password reset or an invitation."
  @spec access_path?(String.t()) :: boolean()
  def access_path?(path) when is_binary(path), do: path |> String.split("/", trim: true) |> access_segments?()

  @doc "Removes a leading public locale segment, including the default alias."
  @spec unprefixed(String.t()) :: String.t()
  def unprefixed(path) when is_binary(path), do: path |> ensure_leading_slash() |> strip_locale_prefix()

  @spec localized_path(String.t(), String.t()) :: String.t()
  def localized_path(locale, path) when is_binary(path) do
    validate_locale!(locale)

    if locale == Locales.default_locale() do
      path
    else
      "/#{Locales.path_segment(locale)}" <> if(path == "/", do: "", else: path)
    end
  end

  defp strip_locale_prefix(path) do
    path
    |> String.split("/", trim: true)
    |> strip_locale_segments(path)
  end

  defp strip_locale_segments([segment | rest], original_path) do
    case Locales.locale_from_path_segment(segment) do
      nil -> original_path
      _locale -> join_path_segments(rest)
    end
  end

  defp strip_locale_segments([], _original_path), do: "/"

  defp join_path_segments([]), do: "/"
  defp join_path_segments(segments), do: "/" <> Enum.join(segments, "/")

  defp ensure_leading_slash("/" <> _rest = path), do: path
  defp ensure_leading_slash(path), do: "/" <> path

  defp public_path?("/"), do: true

  defp public_path?(path) do
    case String.split(path, "/", trim: true) do
      [root | _rest] = segments -> root in @public_roots or access_segments?(segments)
      [] -> true
    end
  end

  defp access_segments?(segments), do: Enum.any?(@access_roots, &List.starts_with?(segments, &1))

  defp validate_locale!(locale) do
    if !Locales.valid?(locale) do
      raise ArgumentError, "unsupported public locale: #{inspect(locale)}"
    end
  end
end
