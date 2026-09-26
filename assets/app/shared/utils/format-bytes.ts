/**
 * Byte counts cross the LiveView boundary as base-10 strings. PostgreSQL
 * bigint values can exceed JavaScript's safe integer range, so converting them
 * to number would make quota information silently inaccurate.
 */
export type ByteCount = string;

const BYTE_UNITS = ["B", "KB", "MB", "GB", "TB", "PB", "EB"] as const;
const BYTES_PER_UNIT = 1024n;

/**
 * Formats an integer byte count using binary unit boundaries and localized
 * decimal separators. Invalid, negative, or unknown measurements stay unknown
 * instead of being silently displayed as zero usage.
 */
export function formatBytes(bytes: ByteCount | number | null | undefined, locale?: string): string {
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

/** A byte count as an exact integer; null unless it is a whole, non-negative number. */
export function parseByteCount(value: ByteCount | number | null | undefined): bigint | null {
  if (typeof value === "number") {
    return Number.isSafeInteger(value) && value >= 0 ? BigInt(value) : null;
  }
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
