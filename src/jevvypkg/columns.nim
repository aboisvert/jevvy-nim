import std/[math, strformat, strutils, tables]
import jev_nim_client/[answers, questions, content]
import results

const ErrorColumn* = "jev_error"

proc headerNamesFor*(questionId: string; q: Question): seq[string] =
  case q.questionKind
  of qkNoul:
    @[questionId & "_probability"]
  of qkChoice:
    @[questionId & "_choice", questionId & "_confidence"]
  of qkScore:
    @[questionId & "_score", questionId & "_nearest_label"]

proc extraHeaders*(questionOrder: seq[string]; questions: Questions): seq[string] =
  for id in questionOrder:
    if id in questions:
      for h in headerNamesFor(id, questions[id]):
        result.add h
  result.add ErrorColumn

proc valuesForError*(questionOrder: seq[string]; questions: Questions; message: string): seq[string] =
  for id in questionOrder:
    if id in questions:
      for _ in headerNamesFor(id, questions[id]):
        result.add ""
  result.add message

proc scoreNearestLabel(
    ans: ScoreAnswer; questionId: string; scoreLabels: Table[string, seq[string]],
): string =
  let idx = round(ans.score).int
  if questionId in scoreLabels and idx >= 0 and idx < scoreLabels[questionId].len:
    return scoreLabels[questionId][idx]
  let key = $idx
  if key in ans.legend:
    let c = ans.legend[key]
    if c.contentKind == jckString:
      let text = c.text
      let sep = text.find(": ")
      if sep >= 0:
        return text[0 ..< sep]
      return text
  ""

proc fieldsForQuestion*(
    response: SystemOneResponse;
    questionId: string;
    q: Question;
    scoreLabels: Table[string, seq[string]],
): Result[seq[string], string] =
  case q.questionKind
  of qkNoul:
    let noulResult = response.noul(questionId)
    if noulResult.isErr:
      return err("missing answer for question '" & questionId & "' in response")
    let a = noulResult.get()
    ok(@[&"{a.noul:.4f}"])
  of qkChoice:
    let choiceResult = response.choice(questionId)
    if choiceResult.isErr:
      return err("missing answer for question '" & questionId & "' in response")
    let a = choiceResult.get()
    ok(
      @[
        a.choice,
        &"{a.confidence:.4f}",
      ],
    )
  of qkScore:
    let scoreResult = response.score(questionId)
    if scoreResult.isErr:
      return err("missing answer for question '" & questionId & "' in response")
    let a = scoreResult.get()
    ok(
      @[
        &"{a.score:.4f}",
        scoreNearestLabel(a, questionId, scoreLabels),
      ],
    )

proc valuesForSuccess*(
    response: SystemOneResponse;
    questionOrder: seq[string];
    questions: Questions;
    scoreLabels: Table[string, seq[string]],
): Result[seq[string], string] =
  var fields: seq[string] = @[]
  for id in questionOrder:
    if id notin questions:
      continue
    let part = fieldsForQuestion(response, id, questions[id], scoreLabels)
    if part.isErr:
      return err(part.unsafeError())
    for cell in part.get():
      fields.add cell
  ok(fields)
