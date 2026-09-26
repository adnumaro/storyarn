/** Share of a limit at which every settings meter turns to "warning". */
export const METER_WARNING_RATIO = 0.8;

/** The same threshold for meters measured in basis points. */
export const METER_WARNING_BASIS_POINTS = BigInt(METER_WARNING_RATIO * 10_000);
