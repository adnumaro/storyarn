defmodule Storyarn.Localization.LocaleCode do
  @moduledoc """
  Validates locale identifiers used by localization storage and export filenames.

  Storyarn accepts the BCP 47 subset used by its language catalog: a two or
  three letter language subtag followed by optional 2-8 character alphanumeric
  subtags. Restricting the alphabet also guarantees that a locale is a safe
  filename component.
  """

  @format ~r/\A[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*\z/
  @max_length 35

  @spec valid?(term()) :: boolean()
  def valid?(locale_code) when is_binary(locale_code) do
    byte_size(locale_code) <= @max_length and Regex.match?(@format, locale_code)
  end

  def valid?(_locale_code), do: false

  @spec ensure_safe!(term()) :: String.t()
  def ensure_safe!(locale_code) do
    if valid?(locale_code) do
      locale_code
    else
      raise ArgumentError, "invalid localization locale for export: #{inspect(locale_code)}"
    end
  end

  @spec format() :: Regex.t()
  def format, do: @format

  @spec max_length() :: pos_integer()
  def max_length, do: @max_length
end
