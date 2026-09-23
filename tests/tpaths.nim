import std/[unittest, options]
import jevvypkg/paths

suite "BatchPaths":
  test "default paths from csv input":
    check defaultConfig("examples/foo.csv") == "examples/foo.yaml"
    check defaultOutput("examples/foo.csv") == "examples/foo-out.csv"

  test "strips .csv case-insensitively":
    check stem("FOO.CSV") == "FOO"
    check defaultConfig("FOO.CSV") == "FOO.yaml"
    check defaultOutput("FOO.CSV") == "FOO-out.csv"

  test "no csv suffix uses full path as stem":
    check defaultConfig("data") == "data.yaml"
    check defaultOutput("data") == "data-out.csv"

  test "resolve preserves explicit overrides":
    let paths = resolve("examples/foo.csv", some("custom.yaml"), some("/tmp/out.csv"))
    check paths.configPath == "custom.yaml"
    check paths.inputPath == "examples/foo.csv"
    check paths.outputPath == "/tmp/out.csv"

  test "resolve applies defaults when options empty":
    let paths = resolve("examples/foo.csv", none(string), none(string))
    check paths.configPath == "examples/foo.yaml"
    check paths.inputPath == "examples/foo.csv"
    check paths.outputPath == "examples/foo-out.csv"
