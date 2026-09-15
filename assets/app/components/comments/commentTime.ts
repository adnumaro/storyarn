const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;
const WEEK = 7 * DAY;

function formatter(locale: string): Intl.RelativeTimeFormat {
  try {
    return new Intl.RelativeTimeFormat(locale, { numeric: "auto", style: "narrow" });
  } catch {
    return new Intl.RelativeTimeFormat("en", { numeric: "auto", style: "narrow" });
  }
}

/**
 * Relative time for comment activity, in the viewer's language: "20 min ago",
 * "yesterday", "3 wk ago". Beyond five weeks it falls back to the calendar date.
 */
export function formatCommentTime(value: string, locale: string, now = Date.now()): string {
  const date = new Date(value);
  if (Number.isNaN(date.valueOf())) return "";
  const elapsed = now - date.valueOf();
  const rtf = formatter(locale);
  if (elapsed < MINUTE) return rtf.format(0, "second");
  if (elapsed < HOUR) return rtf.format(-Math.floor(elapsed / MINUTE), "minute");
  if (elapsed < DAY) return rtf.format(-Math.floor(elapsed / HOUR), "hour");
  if (elapsed < WEEK) return rtf.format(-Math.floor(elapsed / DAY), "day");
  if (elapsed < 5 * WEEK) return rtf.format(-Math.floor(elapsed / WEEK), "week");
  return new Intl.DateTimeFormat(locale, { dateStyle: "medium" }).format(date);
}

/** Full date and time, for tooltips over a relative time. */
export function formatCommentDateTime(value: string, locale: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.valueOf())) return "";
  return new Intl.DateTimeFormat(locale, { dateStyle: "medium", timeStyle: "short" }).format(date);
}
