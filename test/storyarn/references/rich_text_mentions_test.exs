defmodule Storyarn.References.RichTextMentionsTest do
  use ExUnit.Case, async: true

  alias Storyarn.References.RichTextMentions

  describe "html_candidates/1" do
    test "selects actual mention markup without treating ordinary prose as HTML" do
      mention =
        ~s(<p><span class="pill mention selected" data-type="sheet" data-id="42">Target</span></p>)

      value = %{
        "description" => "This sentence mentions a mention without rich-text markup.",
        "nested" => ["<p>A dimension label</p>", %{"content" => mention}]
      }

      assert RichTextMentions.html_candidates(value) == [mention]
    end

    test "keeps malformed mention elements so strict callers can reject them" do
      malformed = ~s(<p><span class="mention" data-type="sheet">Missing target</span></p>)
      unquoted = ~s(<span class=mention data-type="flow" data-id="7">Flow</span>)

      assert RichTextMentions.html_candidates([malformed, unquoted]) == [unquoted, malformed]
    end

    test "recognizes case-insensitive HTML tag and attribute names" do
      mention = ~s(<SPAN CLASS="mention" data-type="sheet" data-id="42">Target</SPAN>)

      assert RichTextMentions.html_candidates(%{"content" => mention}) == [mention]
      assert {:ok, [%{type: "sheet", id: "42"}]} = RichTextMentions.extract_from_html(mention)
    end

    test "recognizes mention classes containing decoded HTML entities" do
      mentions = [
        ~s(<span class="foo&#32;mention" data-type="sheet" data-id="42">Target</span>),
        ~s(<span class="m&#101;ntion" data-type="flow" data-id="7">Target</span>)
      ]

      for mention <- mentions do
        assert {:ok, [_mention]} = RichTextMentions.extract_from_html(mention)
        assert RichTextMentions.html_candidates(%{"content" => mention}) == [mention]
      end
    end

    test "recognizes mentions after a quoted greater-than character" do
      mentions = [
        ~s(<span title="a > b" class="mention" data-type="sheet" data-id="42">Target</span>),
        ~s(<span title="a > b" class="m&#101;ntion" data-type="flow" data-id="7">Target</span>)
      ]

      for mention <- mentions do
        assert {:ok, [_mention]} = RichTextMentions.extract_from_html(mention)
        assert RichTextMentions.html_candidates(%{"content" => mention}) == [mention]
      end
    end

    test "keeps malformed entity-encoded mentions so strict callers can reject them" do
      malformed = ~s(<span class="m&#101;ntion" data-type="sheet">Missing target</span>)

      assert RichTextMentions.html_candidates(%{"content" => malformed}) == [malformed]

      assert {:error, {:invalid_mention, %{type: ["sheet"], id: []}}} =
               RichTextMentions.extract_from_html(malformed)
    end
  end

  describe "extract_from_html/1" do
    test "extracts supported mentions in document order" do
      html =
        ~s(<a class="mention" data-type="sheet" data-id="12">Sheet</a>) <>
          ~s(<mark class="mention" data-type="flow" data-id="34">Flow</mark>)

      assert {:ok, [%{type: "sheet", id: "12"}, %{type: "flow", id: "34"}]} =
               RichTextMentions.extract_from_html(html)
    end

    test "reports malformed and blank mention targets" do
      missing_id = ~s(<span class="mention" data-type="sheet">Missing</span>)
      blank_id = ~s(<span class="mention" data-type="flow" data-id=" ">Blank</span>)

      duplicate_type =
        ~s(<span class="mention" data-type="sheet" data-type="flow" data-id="42">Duplicate</span>)

      assert {:error, {:invalid_mention, %{type: ["sheet"], id: []}}} =
               RichTextMentions.extract_from_html(missing_id)

      assert {:error, {:invalid_mention, %{type: ["flow"], id: [" "]}}} =
               RichTextMentions.extract_from_html(blank_id)

      assert {:error, {:invalid_mention, %{type: ["sheet", "flow"], id: ["42"]}}} =
               RichTextMentions.extract_from_html(duplicate_type)
    end
  end
end
