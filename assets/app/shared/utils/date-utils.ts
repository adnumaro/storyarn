const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;
const WEEK = 7 * DAY;

export type DatePreset = "date" | "datetime" | "monthDay" | "dateLong";

const PRESETS: Record<DatePreset, Intl.DateTimeFormatOptions> = {
  date: { dateStyle: "medium" },
  datetime: { dateStyle: "medium", timeStyle: "short" },
  monthDay: { month: "short", day: "numeric" },
  dateLong: { dateStyle: "long" },
};

// A calendar date without a time ("2026-09-26") is a day, not an instant: it is
// read at local midnight so it never shifts to the previous day west of UTC.
const CALENDAR_DATE = /^\d{4}-\d{2}-\d{2}$/;

type DateInput = string | number | Date | null | undefined;

function toDate(value: DateInput): Date | null {
  if (value === null || value === undefined || value === "") return null;
  const date =
    typeof value === "string" && CALENDAR_DATE.test(value)
      ? new Date(`${value}T00:00:00`)
      : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

/** A date in the viewer's language; an empty string when the value is missing or not a date. */
export function formatDate(value: DateInput, locale: string, preset: DatePreset = "date"): string {
  const date = toDate(value);
  return date ? new Intl.DateTimeFormat(locale, PRESETS[preset]).format(date) : "";
}

/**
 * How long ago, in the viewer's language: "now", "20m ago", "yesterday", "3w ago"
 * ("ahora", "hace 20 min", "ayer"…). Beyond five weeks it shows the calendar date.
 * An empty string when the value is missing or not a date.
 */
export function formatRelativeTime(value: DateInput, locale: string, now = Date.now()): string {
  const date = toDate(value);
  if (!date) return "";

  const elapsed = now - date.getTime();
  const rtf = new Intl.RelativeTimeFormat(locale, { numeric: "auto", style: "narrow" });
  if (elapsed < MINUTE) return rtf.format(0, "second");
  if (elapsed < HOUR) return rtf.format(-Math.floor(elapsed / MINUTE), "minute");
  if (elapsed < DAY) return rtf.format(-Math.floor(elapsed / HOUR), "hour");
  if (elapsed < WEEK) return rtf.format(-Math.floor(elapsed / DAY), "day");
  if (elapsed < 5 * WEEK) return rtf.format(-Math.floor(elapsed / WEEK), "week");
  return formatDate(date, locale);
}
