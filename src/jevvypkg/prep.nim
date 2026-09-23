import std/[tables, locks, strutils]
import malebolgia
import jev_nim_client/content
import ./csvio

type
  RowJob* = object
    index*: int
    row*: Table[string, string]

  PreparedRow* = object
    index*: int
    inputFields*: seq[string]
    state*: JsonContent

const PrepEndSentinel* = -1

proc prepareOneRow(headers: seq[string]; job: RowJob): PreparedRow {.gcsafe.} =
  PreparedRow(
    index: job.index,
    inputFields: rowValuesInOrder(headers, job.row),
    state: rowToState(job.row),
  )

proc runPrepWorker*(
    headers: seq[string];
    jobs: var Channel[RowJob];
    results: var Channel[PreparedRow];
    batchSize: int,
) {.gcsafe.} =
  var master = createMaster(activeProducer = true)
  while true:
    var batch: seq[RowJob] = @[]
    let first = jobs.recv()
    if first.index == PrepEndSentinel:
      break
    batch.add first
    while batch.len < batchSize:
      let recvMore = jobs.tryRecv()
      if not recvMore.dataAvailable:
        break
      let more = recvMore.msg
      if more.index == PrepEndSentinel:
        jobs.send more
        break
      batch.add more
    var prepared = newSeq[PreparedRow](batch.len)
    master.awaitAll:
      for i, job in batch:
        master.spawn prepareOneRow(headers, job) -> prepared[i]
    for row in prepared:
      results.send row
