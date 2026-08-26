defmodule Storyarn.Flows.Versioning.LocaleCode do
  @moduledoc false

  @format ~r/\A[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*\z/
  @max_length 35

  def valid?(locale_code) when is_binary(locale_code) do
    byte_size(locale_code) <= @max_length and Regex.match?(@format, locale_code)
  end

  def valid?(_locale_code), do: false

  def normalize(locale_code) when is_binary(locale_code), do: String.downcase(locale_code)
  def normalize(locale_code), do: locale_code
end
