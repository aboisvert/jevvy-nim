import std/[os, strutils, tables, options, streams]
import yaml/[dom, loading]
import jev_nim_client
import results

const ScalaDefaultTimeoutSec = 30.0

type
  ChoiceOptionYaml* = object
    id*: string
    description*: string

  ScoreLevelYaml* = object
    label*: string
    description*: string

  QuestionYaml* = object
    name*: string
    qtype*: string
    question*: string
    options*: seq[ChoiceOptionYaml]
    levels*: seq[ScoreLevelYaml]

  BatchConfigFile* = object
    model*: Option[string]
    timeoutSeconds*: Option[int]
    concurrency*: Option[int]
    delayMs*: Option[int64]
    maxRetries*: Option[int]
    questions*: seq[QuestionYaml]

  LoadedBatchConfig* = object
    defaultModel*: string
    timeoutSec*: float
    retryPolicy*: RetryPolicy
    concurrency*: int
    delayMs*: int64
    questions*: Questions
    questionOrder*: seq[string]
    scoreLabels*: Table[string, seq[string]]

proc yamlScalar(node: YamlNode): string =
  if node.kind != yScalar:
    raise newException(ValueError, "expected scalar")
  node.content

proc yamlOptString(mapping: YamlNode; key: string): Option[string] =
  try:
    let n = mapping[key]
    if n.isNil:
      none(string)
    else:
      some(yamlScalar(n).strip())
  except KeyError:
    none(string)

proc yamlOptInt(mapping: YamlNode; key: string): Option[int] =
  try:
    let n = mapping[key]
    if n.isNil:
      none(int)
    else:
      some(parseInt(yamlScalar(n)))
  except KeyError:
    none(int)
  except ValueError:
    none(int)

proc yamlOptInt64(mapping: YamlNode; key: string): Option[int64] =
  try:
    let n = mapping[key]
    if n.isNil:
      none(int64)
    else:
      some(parseInt(yamlScalar(n)).int64)
  except KeyError:
    none(int64)
  except ValueError:
    none(int64)

proc parseChoiceOptions(node: YamlNode): seq[ChoiceOptionYaml] =
  if node.kind != ySequence:
    raise newException(ValueError, "options must be a list")
  for item in node.items:
    if item.kind != yMapping:
      raise newException(ValueError, "option must be a mapping")
    result.add ChoiceOptionYaml(
      id: yamlScalar(item["id"]),
      description: yamlScalar(item["description"]),
    )

proc parseScoreLevels(node: YamlNode): seq[ScoreLevelYaml] =
  if node.kind != ySequence:
    raise newException(ValueError, "levels must be a list")
  for item in node.items:
    if item.kind != yMapping:
      raise newException(ValueError, "level must be a mapping")
    result.add ScoreLevelYaml(
      label: yamlScalar(item["label"]),
      description: yamlScalar(item["description"]),
    )

proc parseQuestion(node: YamlNode): QuestionYaml =
  if node.kind != yMapping:
    raise newException(ValueError, "question must be a mapping")
  var q = QuestionYaml(name: yamlScalar(node["name"]))
  try:
    q.qtype = yamlScalar(node["type"])
  except KeyError:
    raise newException(ValueError, "question missing type")
  q.question = yamlScalar(node["question"])
  try:
    q.options = parseChoiceOptions(node["options"])
  except KeyError:
    discard
  try:
    q.levels = parseScoreLevels(node["levels"])
  except KeyError:
    discard
  q

proc parseBatchConfigFile(root: YamlNode): BatchConfigFile =
  if root.kind != yMapping:
    raise newException(ValueError, "config root must be a mapping")
  var file = BatchConfigFile()
  file.model = yamlOptString(root, "model")
  file.timeoutSeconds = yamlOptInt(root, "timeout_seconds")
  file.concurrency = yamlOptInt(root, "concurrency")
  file.delayMs = yamlOptInt64(root, "delay_ms")
  file.maxRetries = yamlOptInt(root, "max_retries")
  try:
    let qs = root["questions"]
    if qs.kind != ySequence:
      raise newException(ValueError, "questions must be a list")
    for item in qs.items:
      file.questions.add parseQuestion(item)
  except KeyError:
    raise newException(ValueError, "config missing questions")
  file

proc loadFromString*(yamlText: string): Result[BatchConfigFile, string] =
  try:
    var root: YamlNode
    load(yamlText, root)
    ok(parseBatchConfigFile(root))
  except CatchableError as e:
    err("invalid YAML config: " & e.msg)

proc loadFromFile*(path: string): Result[BatchConfigFile, string] =
  try:
    let text = readFile(path)
    loadFromString(text)
  except CatchableError as e:
    err("cannot read config " & path & ": " & e.msg)

