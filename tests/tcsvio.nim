import std/[unittest, os, tempfiles, tables, options, algorithm]
import results
import jevvypkg/csvio

suite "CsvIO":
  test "read empty file yields empty table":
    var (cf, path) = createTempFile("jevvy-empty", ".csv")
    cf.close()
    defer:
      removeFile(path)
    writeFile(path, "")
    let table = read(path)
    check table.isOk
    check table.get().headers.len == 0
    check table.get().rows.len == 0

  test "readRows pulls rows lazily":
    var (cf, path) = createTempFile("jevvy-lazy", ".csv")
    cf.close()
    defer:
      removeFile(path)
    check write(path, @["id"], @[@[ "1"], @["2"], @["3"]]).isOk
    var rowsConsumed = 0
    let onlyFirst = readRows(
      path,
      proc(headers: seq[string]; readNext: RowSource): string =
        let row = readNext()
        if row.isSome:
          rowsConsumed += 1
          row.get()["id"]
        else:
          "",
    )
    check onlyFirst == "1"
    check rowsConsumed == 1

  test "write and read roundtrip":
    var (cf, path) = createTempFile("jevvy-roundtrip", ".csv")
    cf.close()
    defer:
      removeFile(path)
    let headers = @["a", "b"]
    let rows = @[@[ "1", "2"], @["3", "4"]]
    check write(path, headers, rows).isOk
    let table = read(path).get()
    check table.headers == headers
    check table.rows.len == 2
    check table.rows[0]["a"] == "1"
    check table.rows[1]["b"] == "4"

  test "rowValuesInOrder follows header order":
    let row = {"z": "last", "a": "first"}.toTable()
    check rowValuesInOrder(@["a", "z", "missing"], row) == @["first", "last", ""]

  test "rowToState sorts fields by key":
    let state = rowToState({"b": "two", "a": "one"}.toTable())
    var keys: seq[string] = @[]
    for k in state.obj.keys:
      keys.add k
    keys.sort()
    check keys == @["a", "b"]
