import { CellValue, TableColumn, TableRow } from "@modules/sheets/types.ts";

export function getCellValue(row: TableRow, column: TableColumn): CellValue {
  return row.cells?.[column.slug] ?? "";
}