proc jevvyDefaultRetryPolicy*(maxRetries: int): RetryPolicy =
  var p = defaultRetryPolicy()
  p.maxRetries = maxRetries
  p.backoffInitial = 0.5
  p.backoffMax = 8.0
  p.backoffJitter = 0.2
  p.respectRetryAfter = true
  p.retryConnection = true
  p.retryTimeout = true
  p.totalBudgetSec = none(float)
  p.httpStatuses = defaultRetryHttpStatuses()
  p

proc validateQuestion*(name: string; q: Question): Result[void, string] =
  var one = initOrderedTable[string, Question]()
  one[name] = q
  let checked = validateQuestions(one)
  if checked.isErr:
    return err(checked.unsafeError())
  ok()

proc buildQuestion*(q: QuestionYaml): Result[Question, string] =
  let typ = q.qtype.strip().toLowerAscii()
  case typ
  of "noul":
    ok(noul(q.question))
  of "choice":
    if q.options.len == 0:
      return err("choice question '" & q.name & "' requires non-empty options")
    var criteria = initOrderedTable[string, string]()
    for o in q.options:
      criteria[o.id] = o.description
    let built = choice(q.question, criteria)
    let checked = validateQuestion(q.name, built)
    if checked.isErr:
      return err(checked.unsafeError())
    ok(built)
  of "score":
    if q.levels.len < 2:
      return err("score question '" & q.name & "' requires at least 2 levels")
    var levels: seq[string] = @[]
    for lv in q.levels:
      levels.add lv.label & ": " & lv.description
    let built = score(q.question, levels)
    let checked = validateQuestion(q.name, built)
    if checked.isErr:
      return err(checked.unsafeError())
    ok(built)
  else:
    err(
      "question '" & q.name & "' has unknown type '" & q.qtype &
        "' (expected noul, choice, or score)",
    )

proc buildQuestions*(
    file: BatchConfigFile,
): Result[(Questions, seq[string], Table[string, seq[string]]), string] =
  if file.questions.len == 0:
    return err("config must define at least one question")
  var qs = initOrderedTable[string, Question]()
  var order: seq[string] = @[]
  var scoreLabels = initTable[string, seq[string]]()
  for qy in file.questions:
    let builtResult = buildQuestion(qy)
    if builtResult.isErr:
      return err(builtResult.unsafeError())
    let built = builtResult.get()
    if qy.name in qs:
      discard # Scala allows duplicates; keep first
    qs[qy.name] = built
    order.add qy.name
    if qy.levels.len > 0:
      var labels: seq[string] = @[]
      for lv in qy.levels:
        labels.add lv.label
      scoreLabels[qy.name] = labels
  let validated = validateQuestions(qs)
  if validated.isErr:
    return err(validated.unsafeError())
  ok((qs, order, scoreLabels))

proc resolveModel(file: BatchConfigFile; cliModel: Option[string]): string =
  if cliModel.isSome:
    cliModel.get()
  elif file.model.isSome:
    file.model.get()
  else:
    ""

proc resolve*(
    file: BatchConfigFile;
    cliConcurrency: Option[int];
    cliModel: Option[string];
    cliMaxRetries: Option[int] = none(int),
): Result[LoadedBatchConfig, string] =
  let builtAll = buildQuestions(file)
  if builtAll.isErr:
    return err(builtAll.unsafeError())
  let (questions, order, scoreLabels) = builtAll.get()
  let concurrency = cliConcurrency.get(file.concurrency.get(1))
  if concurrency < 1:
    return err("concurrency must be at least 1")
  let delayMs = file.delayMs.get(0'i64)
  if delayMs < 0:
    return err("delay_ms must be non-negative")
  let maxRetries = cliMaxRetries.get(file.maxRetries.get(3))
  if maxRetries < 0:
    return err("max_retries must be non-negative")
  let timeoutSec =
    if file.timeoutSeconds.isSome:
      file.timeoutSeconds.get().float
    else:
      ScalaDefaultTimeoutSec
  ok(
    LoadedBatchConfig(
      defaultModel: resolveModel(file, cliModel),
      timeoutSec: timeoutSec,
      retryPolicy: jevvyDefaultRetryPolicy(maxRetries),
      concurrency: concurrency,
      delayMs: delayMs,
      questions: questions,
      questionOrder: order,
      scoreLabels: scoreLabels,
    ),
  )

proc checkApiKeyFromEnv*(): Result[void, string] =
  let created = newJevClient()
  if created.isErr:
    return err(created.unsafeError().message())
  let client = created.get()
  client.close()
  ok()
