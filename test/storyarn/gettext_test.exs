defmodule Storyarn.GettextTest do
  use ExUnit.Case, async: true

  @spanish_default_error_messages %{
    "Export is too large" => "La exportación es demasiado grande",
    "Invalid localization policy" => "Política de localización no válida",
    "Media not found" => "Archivo multimedia no encontrado"
  }

  test "Spanish default error messages are translated" do
    Gettext.with_locale(Storyarn.Gettext, "es", fn ->
      Enum.each(@spanish_default_error_messages, fn {message, translation} ->
        assert Gettext.dgettext(Storyarn.Gettext, "default", message) == translation
      end)
    end)
  end
end
