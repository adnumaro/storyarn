import { describe, expect, it } from "vitest";
import {
  formatBasisPoints,
  formatBytes,
  storagePercentage,
} from "../../../shared/utils/storage-accounting";

describe("storage accounting formatting", () => {
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

  it("formats integer basis points without discarding meaningful precision", () => {
    expect(formatBasisPoints(1n, "en-US")).toBe("0.01%");
    expect(formatBasisPoints(3_333n, "en-US")).toBe("33.33%");
    expect(formatBasisPoints(12_345n, "en-US")).toBe("123.45%");
    expect(formatBasisPoints(3_333n, "es-ES")).toBe("33,33\u00a0%");
    expect(formatBasisPoints(90_071_992_547_409_930_000n, "en-US")).toBe(
      "900,719,925,474,099,300%",
    );
  });
});

describe("storagePercentage", () => {
  it("rounds limited usage half-up to the nearest basis point with integer arithmetic", () => {
    expect(storagePercentage("1", "3", "limited")).toEqual({
      state: "limited",
      basisPoints: 3_333n,
      progressPercent: 33.33,
      lessThanOneBasisPoint: false,
    });

    expect(storagePercentage("2", "3", "limited").basisPoints).toBe(6_667n);
    expect(storagePercentage("1", "32", "limited").basisPoints).toBe(313n);

    expect(storagePercentage("262143999", "262144000", "limited")).toEqual({
      state: "limited",
      basisPoints: 9_999n,
      progressPercent: 99.99,
      lessThanOneBasisPoint: false,
    });

    expect(storagePercentage("9223372036854775807", "9223372036854775807", "limited")).toEqual({
      state: "limited",
      basisPoints: 10_000n,
      progressPercent: 100,
      lessThanOneBasisPoint: false,
    });
  });

  it("keeps over-limit basis points visible while clamping only progress", () => {
    expect(storagePercentage("3", "2", "limited")).toEqual({
      state: "over_limit",
      basisPoints: 15_000n,
      progressPercent: 100,
      lessThanOneBasisPoint: false,
    });

    expect(storagePercentage("9007199254740993", "1", "limited")).toEqual({
      state: "over_limit",
      basisPoints: 90_071_992_547_409_930_000n,
      progressPercent: 100,
      lessThanOneBasisPoint: false,
    });
  });

  it("marks positive usage below 0.01% without presenting it as zero", () => {
    expect(storagePercentage("1", "20000", "limited")).toEqual({
      state: "limited",
      basisPoints: 1n,
      progressPercent: 0.01,
      lessThanOneBasisPoint: true,
    });
  });

  it("distinguishes zero, unlimited, unknown, and impossible zero-limit usage", () => {
    expect(storagePercentage("0", "0", "limited")).toEqual({
      state: "zero",
      basisPoints: 0n,
      progressPercent: 0,
      lessThanOneBasisPoint: false,
    });

    expect(storagePercentage("1", "0", "limited")).toEqual({
      state: "over_limit",
      basisPoints: null,
      progressPercent: 100,
      lessThanOneBasisPoint: false,
    });

    expect(storagePercentage("100", null, "unlimited")).toEqual({
      state: "unlimited",
      basisPoints: null,
      progressPercent: 0,
      lessThanOneBasisPoint: false,
    });

    expect(storagePercentage("100", null, "unknown")).toEqual({
      state: "unknown",
      basisPoints: null,
      progressPercent: 0,
      lessThanOneBasisPoint: false,
    });

    expect(storagePercentage(null, "100", "limited").state).toBe("unknown");
  });
});
