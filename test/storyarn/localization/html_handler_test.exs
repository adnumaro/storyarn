defmodule Storyarn.Localization.HtmlHandlerTest do
  use ExUnit.Case, async: true

  alias Storyarn.Localization.HtmlHandler

  describe "pre_translate/1" do
    test "wraps variable placeholders in translate-no spans" do
      input = "Hello {player_name}, you have {health} HP"
      result = HtmlHandler.pre_translate(input)

      assert result ==
               ~s(Hello <span translate="no">{player_name}</span>, you have <span translate="no">{health}</span> HP)
    end

    test "preserves text without placeholders" do
      assert HtmlHandler.pre_translate("Hello world") == "Hello world"
    end

    test "handles HTML with placeholders" do
      input = "<p>Welcome, {name}!</p>"
      result = HtmlHandler.pre_translate(input)
      assert result == ~s(<p>Welcome, <span translate="no">{name}</span>!</p>)
    end

    test "handles nil" do
      assert HtmlHandler.pre_translate(nil) == nil
    end
  end

  describe "post_translate/1" do
    test "unwraps translate-no spans around placeholders" do
      input =
        ~s(Hola <span translate="no">{player_name}</span>, tienes <span translate="no">{health}</span> HP)

      result = HtmlHandler.post_translate(input)
      assert result == "Hola {player_name}, tienes {health} HP"
    end

    test "preserves text without wrapped placeholders" do
      assert HtmlHandler.post_translate("Hola mundo") == "Hola mundo"
    end

    test "handles nil" do
      assert HtmlHandler.post_translate(nil) == nil
    end
  end

  describe "html?/1" do
    test "detects HTML content" do
      assert HtmlHandler.html?("<p>Hello</p>")
      assert HtmlHandler.html?("<span class=\"mention\">@Bob</span>")
    end

    test "returns false for plain text" do
      refute HtmlHandler.html?("Hello world")
      refute HtmlHandler.html?("")
    end

    test "returns false for nil" do
      refute HtmlHandler.html?(nil)
    end
  end
end
