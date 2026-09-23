import std/[strutils, options]

## Default config and output paths from the input CSV stem.

proc stem*(input: string): string =
  let lower = input.toLowerAscii()
  if lower.endsWith(".csv"):
    result = input[0 ..< input.len - 4]
  else:
    result = input

proc defaultConfig*(input: string): string =
  stem(input) & ".yaml"

proc defaultOutput*(input: string): string =
  stem(input) & "-out.csv"

proc resolve*(
    input: string; config: Option[string]; output: Option[string],
): tuple[configPath: string; inputPath: string; outputPath: string] =
  (
    configPath: config.get(defaultConfig(input)),
    inputPath: input,
    outputPath: output.get(defaultOutput(input)),
  )
