const tags = new Set([
  "p",
  "br",
  "em",
  "strong",
  "b",
  "i",
  "u",
  "s",
  "span",
  "ul",
  "ol",
  "li",
  "blockquote",
  "code",
  "pre",
  "sub",
  "sup",
  "del",
  "h2",
  "h3",
]);

/** Inert parsing, closed formatting, no attributes/URLs. Server validation is
 * authoritative; this only makes pasted external text editable without scripts. */
export function pasteContent(html: string): string {
  const template = document.createElement("template");
  template.innerHTML = html;
  for (const element of [...template.content.querySelectorAll("*")].reverse()) {
    if (!tags.has(element.tagName.toLowerCase())) {
      element.replaceWith(...element.childNodes);
    } else {
      while (element.attributes.length) element.removeAttribute(element.attributes[0].name);
    }
  }
  return template.innerHTML;
}

/** The server re-serializes bodies (`"` → `&quot;`, `<br>` → `<br/>`, `&nbsp;` →
 * U+00A0), so raw strings differ while the document is identical. Compare
 * through the browser's own serialization instead. */
export function sameBody(a: string, b: string): boolean {
  return a === b || pasteContent(a) === pasteContent(b);
}
