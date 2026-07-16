defmodule StoryarnWeb.BlogFormatting do
  @moduledoc false

  use Gettext, backend: Storyarn.Gettext

  def format_date(%Date{} = date, locale) when is_binary(locale) do
    Gettext.with_locale(Storyarn.Gettext, locale, fn ->
      dgettext("blog", "%{month} %{day}, %{year}",
        month: month_name(date.month),
        day: date.day,
        year: date.year
      )
    end)
  end

  defp month_name(1), do: dgettext("blog", "January")
  defp month_name(2), do: dgettext("blog", "February")
  defp month_name(3), do: dgettext("blog", "March")
  defp month_name(4), do: dgettext("blog", "April")
  defp month_name(5), do: dgettext("blog", "May")
  defp month_name(6), do: dgettext("blog", "June")
  defp month_name(7), do: dgettext("blog", "July")
  defp month_name(8), do: dgettext("blog", "August")
  defp month_name(9), do: dgettext("blog", "September")
  defp month_name(10), do: dgettext("blog", "October")
  defp month_name(11), do: dgettext("blog", "November")
  defp month_name(12), do: dgettext("blog", "December")
end
