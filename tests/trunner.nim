import std/[unittest, asyncdispatch, os, tempfiles, tables, strutils, options]
import jev_nim_client
import jev_nim_client/requestloop
import results
import jevvypkg/[config, csvio, columns, runner]
import fixtures

const TestApiKey = "ts_test_key_1234567890"

proc testClientPool(n: int): seq[AsyncJevClient] =
  proc noopTransport(
      verb, url, body: string; headers: Table[string, string]; timeoutSec: float,
  ): Future[Result[RawResponse, JevFailure]] {.async.} =
    err(connectionFailure("unused in tests"))
  let transport = AsyncRequestExecutor(noopTransport)
  for _ in 0 ..< n:
    result.add newAsyncJevClient(
      apiKey = TestApiKey,
      baseUrl = "https://example.test",
      executor = some transport,
    ).get()

suite "BatchRunner":
  let isUrgent = noul("Urgent?")

  proc loadedConfig(): LoadedBatchConfig =
    var qs = initOrderedTable[string, Question]()
    qs["is_urgent"] = isUrgent
    LoadedBatchConfig(
      defaultModel: "test-model",
      timeoutSec: 30.0,
      retryPolicy: jevvyDefaultRetryPolicy(3),
      concurrency: 1,
      delayMs: 0,
      questions: qs,
      questionOrder: @["is_urgent"],
      scoreLabels: initTable[string, seq[string]](),
    )

  test "runWith writes success rows with empty jev_error":
    var (outCf, outPath) = createTempFile("jevvy-out", ".csv")
    outCf.close()
    var (inCf, inputPath) = createTempFile("jevvy-in", ".csv")
    inCf.close()
    defer:
      removeFile(outPath)
      removeFile(inputPath)
    check write(inputPath, @["message"], @[@[ "help"]]).isOk
    let table = read(inputPath).get()
    let body = bodyForNoul("is_urgent", 0.9)
    var qs = loadedConfig().questions
    let response = parseResponse(body, qs)

    proc fakeRequest(
        client: AsyncJevClient; state: JsonContent; rowIndex: int,
    ): Future[Result[SystemOneResponse, string]] {.async.} =
      return ok(response)

    var readIdx = 0
    proc readNext(): Option[Table[string, string]] =
      if readIdx < table.rows.len:
        let row = table.rows[readIdx]
        readIdx += 1
        some(row)
      else:
        none(Table[string, string])

    let clients = testClientPool(1)
    defer:
      for client in clients:
        client.close()
    let result =
      runWith(loadedConfig(), table.headers, readNext, outPath, clients, fakeRequest).get()
    check result.total == 1
    check result.failures == 0
    let written = read(outPath).get()
    check written.headers == @["message"] & extraHeaders(@["is_urgent"], qs)
    check written.rows[0]["jev_error"] == ""
    check written.rows[0]["is_urgent_probability"] == "0.9000"

  test "runWith records API errors in jev_error column":
    var (outCf, outPath) = createTempFile("jevvy-out-err", ".csv")
    outCf.close()
    defer:
      removeFile(outPath)

    proc failRequest(
        client: AsyncJevClient; state: JsonContent; rowIndex: int,
    ): Future[Result[SystemOneResponse, string]] {.async.} =
      return err("rate limited")

    var sent = false
    proc readNext(): Option[Table[string, string]] =
      if not sent:
        sent = true
        some({"message": "x"}.toTable())
      else:
        none(Table[string, string])

    let clients = testClientPool(1)
    defer:
      for client in clients:
        client.close()
    let result =
      runWith(loadedConfig(), @["message"], readNext, outPath, clients, failRequest).get()
    check result.failures == 1
    let written = read(outPath).get()
    check "rate limited" in written.rows[0]["jev_error"]

  test "runWith preserves row order under concurrency":
    var (outCf, outPath) = createTempFile("jevvy-out-order", ".csv")
    outCf.close()
    var (inCf, inputPath) = createTempFile("jevvy-in-order", ".csv")
    inCf.close()
    defer:
      removeFile(outPath)
      removeFile(inputPath)
    check write(inputPath, @["message"], @[@[ "slow"], @["b"], @["c"]]).isOk
    let table = read(inputPath).get()
    var cfg = loadedConfig()
    cfg.concurrency = 2
    let body = bodyForNoul("is_urgent", 0.5)
    let response = parseResponse(body, cfg.questions)

    proc slowRequest(
        client: AsyncJevClient; state: JsonContent; rowIndex: int,
    ): Future[Result[SystemOneResponse, string]] {.async.} =
      if rowIndex == 0:
        await sleepAsync(150)
      ok(response)

    var readIdx = 0
    proc readNext(): Option[Table[string, string]] =
      if readIdx < table.rows.len:
        let row = table.rows[readIdx]
        readIdx += 1
        some(row)
      else:
        none(Table[string, string])

    let clients = testClientPool(cfg.concurrency)
    defer:
      for client in clients:
        client.close()
    let result = runWith(cfg, table.headers, readNext, outPath, clients, slowRequest).get()
    check result.total == 3
    let written = read(outPath).get()
    var messages: seq[string] = @[]
    for row in written.rows:
      messages.add row["message"]
    check messages == @["slow", "b", "c"]
