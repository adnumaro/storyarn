defmodule Storyarn.Publication.PathLocalizer do
  @moduledoc """
  Pure canonicalization for paths on Storyarn's public surface.

  The function deliberately leaves authentication, application, asset,
  external, and fragment-only destinations untouched.
  """

  alias Storyarn.Publication.Locales

  @public_roots ~w(contact privacy terms docs blog)

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
      [root | _rest] -> root in @public_roots
      [] -> true
    end
  end

  defp validate_locale!(locale) do
    if !Locales.valid?(locale) do
      raise ArgumentError, "unsupported public locale: #{inspect(locale)}"
    end
  end
end
