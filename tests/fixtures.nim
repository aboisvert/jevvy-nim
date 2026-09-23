import std/tables
import jev_nim_client
import jev_nim_client/wire

proc parseResponse*(body: string; questions: Questions): SystemOneResponse =
  let decoded = decodeSystemOneResponse(body, initTable[string, string]())
  if decoded.isErr:
    raise newException(ValueError, decoded.unsafeError().message())
  decoded.get()

proc bodyForNoul*(name: string; probability: float): string =
  """{"model":"test","answers":{"""" & name & """":{"type":"noul","noul":""" & $probability & "}}}"

proc bodyForChoice*(
    name, choice: string; probs: openArray[(string, float)],
): string =
  var probFields = ""
  for i, p in probs:
    if i > 0:
      probFields.add ","
    probFields.add "\"" & p[0] & "\":" & $p[1]
  result =
    "{\"model\":\"test\",\"answers\":{\"" & name & "\":{\"type\":\"choice\",\"choice\":\"" &
    choice & "\",\"probabilities\":{" & probFields & "},\"confidence\":0.9}}}"

proc bodyForScore*(
    name: string; score: float; levelProbs: openArray[(int, float)],
): string =
  var probFields = ""
  for i, p in levelProbs:
    if i > 0:
      probFields.add ","
    probFields.add "\"" & $p[0] & "\":" & $p[1]
  """{"model":"test","answers":{"""" & name & """":{"type":"score","score":""" & $score &
    ""","legend":{"0":"cold","1":"warm","2":"hot"},"probabilities":{""" & probFields &
    """},"confidence":0.85}}}"""
