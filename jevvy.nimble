# Package

version       = "0.1.0"
author        = "Alex Boisvert"
description   = "Run CSV rows through Jev with YAML-defined questions"
license       = "Apache-2.0"
srcDir        = "src"
bin           = @["jevvy"]

requires "nim >= 2.2.12"
requires "https://github.com/aboisvert/jev-nim-client#head"
requires "https://github.com/Araq/malebolgia"
requires "yaml"
requires "results"

const nimFlags = "-d:ssl --threads:on --path:src --path:tests"

task test, "Run unit tests":
  for t in ["tests/tpaths", "tests/tconfig", "tests/tcsvio", "tests/tcolumns", "tests/trunner"]:
    exec "nim c -r " & nimFlags & " " & t & ".nim"

task build, "Build jevvy binary":
  exec "nim c -d:release " & nimFlags & " -o:out/jevvy src/jevvy.nim"
