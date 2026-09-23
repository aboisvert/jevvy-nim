import std/[parseopt, os, strutils, options, syncio]
import results
import jevvypkg/[paths, config, runner]

const UsageLine* =
  "Usage: jevvy --input PATH [--config PATH] [--output PATH] [--concurrency N] [--model NAME] [--max-retries N]"

proc printUsage() =
  stderr.writeLine(UsageLine)
  stderr.writeLine("Example:")
  stderr.writeLine("  jevvy --input examples/support-triage.csv")

type CliArgs = object
  input: string
  config: Option[string]
  output: Option[string]
  concurrency: Option[int]
  model: Option[string]
  maxRetries: Option[int]
  showHelp: bool

proc appCommandLine(): seq[string] =
  ## Drop a leading `--` (nim r passes it through to the cached binary).
  result = commandLineParams()
  if result.len > 0 and result[0] == "--":
    result = result[1 ..^ 1]

proc parseCli(): CliArgs =
  var p = initOptParser(appCommandLine(), longNoVal = @["help", "h"])
  for kind, key, val in p.getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "input":
        result.input = val
      of "config":
        result.config = some(val)
      of "output":
        result.output = some(val)
      of "concurrency":
        result.concurrency = some(parseInt(val))
      of "model":
        result.model = some(val)
      of "max-retries":
        result.maxRetries = some(parseInt(val))
      of "help", "h":
        result.showHelp = true
      else:
        discard
    else:
      discard

proc main() =
  let cli = parseCli()
  if cli.showHelp or cli.input.len == 0:
    printUsage()
    quit(if cli.showHelp: 0 else: 1)

  let envCheck = checkApiKeyFromEnv()
  if envCheck.isErr:
    stderr.writeLine(envCheck.unsafeError())
    quit(1)

  let paths = resolve(cli.input, cli.config, cli.output)
  let file = loadFromFile(paths.configPath)
  if file.isErr:
    stderr.writeLine(file.unsafeError())
    quit(1)
  let loaded = resolve(file.get(), cli.concurrency, cli.model, cli.maxRetries)
  if loaded.isErr:
    stderr.writeLine(loaded.unsafeError())
    quit(1)

  let batch = run(loaded.get(), paths.inputPath, paths.outputPath)
  if batch.isErr:
    stderr.writeLine(batch.unsafeError())
    quit(1)

  let result = batch.get()
  stderr.writeLine(
    "Wrote " & result.outputPath & " (" & $result.total & " rows, " & $result.failures &
      " failed)",
  )
  if result.failures > 0:
    quit(1)

main()
