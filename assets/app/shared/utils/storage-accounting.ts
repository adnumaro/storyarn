export type StorageLimitKind = "limited" | "unlimited" | "unknown";

/**
 * Byte counts cross the LiveView boundary as base-10 strings. PostgreSQL
 * bigint values can exceed JavaScript's safe integer range, so converting them
 * to number would make quota information silently inaccurate.
 */
export type ByteCount = string;

export interface WorkspaceStorageUsage {
  currentAssetsBytes: ByteCount;
  assetTrashBytes: ByteCount;
  fullSnapshotsBytes: ByteCount;
  activeReservationsBytes: ByteCount;
  totalAccountedBytes: ByteCount;
  limitBytes: ByteCount | null;
  remainingBytes: ByteCount | null;
  limitKind: StorageLimitKind;
}

export type StoragePercentageState = "limited" | "over_limit" | "zero" | "unlimited" | "unknown";

export interface StoragePercentage {
  state: StoragePercentageState;
  basisPoints: bigint | null;
  progressPercent: number;
  lessThanOneBasisPoint: boolean;
}

const BYTE_UNITS = ["B", "KB", "MB", "GB", "TB", "PB", "EB"] as const;
const BYTES_PER_UNIT = 1024n;
const BASIS_POINTS_PER_PERCENT = 100n;
const BASIS_POINTS_PER_WHOLE = 10_000n;
const NUMERIC_PERCENT_PARTS = new Set(["integer", "group", "decimal", "fraction"]);

/**
 * Formats an integer byte count using binary unit boundaries and localized
 * decimal separators. Invalid, negative, or unknown measurements stay unknown
 * instead of being silently displayed as zero usage.
 */
export function formatBytes(bytes: ByteCount | null | undefined, locale?: string): string {
  const parsed = parseByteCount(bytes);
  if (parsed === null) return "\u2014";
  if (parsed === 0n) return "0 B";

  const unit = byteUnit(parsed);

  if (unit.index === 0) {
    return `${new Intl.NumberFormat(locale).format(parsed)} ${BYTE_UNITS[unit.index]}`;
  }

  const rounded = roundedByteUnit(parsed, unit);
  const boundedValue = Number(rounded.value) / Number(rounded.scale);
  const formatted = new Intl.NumberFormat(locale, {
    maximumFractionDigits: rounded.atLeastTenUnits ? 0 : 1,
  }).format(boundedValue);

  return `${formatted} ${BYTE_UNITS[rounded.index]}`;
}

/**
 * Calculates storage usage with exact integer basis-point semantics.
 *
 * Limited percentages are rounded half-up to the nearest basis point (0.01%)
 * with BigInt arithmetic. Usage below the limit is capped at 99.99% so
 * rounding never claims capacity is exhausted while a final byte still fits.
 * Over-limit basis points remain uncapped while only the progress bar is
 * clamped to 100%.
 */
export function storagePercentage(
  usedBytes: ByteCount | null,
  limitBytes: ByteCount | null,
  limitKind: StorageLimitKind,
): StoragePercentage {
  const used = parseByteCount(usedBytes);
  if (used === null) return unknownPercentage();

  if (limitKind === "unlimited") {
    return percentage("unlimited", null, 0);
  }

  const limit = parseByteCount(limitBytes);
  if (limitKind === "unknown" || limit === null) {
    return unknownPercentage();
  }

  if (limit === 0n) {
    return used === 0n ? percentage("zero", 0n, 0) : percentage("over_limit", null, 100);
  }

  return limitedPercentage(used, limit);
}

function limitedPercentage(used: bigint, limit: bigint): StoragePercentage {
  const roundedBasisPoints = (used * BASIS_POINTS_PER_WHOLE + limit / 2n) / limit;
  const exactBasisPoints =
    used < limit && roundedBasisPoints >= BASIS_POINTS_PER_WHOLE
      ? BASIS_POINTS_PER_WHOLE - 1n
      : roundedBasisPoints;
  const lessThanOneBasisPoint = used > 0n && used * BASIS_POINTS_PER_WHOLE < limit;
  const progressPercent =
    exactBasisPoints >= BASIS_POINTS_PER_WHOLE
      ? 100
      : Number(exactBasisPoints) / Number(BASIS_POINTS_PER_PERCENT);

  return {
    state: used > limit ? "over_limit" : "limited",
    basisPoints: exactBasisPoints,
    progressPercent,
    lessThanOneBasisPoint,
  };
}

/** Formats an arbitrary exact basis-point count as a localized percentage. */
export function formatBasisPoints(basisPoints: bigint, locale?: string): string {
  if (basisPoints < 0n) return "\u2014";

  const wholePercent = basisPoints / BASIS_POINTS_PER_PERCENT;
  const fractionalBasisPoints = basisPoints % BASIS_POINTS_PER_PERCENT;
  const integer = new Intl.NumberFormat(locale, { maximumFractionDigits: 0 }).format(wholePercent);
  const fraction = fractionalBasisPoints.toString().padStart(2, "0").replace(/0+$/, "");
  const decimalSeparator =
    new Intl.NumberFormat(locale).formatToParts(1.1).find((part) => part.type === "decimal")
      ?.value ?? ".";
  const numericValue = fraction ? `${integer}${decimalSeparator}${fraction}` : integer;
  const percentParts = new Intl.NumberFormat(locale, {
    style: "percent",
    maximumFractionDigits: 0,
  }).formatToParts(0);
  let inserted = false;

  return percentParts
    .map((part) => {
      if (!NUMERIC_PERCENT_PARTS.has(part.type)) return part.value;
      if (inserted) return "";

      inserted = true;
      return numericValue;
    })
    .join("");
}

export function positiveByteCount(value: ByteCount | null | undefined): boolean {
  const parsed = parseByteCount(value);
  return parsed !== null && parsed > 0n;
}

function parseByteCount(value: ByteCount | null | undefined): bigint | null {
  if (typeof value !== "string" || !/^(0|[1-9]\d*)$/.test(value)) return null;

  return BigInt(value);
}

interface ByteUnit {
  divisor: bigint;
  index: number;
}

interface RoundedByteUnit extends ByteUnit {
  atLeastTenUnits: boolean;
  scale: bigint;
  value: bigint;
}

function byteUnit(bytes: bigint): ByteUnit {
  let divisor = 1n;
  let index = 0;

  while (bytes >= divisor * BYTES_PER_UNIT && index < BYTE_UNITS.length - 1) {
    divisor *= BYTES_PER_UNIT;
    index += 1;
  }

  return { divisor, index };
}

function roundedByteUnit(bytes: bigint, unit: ByteUnit): RoundedByteUnit {
  const atLeastTenUnits = bytes >= unit.divisor * 10n;
  const scale = atLeastTenUnits ? 1n : 10n;
  const value = (bytes * scale + unit.divisor / 2n) / unit.divisor;

  if (value >= BYTES_PER_UNIT * scale && unit.index < BYTE_UNITS.length - 1) {
    return roundedByteUnit(bytes, {
      divisor: unit.divisor * BYTES_PER_UNIT,
      index: unit.index + 1,
    });
  }

  return { ...unit, atLeastTenUnits, scale, value };
}

function percentage(
  state: StoragePercentageState,
  basisPoints: bigint | null,
  progressPercent: number,
): StoragePercentage {
  return { state, basisPoints, progressPercent, lessThanOneBasisPoint: false };
}

function unknownPercentage(): StoragePercentage {
  return percentage("unknown", null, 0);
}
