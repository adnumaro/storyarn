import { describe, expect, it } from "vitest";
import { formatBytes } from "../../../shared/utils/format-bytes";

describe("formatBytes", () => {
  it("formats exact byte counts at binary boundaries with the requested locale", () => {
    expect(formatBytes("0", "en-US")).toBe("0 B");
    expect(formatBytes("1023", "en-US")).toBe("1,023 B");
    expect(formatBytes("1024", "en-US")).toBe("1 KB");
    expect(formatBytes("1536", "en-US")).toBe("1.5 KB");
    expect(formatBytes("1536", "es-ES")).toBe("1,5 KB");
    expect(formatBytes(String(1024 ** 2 - 1), "en-US")).toBe("1 MB");
    expect(formatBytes(String(1024 ** 4), "en-US")).toBe("1 TB");
    expect(formatBytes("9223372036854775807", "en-US")).toBe("8 EB");
  });

  it("keeps invalid, negative, and unknown measurements visibly unknown", () => {
    expect(formatBytes(null, "en-US")).toBe("\u2014");
    expect(formatBytes("NaN", "en-US")).toBe("\u2014");
    expect(formatBytes("-1", "en-US")).toBe("\u2014");
    expect(formatBytes("1.5", "en-US")).toBe("\u2014");
    expect(formatBytes("01", "en-US")).toBe("\u2014");
  });

  it("reads a file size the same way as a stored byte count", () => {
    expect(formatBytes(1536, "en-US")).toBe("1.5 KB");
    expect(formatBytes(1536, "es-ES")).toBe("1,5 KB");
    expect(formatBytes(2.5 * 1024 ** 3, "en-US")).toBe("2.5 GB");
    expect(formatBytes(0, "en-US")).toBe("0 B");
  });

  it("keeps a fractional or negative file size unknown", () => {
    expect(formatBytes(1.5, "en-US")).toBe("\u2014");
    expect(formatBytes(-1, "en-US")).toBe("\u2014");
    expect(formatBytes(Number.NaN, "en-US")).toBe("\u2014");
  });
});
