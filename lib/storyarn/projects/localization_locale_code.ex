defmodule Storyarn.Projects.LocalizationLocaleCode do
  @moduledoc false

  @format ~r/\A[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*\z/
  @max_length 35

  @spec valid?(term()) :: boolean()
  def valid?(locale_code) when is_binary(locale_code) do
    byte_size(locale_code) <= @max_length and Regex.match?(@format, locale_code)
  end

  def valid?(_locale_code), do: false

  @spec normalize(term()) :: term()
  def normalize(locale_code) when is_binary(locale_code), do: String.downcase(locale_code)
  def normalize(locale_code), do: locale_code

  @spec ensure_safe!(term()) :: String.t()
  def ensure_safe!(locale_code) do
    if valid?(locale_code) do
      normalize(locale_code)
    else
      raise ArgumentError, "invalid localization locale for export: #{inspect(locale_code)}"
    end
  end

  def format, do: @format
  def max_length, do: @max_length
end
