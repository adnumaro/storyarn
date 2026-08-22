defmodule StoryarnWeb.PublicLanguageMetadata do
  @moduledoc false

  @metadata %{
    "en" => %{native_name: "English", flag_code: "gb", short_label: "EN"},
    "es" => %{native_name: "Español", flag_code: "es", short_label: "ES"}
  }

  @spec get(String.t()) :: map() | nil
  def get(language_tag) when is_binary(language_tag) do
    Map.get(@metadata, String.downcase(language_tag))
  end

  def get(_language_tag), do: nil

  @spec native_name(String.t()) :: String.t()
  def native_name(language_tag) when is_binary(language_tag) do
    case get(language_tag) do
      %{native_name: name} -> name
      nil -> String.upcase(language_tag)
    end
  end

  @spec flag_code(String.t()) :: String.t() | nil
  def flag_code(language_tag) when is_binary(language_tag) do
    case get(language_tag) do
      %{flag_code: code} -> code
      nil -> nil
    end
  end

  @spec short_label(String.t()) :: String.t()
  def short_label(language_tag) when is_binary(language_tag) do
    case get(language_tag) do
      %{short_label: label} -> label
      nil -> language_tag |> String.split("-", parts: 2) |> hd() |> String.slice(0, 2) |> String.upcase()
    end
  end
end
