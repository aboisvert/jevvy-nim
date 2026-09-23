import std/[asyncdispatch, locks, os, strutils, tables, options]
import jev_nim_client
import results
import ./config
import ./csvio
import ./columns
import ./prep

type
  BatchResult* = object
    outputPath*: string
    total*: int
    failures*: int

  RunRowRequest* = proc(
    client: AsyncJevClient; state: JsonContent; rowIndex: int,
  ): Future[Result[SystemOneResponse, string]] {.async.}

  InFlightRow* = object
    future*: Future[seq[string]]
    client*: AsyncJevClient

proc logProgress(total: int) =
  if total > 0 and total mod 10 == 0:
    stderr.writeLine("processed " & $total)

proc makeRowFuture(
    config: LoadedBatchConfig;
    client: AsyncJevClient;
    prep: PreparedRow;
    runRequest: RunRowRequest;
): Future[seq[string]] {.async.} =
  try:
    if config.delayMs > 0 and prep.index > 0:
      await sleepAsync(config.delayMs.int)
    let responseResult = await runRequest(client, prep.state, prep.index)
    let extra =
      if responseResult.isErr:
        valuesForError(
          config.questionOrder, config.questions, responseResult.unsafeError(),
        )
      else:
        let okFields = valuesForSuccess(
          responseResult.get(),
          config.questionOrder,
          config.questions,
          config.scoreLabels,
        )
        if okFields.isErr:
          valuesForError(
            config.questionOrder, config.questions, okFields.unsafeError(),
          )
        else:
          okFields.get() & @[""] # empty jev_error
    result = prep.inputFields & extra
  except CatchableError as e:
    result = prep.inputFields & valuesForError(
      config.questionOrder, config.questions, e.msg,
    )

proc processRowsOrdered(
    config: LoadedBatchConfig;
    headers: seq[string];
    readNext: RowSource;
    clients: seq[AsyncJevClient];
    runRequest: RunRowRequest;
    writeRow: proc(fields: seq[string]);
): Future[BatchResult] {.async.} =
  var jobs: Channel[RowJob]
  var prepared: Channel[PreparedRow]
  jobs.open()
  prepared.open()
  let batchSize = max(config.concurrency, 1)

  type PrepThreadArgs = tuple[
    hdrs: seq[string],
    jobCh: ptr Channel[RowJob],
    outCh: ptr Channel[PreparedRow],
    batch: int,
  ]

  proc prepThreadBody(args: PrepThreadArgs) {.thread.} =
    runPrepWorker(args.hdrs, args.jobCh[], args.outCh[], args.batch)

  var prepThread: Thread[PrepThreadArgs]
  createThread(
    prepThread,
    prepThreadBody,
    (headers, addr(jobs), addr(prepared), batchSize),
  )

  var rowCount = 0
  while true:
    let row = readNext()
    if row.isNone:
      break
    jobs.send RowJob(index: rowCount, row: row.get())
    rowCount += 1
  jobs.send RowJob(index: PrepEndSentinel, row: initTable[string, string]())

  var window: seq[InFlightRow] = @[]
  var rowsPrepared = 0
  var failures = 0
  var total = 0
  var nextClient = 0

  while window.len < config.concurrency and rowsPrepared < rowCount:
    let prep = prepared.recv()
    rowsPrepared += 1
    let client = clients[nextClient]
    nextClient = (nextClient + 1) mod clients.len
    window.add InFlightRow(
      future: makeRowFuture(config, client, prep, runRequest), client: client,
    )

  while window.len > 0:
    let inFlight = window[0]
    window.delete(0)
    let rowFields = await inFlight.future
    writeRow(rowFields)
    if rowFields.len > 0 and rowFields[^1].len > 0:
      failures += 1
    total += 1
    logProgress(total)
    if rowsPrepared < rowCount:
      let prep = prepared.recv()
      rowsPrepared += 1
      window.add InFlightRow(
        future: makeRowFuture(config, inFlight.client, prep, runRequest),
        client: inFlight.client,
      )

  joinThread(prepThread)
  BatchResult(outputPath: "", total: total, failures: failures)

proc runWith*(
    config: LoadedBatchConfig;
    headers: seq[string];
    readNext: RowSource;
    outputPath: string;
    clients: seq[AsyncJevClient];
    runRequest: RunRowRequest;
): Result[BatchResult, string] =
  if clients.len == 0:
    return err("at least one async client is required")
  let outHeaders = headers & extraHeaders(config.questionOrder, config.questions)
  writeRowsResult(
    outputPath,
    outHeaders,
    proc(writeRow: proc(fields: seq[string])): BatchResult =
      let batch = waitFor processRowsOrdered(
        config, headers, readNext, clients, runRequest, writeRow,
      )
      BatchResult(outputPath: outputPath, total: batch.total, failures: batch.failures),
  )

proc newClientPool(config: LoadedBatchConfig): Result[seq[AsyncJevClient], string] =
  var clients: seq[AsyncJevClient] = @[]
  for _ in 0 ..< config.concurrency:
    let created = newAsyncJevClient(
      defaultModel = config.defaultModel,
      timeoutSec = config.timeoutSec,
      retryPolicy = config.retryPolicy,
    )
    if created.isErr:
      for client in clients:
        client.close()
      return err(created.unsafeError().message())
    clients.add created.get()
  ok(clients)

proc run*(
    config: LoadedBatchConfig; inputPath: string; outputPath: string,
): Result[BatchResult, string] =
  let clientsResult = newClientPool(config)
  if clientsResult.isErr:
    return err(clientsResult.unsafeError())
  let clients = clientsResult.get()

  proc runRequest(
      client: AsyncJevClient; state: JsonContent; rowIndex: int,
  ): Future[Result[SystemOneResponse, string]] {.async.} =
    let r = await client.systemOne(state, config.questions)
    if r.isErr:
      return err(r.unsafeError().message())
    ok(r.get())

  defer:
    for client in clients:
      client.close()

  let nested = readRowsResult(
    inputPath,
    proc(headers: seq[string]; readNext: RowSource): Result[BatchResult, string] =
      runWith(config, headers, readNext, outputPath, clients, runRequest),
  )
  if nested.isErr:
    return err(nested.unsafeError())
  nested.get()
