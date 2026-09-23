import std/[unittest, tables, sequtils]
import results
import jev_nim_client
import jevvypkg/columns
import fixtures

suite "AnswerColumns":
  let isUrgent = noul("Urgent?")
  var deptCriteria = initOrderedTable[string, string]()
  deptCriteria["billing"] = "Payments"
  deptCriteria["technical"] = "Bugs"
  let dept = choice("Team?", deptCriteria)

  var scoreLabels = initTable[string, seq[string]]()
  scoreLabels["sales_readiness"] = @["cold", "warm", "hot"]
  let readiness = score("How ready?", "cold", "warm", "hot")

  test "extraHeaders lists flat columns and jev_error":
    var qs = initOrderedTable[string, Question]()
    qs["is_urgent"] = isUrgent
    qs["department"] = dept
    qs["sales_readiness"] = readiness
    check extraHeaders(@["is_urgent", "department", "sales_readiness"], qs) ==
      @[
        "is_urgent_probability",
        "department_choice",
        "department_confidence",
        "sales_readiness_score",
        "sales_readiness_nearest_label",
        "jev_error",
      ]

  test "valuesForError pads blanks and sets jev_error":
    var qs = initOrderedTable[string, Question]()
    qs["is_urgent"] = isUrgent
    qs["department"] = dept
    let fields = valuesForError(@["is_urgent", "department"], qs, "rate limited")
    check fields.len == 4
    check fields[0 .. ^2].allIt(it.len == 0)
    check fields[^1] == "rate limited"

  test "valuesForSuccess extracts noul probability":
    var qs = initOrderedTable[string, Question]()
    qs["is_urgent"] = noul("Urgent?")
    let body = bodyForNoul("is_urgent", 0.75)
    let response = parseResponse(body, qs)
    check valuesForSuccess(response, @["is_urgent"], qs, scoreLabels).get() == @["0.7500"]

  test "valuesForSuccess extracts choice and confidence":
    var qs = initOrderedTable[string, Question]()
    qs["department"] = dept
    let body = bodyForChoice("department", "billing", [("billing", 0.8), ("technical", 0.2)])
    let response = parseResponse(body, qs)
    check valuesForSuccess(response, @["department"], qs, scoreLabels).get() ==
      @["billing", "0.9000"]

  test "valuesForSuccess extracts score and nearest label":
    var qs = initOrderedTable[string, Question]()
    qs["sales_readiness"] = readiness
    let body = bodyForScore("sales_readiness", 1.6, [(0, 0.1), (1, 0.3), (2, 0.6)])
    let response = parseResponse(body, qs)
    let fields = valuesForSuccess(response, @["sales_readiness"], qs, scoreLabels).get()
    check fields[0] == "1.6000"
    check fields[1] == "hot"

  test "valuesForSuccess fails when answer missing":
    var qs = initOrderedTable[string, Question]()
    qs["is_urgent"] = isUrgent
    qs["department"] = dept
    let body = bodyForNoul("is_urgent", 0.5)
    let response = parseResponse(body, qs)
    check valuesForSuccess(response, @["is_urgent", "department"], qs, scoreLabels).isErr
