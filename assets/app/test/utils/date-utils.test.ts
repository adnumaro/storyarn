import { describe, expect, it } from "vitest";
import { formatDate, formatRelativeTime } from "../../shared/utils/date-utils";

const NOW = new Date(2026, 8, 26, 14, 0, 0).getTime();
const ago = (ms: number) => new Date(NOW - ms).toISOString();
const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

describe("formatRelativeTime", () => {
  it("reads in the viewer's language", () => {
    expect(formatRelativeTime(ago(30_000), "en", NOW)).toBe("now");
    expect(formatRelativeTime(ago(5 * MINUTE), "en", NOW)).toBe("5m ago");
    expect(formatRelativeTime(ago(5 * MINUTE), "es", NOW)).toBe("hace 5 min");
    expect(formatRelativeTime(ago(2 * HOUR), "es", NOW)).toBe("hace 2 h");
    expect(formatRelativeTime(ago(DAY), "en", NOW)).toBe("yesterday");
    expect(formatRelativeTime(ago(DAY), "es", NOW)).toBe("ayer");
    expect(formatRelativeTime(ago(14 * DAY), "en", NOW)).toBe("2w ago");
  });

  it("shows the calendar date beyond five weeks", () => {
    const old = new Date(2026, 6, 1, 12, 0, 0);

    expect(formatRelativeTime(old.toISOString(), "en", NOW)).toBe("Jul 1, 2026");
    expect(formatRelativeTime(old.toISOString(), "es", NOW)).toBe("1 jul 2026");
  });

  it("returns an empty string for a missing or invalid value", () => {
    expect(formatRelativeTime(null, "en", NOW)).toBe("");
    expect(formatRelativeTime(undefined, "en", NOW)).toBe("");
    expect(formatRelativeTime("", "en", NOW)).toBe("");
    expect(formatRelativeTime("not a date", "en", NOW)).toBe("");
  });
});

describe("formatDate", () => {
  const value = new Date(2026, 8, 26, 14, 5, 0);

  it("formats each preset in the viewer's language", () => {
    expect(formatDate(value, "en")).toBe("Sep 26, 2026");
    expect(formatDate(value, "es")).toBe("26 sept 2026");
    expect(formatDate(value, "es", "datetime")).toBe("26 sept 2026, 14:05");
    expect(formatDate(value, "en", "monthDay")).toBe("Sep 26");
    expect(formatDate(value, "es", "dateLong")).toBe("26 de septiembre de 2026");
  });

  it("reads a calendar date as that day, whatever the time zone", () => {
    expect(formatDate("2026-09-26", "en")).toBe("Sep 26, 2026");
  });

  it("returns an empty string instead of throwing for a missing or invalid value", () => {
    expect(formatDate(null, "en")).toBe("");
    expect(formatDate("", "en")).toBe("");
    expect(formatDate("2026-13-45T99:00", "en", "datetime")).toBe("");
  });
});
