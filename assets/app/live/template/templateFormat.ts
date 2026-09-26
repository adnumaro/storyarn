/** A publication, install or update date as the template screens show it. */
export function formatTemplateDate(value: string | null, locale: string): string {
  if (!value) return "";
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? ""
    : new Intl.DateTimeFormat(locale, { dateStyle: "medium" }).format(date);
}
