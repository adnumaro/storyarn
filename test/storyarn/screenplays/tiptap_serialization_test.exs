defmodule Storyarn.Screenplays.TiptapSerializationTest do
  use ExUnit.Case, async: true

  alias Storyarn.Screenplays.TiptapSerialization

  # Helper to build a minimal element struct-like map
  defp element(attrs) do
    %{
      id: attrs[:id],
      type: attrs[:type] || "action",
      position: attrs[:position] || 0,
      content: attrs[:content] || "",
      data: attrs[:data] || %{}
    }
  end

  # -- server_type_to_tiptap/1 ------------------------------------------------

  describe "server_type_to_tiptap/1" do
    test "converts all known types" do
      conversions = %{
        "scene_heading" => "sceneHeading",
        "action" => "action",
        "character" => "character",
        "dialogue" => "dialogue",
        "parenthetical" => "parenthetical",
        "transition" => "transition",
        "note" => "note",
        "section" => "section",
        "page_break" => "pageBreak",
        "dual_dialogue" => "dualDialogue",
        "conditional" => "conditional",
        "instruction" => "instruction",
        "response" => "response",
        "hub_marker" => "hubMarker",
        "jump_marker" => "jumpMarker",
        "title_page" => "titlePage"
      }

      for {server, tiptap} <- conversions do
        assert TiptapSerialization.server_type_to_tiptap(server) == tiptap,
               "Expected #{server} -> #{tiptap}"
      end
    end

    test "returns input for unknown types" do
      assert TiptapSerialization.server_type_to_tiptap("custom_widget") == "custom_widget"
    end
  end

  # -- tiptap_type_to_server/1 ------------------------------------------------

  describe "tiptap_type_to_server/1" do
    test "converts all known types" do
      conversions = %{
        "sceneHeading" => "scene_heading",
        "action" => "action",
        "character" => "character",
        "dialogue" => "dialogue",
        "parenthetical" => "parenthetical",
        "transition" => "transition",
        "note" => "note",
        "section" => "section",
        "pageBreak" => "page_break",
        "dualDialogue" => "dual_dialogue",
        "conditional" => "conditional",
        "instruction" => "instruction",
        "response" => "response",
        "hubMarker" => "hub_marker",
        "jumpMarker" => "jump_marker",
        "titlePage" => "title_page"
      }

      for {tiptap, server} <- conversions do
        assert TiptapSerialization.tiptap_type_to_server(tiptap) == server,
               "Expected #{tiptap} -> #{server}"
      end
    end

    test "returns input for unknown types" do
      assert TiptapSerialization.tiptap_type_to_server("customWidget") == "customWidget"
    end
  end

  # -- elements_to_doc/1 ------------------------------------------------------

  describe "elements_to_doc/1" do
    test "empty list produces doc with single empty action node" do
      doc = TiptapSerialization.elements_to_doc([])

      assert doc["type"] == "doc"
      assert length(doc["content"]) == 1

      [node] = doc["content"]
      assert node["type"] == "action"
      assert node["content"] == []
      assert node["attrs"]["elementId"] == nil
    end

    test "converts a single text element" do
      doc =
        TiptapSerialization.elements_to_doc([element(id: 1, type: "action", content: "Hello")])

      assert doc["type"] == "doc"
      [node] = doc["content"]
      assert node["type"] == "action"
      assert node["attrs"]["elementId"] == 1
      assert node["content"] == [%{"type" => "text", "text" => "Hello"}]
    end

    test "preserves element order by position" do
      elements = [
        element(id: 3, type: "dialogue", content: "Third", position: 2),
        element(id: 1, type: "scene_heading", content: "First", position: 0),
        element(id: 2, type: "action", content: "Second", position: 1)
      ]

      doc = TiptapSerialization.elements_to_doc(elements)
      types = Enum.map(doc["content"], & &1["type"])

      assert types == ["sceneHeading", "action", "dialogue"]
    end

    test "converts each text element type correctly" do
      text_types =
        ~w(scene_heading action character dialogue parenthetical transition note section)

      expected = ~w(sceneHeading action character dialogue parenthetical transition note section)

      elements =
        text_types
        |> Enum.with_index()
        |> Enum.map(fn {type, idx} -> element(id: idx + 1, type: type, position: idx) end)

      doc = TiptapSerialization.elements_to_doc(elements)
      types = Enum.map(doc["content"], & &1["type"])

      assert types == expected
    end

    test "converts atom element types correctly (no content)" do
      atom_types =
        ~w(page_break conditional instruction response dual_dialogue hub_marker jump_marker title_page)

      elements =
        atom_types
        |> Enum.with_index()
        |> Enum.map(fn {type, idx} -> element(id: idx + 100, type: type, position: idx) end)

      doc = TiptapSerialization.elements_to_doc(elements)

      for node <- doc["content"] do
        refute Map.has_key?(node, "content"), "Atom node #{node["type"]} should not have content"
        assert node["attrs"]["elementId"] != nil
      end
    end

    test "preserves element ID in attrs" do
      doc = TiptapSerialization.elements_to_doc([element(id: 42, type: "action")])
      [node] = doc["content"]

      assert node["attrs"]["elementId"] == 42
    end

    test "preserves element data in attrs" do
      data = %{"sheet_id" => 7, "custom" => "value"}
      doc = TiptapSerialization.elements_to_doc([element(id: 1, type: "character", data: data)])
      [node] = doc["content"]

      assert node["attrs"]["data"] == data
    end

    test "character with sheet_id includes sheetId attr" do
      data = %{"sheet_id" => 42}

      doc =
        TiptapSerialization.elements_to_doc([
          element(id: 1, type: "character", content: "DETECTIVE", data: data)
        ])

      [node] = doc["content"]
      assert node["attrs"]["sheetId"] == 42
    end

    test "character without sheet_id omits sheetId attr" do
      doc =
        TiptapSerialization.elements_to_doc([
          element(id: 1, type: "character", content: "DETECTIVE", data: %{})
        ])

      [node] = doc["content"]
      refute Map.has_key?(node["attrs"], "sheetId")
    end

    test "handles nil content gracefully" do
      doc = TiptapSerialization.elements_to_doc([element(id: 1, type: "action", content: nil)])
      [node] = doc["content"]

      assert node["content"] == []
    end

    test "handles empty string content" do
      doc = TiptapSerialization.elements_to_doc([element(id: 1, type: "action", content: "")])
      [node] = doc["content"]

      assert node["content"] == []
    end

    test "handles nil data gracefully" do
      doc = TiptapSerialization.elements_to_doc([element(id: 1, type: "action", data: nil)])
      [node] = doc["content"]

      assert node["attrs"]["data"] == %{}
    end

    test "mixed text and atom nodes" do
      elements = [
        element(id: 1, type: "scene_heading", content: "INT. OFFICE - DAY", position: 0),
        element(id: 2, type: "action", content: "The door opens.", position: 1),
        element(id: 3, type: "page_break", position: 2),
        element(id: 4, type: "character", content: "JOHN", position: 3),
        element(id: 5, type: "conditional", data: %{"condition" => %{}}, position: 4)
      ]

      doc = TiptapSerialization.elements_to_doc(elements)

      assert length(doc["content"]) == 5

      # Text nodes have content
      assert doc["content"] |> Enum.at(0) |> Map.has_key?("content")
      assert doc["content"] |> Enum.at(1) |> Map.has_key?("content")
      assert doc["content"] |> Enum.at(3) |> Map.has_key?("content")

      # Atom nodes do not
      refute doc["content"] |> Enum.at(2) |> Map.has_key?("content")
      refute doc["content"] |> Enum.at(4) |> Map.has_key?("content")
    end
  end

  # -- doc_to_element_attrs/1 -------------------------------------------------

  describe "doc_to_element_attrs/1" do
    test "extracts type, position, content, data, element_id" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "sceneHeading",
            "attrs" => %{"elementId" => 1, "data" => %{"custom" => true}},
            "content" => [%{"type" => "text", "text" => "INT. OFFICE - DAY"}]
          }
        ]
      }

      [attrs] = TiptapSerialization.doc_to_element_attrs(doc)

      assert attrs.type == "scene_heading"
      assert attrs.position == 0
      assert attrs.content == "INT. OFFICE - DAY"
      assert attrs.data == %{"custom" => true}
      assert attrs.element_id == 1
    end

    test "handles atom nodes (no content)" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "pageBreak",
            "attrs" => %{"elementId" => 5, "data" => %{}}
          }
        ]
      }

      [attrs] = TiptapSerialization.doc_to_element_attrs(doc)

      assert attrs.type == "page_break"
      assert attrs.content == ""
      assert attrs.element_id == 5
    end

    test "handles empty doc" do
      assert TiptapSerialization.doc_to_element_attrs(%{"type" => "doc", "content" => []}) == []
    end

    test "handles invalid doc" do
      assert TiptapSerialization.doc_to_element_attrs(%{}) == []
      assert TiptapSerialization.doc_to_element_attrs(nil) == []
    end

    test "preserves position index" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "action",
            "attrs" => %{},
            "content" => [%{"type" => "text", "text" => "A"}]
          },
          %{
            "type" => "dialogue",
            "attrs" => %{},
            "content" => [%{"type" => "text", "text" => "B"}]
          },
          %{
            "type" => "character",
            "attrs" => %{},
            "content" => [%{"type" => "text", "text" => "C"}]
          }
        ]
      }

      attrs_list = TiptapSerialization.doc_to_element_attrs(doc)
      positions = Enum.map(attrs_list, & &1.position)

      assert positions == [0, 1, 2]
    end

    test "handles nodes without attrs" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{"type" => "action", "content" => [%{"type" => "text", "text" => "Hello"}]}
        ]
      }

      [attrs] = TiptapSerialization.doc_to_element_attrs(doc)

      assert attrs.type == "action"
      assert attrs.content == "Hello"
      assert attrs.data == %{}
      assert attrs.element_id == nil
    end

    test "concatenates multiple text nodes" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "action",
            "attrs" => %{},
            "content" => [
              %{"type" => "text", "text" => "Hello "},
              %{"type" => "text", "text" => "world"}
            ]
          }
        ]
      }

      [attrs] = TiptapSerialization.doc_to_element_attrs(doc)
      assert attrs.content == "Hello world"
    end

    test "serializes mention inline nodes as HTML spans" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "action",
            "attrs" => %{},
            "content" => [
              %{"type" => "text", "text" => "Hello "},
              %{
                "type" => "mention",
                "attrs" => %{"id" => "42", "label" => "Jaime", "type" => "sheet"}
              },
              %{"type" => "text", "text" => " world"}
            ]
          }
        ]
      }

      [attrs] = TiptapSerialization.doc_to_element_attrs(doc)

      assert attrs.content =~
               ~s(<span class="mention" data-type="sheet" data-id="42" data-label="Jaime">#Jaime</span>)

      assert attrs.content |> String.starts_with?("Hello ")
      assert attrs.content |> String.ends_with?(" world")
    end
  end

  # -- Mention inline content tests -------------------------------------------

  describe "elements_to_doc/1 with mentions" do
    test "parses mention HTML spans into mention nodes" do
      content =
        ~s(Visit <span class="mention" data-type="sheet" data-id="7" data-label="Village">#Village</span> today)

      doc =
        TiptapSerialization.elements_to_doc([element(id: 1, type: "action", content: content)])

      [node] = doc["content"]

      assert [
               %{"type" => "text", "text" => "Visit "},
               %{
                 "type" => "mention",
                 "attrs" => %{"id" => "7", "label" => "Village", "type" => "sheet"}
               },
               %{"type" => "text", "text" => " today"}
             ] = node["content"]
    end

    test "plain text without spans produces single text node" do
      doc =
        TiptapSerialization.elements_to_doc([
          element(id: 1, type: "action", content: "Just text")
        ])

      [node] = doc["content"]

      assert node["content"] == [%{"type" => "text", "text" => "Just text"}]
    end

    test "content with ampersand and no spans stays plain text" do
      doc =
        TiptapSerialization.elements_to_doc([
          element(id: 1, type: "action", content: "AT&T rocks")
        ])

      [node] = doc["content"]
      assert node["content"] == [%{"type" => "text", "text" => "AT&T rocks"}]
    end

    test "multiple mentions in one element" do
      content =
        ~s(<span class="mention" data-type="sheet" data-id="1" data-label="Alice">#Alice</span> and <span class="mention" data-type="sheet" data-id="2" data-label="Bob">#Bob</span>)

      doc =
        TiptapSerialization.elements_to_doc([element(id: 1, type: "dialogue", content: content)])

      [node] = doc["content"]

      types = Enum.map(node["content"], & &1["type"])
      assert types == ["mention", "text", "mention"]
    end
  end

  # -- Rich text marks (bold, italic, strike) -----------------------------------

  describe "elements_to_doc/1 with marks" do
    test "parses <strong> tag into bold mark" do
      doc =
        TiptapSerialization.elements_to_doc([
          element(id: 1, type: "action", content: "He <strong>ran</strong> fast")
        ])

      [node] = doc["content"]

      assert [
               %{"type" => "text", "text" => "He "},
               %{"type" => "text", "text" => "ran", "marks" => [%{"type" => "bold"}]},
               %{"type" => "text", "text" => " fast"}
             ] = node["content"]
    end

    test "parses <b> tag as bold mark" do
      doc =
        TiptapSerialization.elements_to_doc([
          element(id: 1, type: "action", content: "<b>bold</b>")
        ])

      [node] = doc["content"]

      assert [%{"type" => "text", "text" => "bold", "marks" => [%{"type" => "bold"}]}] =
               node["content"]
    end

    test "parses <em> tag into italic mark" do
      doc =
        TiptapSerialization.elements_to_doc([
          element(id: 1, type: "dialogue", content: "Say <em>please</em>")
        ])

      [node] = doc["content"]

      assert [
               %{"type" => "text", "text" => "Say "},
               %{"type" => "text", "text" => "please", "marks" => [%{"type" => "italic"}]}
             ] = node["content"]
    end

    test "parses <i> tag as italic mark" do
      doc =
        TiptapSerialization.elements_to_doc([
          element(id: 1, type: "action", content: "<i>italic</i>")
        ])

      [node] = doc["content"]

      assert [%{"type" => "text", "text" => "italic", "marks" => [%{"type" => "italic"}]}] =
               node["content"]
    end

    test "parses <s> tag into strike mark" do
      doc =
        TiptapSerialization.elements_to_doc([
          element(id: 1, type: "action", content: "<s>deleted</s> text")
        ])

      [node] = doc["content"]

      assert [
               %{"type" => "text", "text" => "deleted", "marks" => [%{"type" => "strike"}]},
               %{"type" => "text", "text" => " text"}
             ] = node["content"]
    end

    test "parses <del> tag as strike mark" do
      doc =
        TiptapSerialization.elements_to_doc([
          element(id: 1, type: "action", content: "<del>removed</del>")
        ])

      [node] = doc["content"]

      assert [%{"type" => "text", "text" => "removed", "marks" => [%{"type" => "strike"}]}] =
               node["content"]
    end

    test "parses nested marks (bold + italic)" do
      doc =
        TiptapSerialization.elements_to_doc([
          element(id: 1, type: "action", content: "<strong><em>both</em></strong>")
        ])

      [node] = doc["content"]

      assert [
               %{
                 "type" => "text",
                 "text" => "both",
                 "marks" => [%{"type" => "bold"}, %{"type" => "italic"}]
               }
             ] = node["content"]
    end

    test "plain text without mark tags produces no marks key" do
      doc =
        TiptapSerialization.elements_to_doc([
          element(id: 1, type: "action", content: "plain text")
        ])

      [node] = doc["content"]
      [text_node] = node["content"]

      refute Map.has_key?(text_node, "marks")
    end
  end

  # -- Hard break (<br>) ------------------------------------------------------

  describe "elements_to_doc/1 with hard breaks" do
    test "parses <br> into hardBreak node" do
      doc =
        TiptapSerialization.elements_to_doc([
          element(id: 1, type: "action", content: "Line one<br>Line two")
        ])

      [node] = doc["content"]

      assert [
               %{"type" => "text", "text" => "Line one"},
               %{"type" => "hardBreak"},
               %{"type" => "text", "text" => "Line two"}
             ] = node["content"]
    end

    test "parses self-closing <br/> and <br /> variants" do
      for br <- ["<br>", "<br/>", "<br />"] do
        doc =
          TiptapSerialization.elements_to_doc([
            element(id: 1, type: "action", content: "A#{br}B")
          ])

        [node] = doc["content"]
        types = Enum.map(node["content"], & &1["type"])
        assert types == ["text", "hardBreak", "text"], "Failed for variant: #{br}"
      end
    end
  end

  # -- doc_to_element_attrs with marks and hard breaks -------------------------

  describe "doc_to_element_attrs/1 with marks" do
    test "serializes bold mark as <strong> tag" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "action",
            "attrs" => %{},
            "content" => [
              %{"type" => "text", "text" => "bold", "marks" => [%{"type" => "bold"}]}
            ]
          }
        ]
      }

      [attrs] = TiptapSerialization.doc_to_element_attrs(doc)
      assert attrs.content == "<strong>bold</strong>"
    end

    test "serializes italic mark as <em> tag" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "action",
            "attrs" => %{},
            "content" => [
              %{"type" => "text", "text" => "italic", "marks" => [%{"type" => "italic"}]}
            ]
          }
        ]
      }

      [attrs] = TiptapSerialization.doc_to_element_attrs(doc)
      assert attrs.content == "<em>italic</em>"
    end

    test "serializes strike mark as <s> tag" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "action",
            "attrs" => %{},
            "content" => [
              %{"type" => "text", "text" => "struck", "marks" => [%{"type" => "strike"}]}
            ]
          }
        ]
      }

      [attrs] = TiptapSerialization.doc_to_element_attrs(doc)
      assert attrs.content == "<s>struck</s>"
    end

    test "serializes nested marks" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "action",
            "attrs" => %{},
            "content" => [
              %{
                "type" => "text",
                "text" => "both",
                "marks" => [%{"type" => "bold"}, %{"type" => "italic"}]
              }
            ]
          }
        ]
      }

      [attrs] = TiptapSerialization.doc_to_element_attrs(doc)
      assert attrs.content == "<em><strong>both</strong></em>"
    end

    test "serializes hardBreak as <br>" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "action",
            "attrs" => %{},
            "content" => [
              %{"type" => "text", "text" => "Line one"},
              %{"type" => "hardBreak"},
              %{"type" => "text", "text" => "Line two"}
            ]
          }
        ]
      }

      [attrs] = TiptapSerialization.doc_to_element_attrs(doc)
      assert attrs.content == "Line one<br>Line two"
    end

    test "escapes HTML in marked text" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "action",
            "attrs" => %{},
            "content" => [
              %{"type" => "text", "text" => "x < y", "marks" => [%{"type" => "bold"}]}
            ]
          }
        ]
      }

      [attrs] = TiptapSerialization.doc_to_element_attrs(doc)
      assert attrs.content == "<strong>x &lt; y</strong>"
    end

    test "plain text without marks skips HTML output" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "action",
            "attrs" => %{},
            "content" => [
              %{"type" => "text", "text" => "Hello"},
              %{"type" => "text", "text" => " world"}
            ]
          }
        ]
      }

      [attrs] = TiptapSerialization.doc_to_element_attrs(doc)
      # No HTML output — plain text concatenation (no escaping)
      assert attrs.content == "Hello world"
    end

    test "mixed marks and mentions" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "action",
            "attrs" => %{},
            "content" => [
              %{"type" => "text", "text" => "Visit ", "marks" => [%{"type" => "bold"}]},
              %{
                "type" => "mention",
                "attrs" => %{"id" => "7", "label" => "Village", "type" => "sheet"}
              },
              %{"type" => "text", "text" => " today"}
            ]
          }
        ]
      }

      [attrs] = TiptapSerialization.doc_to_element_attrs(doc)
      assert attrs.content =~ "<strong>Visit </strong>"
      assert attrs.content =~ ~s(data-id="7")
      assert attrs.content =~ " today"
    end
  end

  # -- Round-trip tests -------------------------------------------------------

  describe "round-trip" do
    test "elements -> doc -> attrs preserves all data" do
      original =
        element(
          id: 42,
          type: "dialogue",
          content: "Hello world",
          position: 0,
          data: %{"key" => "val"}
        )

      doc = TiptapSerialization.elements_to_doc([original])
      [result] = TiptapSerialization.doc_to_element_attrs(doc)

      assert result.type == "dialogue"
      assert result.content == "Hello world"
      assert result.data == %{"key" => "val"}
      assert result.element_id == 42
      assert result.position == 0
    end

    test "round-trip with mixed text and atom nodes" do
      originals = [
        element(id: 1, type: "scene_heading", content: "INT. OFFICE", position: 0),
        element(id: 2, type: "action", content: "Action text", position: 1),
        element(id: 3, type: "page_break", position: 2),
        element(id: 4, type: "character", content: "JOHN", position: 3, data: %{"sheet_id" => 5}),
        element(id: 5, type: "dialogue", content: "Line.", position: 4),
        element(
          id: 6,
          type: "conditional",
          position: 5,
          data: %{"condition" => %{"logic" => "all", "rules" => []}}
        )
      ]

      doc = TiptapSerialization.elements_to_doc(originals)
      results = TiptapSerialization.doc_to_element_attrs(doc)

      assert length(results) == 6

      # Text elements preserve content
      assert Enum.at(results, 0).content == "INT. OFFICE"
      assert Enum.at(results, 1).content == "Action text"
      assert Enum.at(results, 3).content == "JOHN"
      assert Enum.at(results, 4).content == "Line."

      # Atom elements have empty content
      assert Enum.at(results, 2).content == ""
      assert Enum.at(results, 5).content == ""

      # Data preserved
      assert Enum.at(results, 3).data == %{"sheet_id" => 5}
      assert Enum.at(results, 5).data == %{"condition" => %{"logic" => "all", "rules" => []}}

      # Types preserved
      assert Enum.map(results, & &1.type) ==
               ~w(scene_heading action page_break character dialogue conditional)

      # IDs preserved
      assert Enum.map(results, & &1.element_id) == [1, 2, 3, 4, 5, 6]
    end

    test "round-trip with empty content" do
      original = element(id: 1, type: "action", content: "", position: 0)

      doc = TiptapSerialization.elements_to_doc([original])
      [result] = TiptapSerialization.doc_to_element_attrs(doc)

      assert result.content == ""
    end

    test "round-trip with nil content" do
      original = element(id: 1, type: "action", content: nil, position: 0)

      doc = TiptapSerialization.elements_to_doc([original])
      [result] = TiptapSerialization.doc_to_element_attrs(doc)

      assert result.content == ""
    end

    test "round-trip preserves inline mentions" do
      content =
        ~s(Visit <span class="mention" data-type="sheet" data-id="7" data-label="Village">#Village</span> today)

      original = element(id: 1, type: "action", content: content, position: 0)

      doc = TiptapSerialization.elements_to_doc([original])
      [result] = TiptapSerialization.doc_to_element_attrs(doc)

      # Content should contain the mention span after round-trip
      assert result.content =~ ~s(data-id="7")
      assert result.content =~ ~s(data-label="Village")
      assert result.content =~ "Visit "
      assert result.content =~ " today"
    end

    test "round-trip with HTML-encoded text around mentions" do
      content =
        ~s(A &amp; B <span class="mention" data-type="sheet" data-id="1" data-label="Test">#Test</span> end)

      original = element(id: 1, type: "action", content: content, position: 0)

      doc = TiptapSerialization.elements_to_doc([original])
      [node] = doc["content"]

      # Floki decodes &amp; back to &
      assert [
               %{"type" => "text", "text" => "A & B "},
               %{"type" => "mention", "attrs" => %{"id" => "1", "label" => "Test"}},
               %{"type" => "text", "text" => " end"}
             ] = node["content"]

      # Back to HTML: & is re-encoded
      [result] = TiptapSerialization.doc_to_element_attrs(doc)
      assert result.content =~ "A &amp; B"
      assert result.content =~ ~s(data-id="1")
    end

    test "round-trip preserves bold marks" do
      content = "He <strong>ran</strong> fast"
      original = element(id: 1, type: "action", content: content, position: 0)

      doc = TiptapSerialization.elements_to_doc([original])
      [result] = TiptapSerialization.doc_to_element_attrs(doc)

      assert result.content =~ "<strong>ran</strong>"
      assert result.content =~ "He "
      assert result.content =~ " fast"
    end

    test "round-trip preserves italic marks" do
      content = "<em>whispered</em> words"
      original = element(id: 1, type: "dialogue", content: content, position: 0)

      doc = TiptapSerialization.elements_to_doc([original])
      [result] = TiptapSerialization.doc_to_element_attrs(doc)

      assert result.content =~ "<em>whispered</em>"
      assert result.content =~ " words"
    end

    test "round-trip preserves strike marks" do
      content = "<s>deleted</s> text"
      original = element(id: 1, type: "action", content: content, position: 0)

      doc = TiptapSerialization.elements_to_doc([original])
      [result] = TiptapSerialization.doc_to_element_attrs(doc)

      assert result.content =~ "<s>deleted</s>"
      assert result.content =~ " text"
    end

    test "round-trip preserves hard breaks" do
      content = "Line one<br>Line two"
      original = element(id: 1, type: "action", content: content, position: 0)

      doc = TiptapSerialization.elements_to_doc([original])
      [result] = TiptapSerialization.doc_to_element_attrs(doc)

      assert result.content == "Line one<br>Line two"
    end

    test "round-trip preserves nested bold + italic" do
      content = "<strong><em>both</em></strong>"
      original = element(id: 1, type: "action", content: content, position: 0)

      doc = TiptapSerialization.elements_to_doc([original])
      [result] = TiptapSerialization.doc_to_element_attrs(doc)

      # Nested: inner mark wraps first, outer wraps second
      assert result.content == "<em><strong>both</strong></em>"
    end

    test "round-trip preserves bold text mixed with mentions" do
      content =
        ~s(<strong>Visit</strong> <span class="mention" data-type="sheet" data-id="7" data-label="Village">#Village</span>)

      original = element(id: 1, type: "action", content: content, position: 0)

      doc = TiptapSerialization.elements_to_doc([original])
      [result] = TiptapSerialization.doc_to_element_attrs(doc)

      assert result.content =~ "<strong>Visit</strong>"
      assert result.content =~ ~s(data-id="7")
    end

    test "round-trip preserves hard break mixed with marks" do
      content = "<strong>Bold</strong><br><em>Italic</em>"
      original = element(id: 1, type: "action", content: content, position: 0)

      doc = TiptapSerialization.elements_to_doc([original])
      [result] = TiptapSerialization.doc_to_element_attrs(doc)

      assert result.content =~ "<strong>Bold</strong>"
      assert result.content =~ "<br>"
      assert result.content =~ "<em>Italic</em>"
    end

    test "round-trip preserves auto-detected scene heading type and content" do
      original = element(id: 1, type: "scene_heading", content: "INT. OFFICE - DAY", position: 0)

      doc = TiptapSerialization.elements_to_doc([original])
      assert [%{"type" => "sceneHeading"}] = doc["content"]

      [result] = TiptapSerialization.doc_to_element_attrs(doc)
      assert result.type == "scene_heading"
      assert result.content == "INT. OFFICE - DAY"
    end

    test "round-trip preserves auto-detected transition type and content" do
      original = element(id: 1, type: "transition", content: "CUT TO:", position: 0)

      doc = TiptapSerialization.elements_to_doc([original])
      assert [%{"type" => "transition"}] = doc["content"]

      [result] = TiptapSerialization.doc_to_element_attrs(doc)
      assert result.type == "transition"
      assert result.content == "CUT TO:"
    end

    test "round-trip preserves auto-detected parenthetical type and content" do
      original = element(id: 1, type: "parenthetical", content: "(whispering)", position: 0)

      doc = TiptapSerialization.elements_to_doc([original])
      assert [%{"type" => "parenthetical"}] = doc["content"]

      [result] = TiptapSerialization.doc_to_element_attrs(doc)
      assert result.type == "parenthetical"
      assert result.content == "(whispering)"
    end
  end
end
