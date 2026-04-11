import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { formatRelativeTime } from "@utils/date-utils";

describe("formatRelativeTime", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-04-10T12:00:00Z"));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("returns dash for null/undefined/empty", () => {
    expect(formatRelativeTime(null)).toBe("\u2014");
    expect(formatRelativeTime(undefined)).toBe("\u2014");
    expect(formatRelativeTime("")).toBe("\u2014");
  });

  it("returns 'just now' for < 1 minute", () => {
    expect(formatRelativeTime("2026-04-10T11:59:30Z")).toBe("just now");
  });

  it("returns minutes ago", () => {
    expect(formatRelativeTime("2026-04-10T11:55:00Z")).toBe("5m ago");
    expect(formatRelativeTime("2026-04-10T11:01:00Z")).toBe("59m ago");
  });

  it("returns hours ago", () => {
    expect(formatRelativeTime("2026-04-10T10:00:00Z")).toBe("2h ago");
    expect(formatRelativeTime("2026-04-09T13:00:00Z")).toBe("23h ago");
  });

  it("returns days ago", () => {
    expect(formatRelativeTime("2026-04-09T12:00:00Z")).toBe("1d ago");
    expect(formatRelativeTime("2026-03-20T12:00:00Z")).toBe("21d ago");
  });

  it("returns locale date for >= 30 days", () => {
    const result = formatRelativeTime("2026-02-01T12:00:00Z");
    expect(result).not.toContain("ago");
    expect(result).toBeTruthy();
  });
});
