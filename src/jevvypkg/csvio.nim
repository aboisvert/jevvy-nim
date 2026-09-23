import std/[parsecsv, tables, algorithm, os, strutils, options, sequtils]
import jev_nim_client/content
import results

type
  CsvTable* = object
    headers*: seq[string]
    rows*: seq[Table[string, string]]

  RowSource* = proc(): Option[Table[string, string]] {.closure.}

proc needsCsvQuoting*(s: string): bool =
  for ch in s:
    if ch in {',', '"', '\n', '\r'}:
      return true
  false

proc csvEscapeField*(s: string): string =
  if needsCsvQuoting(s):
    "\"" & s.replace("\"", "\"\"") & "\""
  else:
    s

proc rowValuesInOrder*(headers: seq[string]; row: Table[string, string]): seq[string] =
  for h in headers:
    result.add row.getOrDefault(h)

proc rowToState*(row: Table[string, string]): JsonContent =
  var pairs = initOrderedTable[string, JsonValue]()
  for k, v in row.pairs:
    pairs[k] = jsonStr(v)
  var keys = toSeq(pairs.keys)
  keys.sort()
  var sorted = initOrderedTable[string, JsonValue]()
  for k in keys:
    sorted[k] = pairs[k]
  jsonContentObj(sorted)

proc zipRow(headers: seq[string]; fields: seq[string]): Table[string, string] =
  for i, h in headers:
    if i < fields.len:
      result[h] = fields[i]
    else:
      result[h] = ""

proc readRows*[T](
    path: string;
    f: proc(headers: seq[string]; readNext: RowSource): T {.closure.},
): T =
  var p: CsvParser
  p.open(path)
  try:
    if not p.readRow():
      return f(@[], proc(): Option[Table[string, string]] = none(Table[string, string]))
    let headers = p.row
    proc readNext(): Option[Table[string, string]] =
      if not p.readRow():
        return none(Table[string, string])
      some(zipRow(headers, p.row))
    result = f(headers, readNext)
  finally:
    p.close()

proc readRowsResult*[T](
    path: string;
    f: proc(headers: seq[string]; readNext: RowSource): T {.closure.},
): Result[T, string] =
  try:
    ok(readRows(path, f))
  except CatchableError as e:
    err("cannot read CSV " & path & ": " & e.msg)

proc writeRows*[T](
    path: string; headers: seq[string]; f: proc(writeRow: proc(fields: seq[string])): T,
): T =
  var fstream = open(path, fmWrite)
  try:
    fstream.writeLine(headers.mapIt(csvEscapeField(it)).join(","))
    proc writeRow(fields: seq[string]) =
      fstream.writeLine(fields.mapIt(csvEscapeField(it)).join(","))
    result = f(writeRow)
  finally:
    fstream.close()

proc writeRowsResult*[T](
    path: string;
    headers: seq[string];
    f: proc(writeRow: proc(fields: seq[string])): T,
): Result[T, string] =
  try:
    ok(writeRows(path, headers, f))
  except CatchableError as e:
    err("cannot write CSV " & path & ": " & e.msg)

proc read*(path: string): Result[CsvTable, string] =
  readRowsResult(
    path,
    proc(headers: seq[string]; readNext: RowSource): CsvTable =
      var table = CsvTable(headers: headers, rows: @[])
      while true:
        let row = readNext()
        if row.isNone:
          break
        table.rows.add row.get()
      table,
  )

proc write*(path: string; headers: seq[string]; rows: seq[seq[string]]): Result[void, string] =
  let written = writeRowsResult(
    path,
    headers,
    proc(writeRow: proc(fields: seq[string])): int =
      for r in rows:
        writeRow(r)
      0,
  )
  if written.isErr:
    return err(written.unsafeError())
  return ok()
