defmodule Storyarn.Emails.Layout do
  @moduledoc """
  Shared MJML email layout for all transactional emails.

  Compiles MJML to HTML. All emails share the same visual structure:
  logo header, content area, and footer.
  """

  @doc """
  Wraps content in the shared email layout and compiles MJML to HTML.

  ## Options
    * `:preview` - Preview text shown in email clients (optional)
  """
  def render(content, opts \\ []) do
    preview = Keyword.get(opts, :preview, "")

    mjml = """
    <mjml>
      <mj-head>
        <mj-attributes>
          <mj-all font-family="system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif" />
          <mj-text font-size="15px" line-height="1.6" color="#374151" />
          <mj-button font-size="15px" font-weight="600" border-radius="8px" inner-padding="12px 28px" />
        </mj-attributes>
        <mj-style>
          a { color: #7c3aed; }
          .footer-link { color: #9ca3af !important; text-decoration: none !important; }
        </mj-style>
        #{if preview != "", do: "<mj-preview>#{escape(preview)}</mj-preview>", else: ""}
      </mj-head>
      <mj-body background-color="#f3f4f6">
        <mj-section padding="30px 0 10px">
          <mj-column>
            <mj-text align="center" font-size="22px" font-weight="700" color="#111827" letter-spacing="-0.02em">
              Storyarn
            </mj-text>
          </mj-column>
        </mj-section>

        <mj-section background-color="#ffffff" border-radius="12px" padding="32px 24px">
          <mj-column>
            #{content}
          </mj-column>
        </mj-section>

        <mj-section padding="16px 0 30px">
          <mj-column>
            <mj-text align="center" font-size="12px" color="#9ca3af">
              Storyarn — Narrative design for games &amp; interactive stories
            </mj-text>
          </mj-column>
        </mj-section>
      </mj-body>
    </mjml>
    """

    case Mjml.to_html(mjml) do
      {:ok, html} -> html
      {:error, reason} -> raise "MJML compilation failed: #{inspect(reason)}"
    end
  end

  defp escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
