import std/[unittest, options, tables]
import jev_nim_client
import results
import jevvypkg/config

suite "BatchConfig":
  test "loads choice question from YAML":
    let yaml = """
concurrency: 3
questions:
  - name: department
    type: choice
    question: Which team?
    options:
      - id: billing
        description: Payments
      - id: technical
        description: Bugs
"""
    let file = loadFromString(yaml).get()
    check file.concurrency == some(3)
    let (questions, _, _) = buildQuestions(file).get()
    check questions.len == 1
    check questions["department"].questionKind == qkChoice

  test "loads noul question from YAML":
    let yaml = """
questions:
  - name: is_spam
    type: noul
    question: Is this spam?
"""
    let file = loadFromString(yaml).get()
    let (questions, _, _) = buildQuestions(file).get()
    check questions["is_spam"].questionKind == qkNoul

  test "loads valid score question from YAML":
    let yaml = """
questions:
  - name: readiness
    type: score
    question: How ready?
    levels:
      - label: cold
        description: Low
      - label: hot
        description: High
"""
    let file = loadFromString(yaml).get()
    let (questions, _, _) = buildQuestions(file).get()
    check questions["readiness"].questionKind == qkScore

  test "rejects empty questions list":
    let file = loadFromString("questions: []").get()
    check buildQuestions(file).isErr

  test "rejects score with one level":
    let yaml = """
questions:
  - name: readiness
    type: score
    question: How ready?
    levels:
      - label: cold
        description: Low
"""
    let file = loadFromString(yaml).get()
    check buildQuestions(file).isErr

  test "rejects choice with empty options":
    let yaml = """
questions:
  - name: department
    type: choice
    question: Which team?
    options: []
"""
    let file = loadFromString(yaml).get()
    check buildQuestions(file).isErr

  test "rejects unknown question type":
    let yaml = """
questions:
  - name: x
    type: magic
    question: ???
"""
    let file = loadFromString(yaml).get()
    check buildQuestions(file).isErr

  test "loads bundled support-triage example":
    let file = loadFromFile("examples/support-triage.yaml").get()
    check file.questions[0].name == "department"
    check file.questions[0].qtype == "choice"

  test "resolve applies model timeout and concurrency overrides":
    let yaml = """
model: yaml-model
timeout_seconds: 42
concurrency: 4
delay_ms: 100
questions:
  - name: is_spam
    type: noul
    question: Spam?
"""
    let file = loadFromString(yaml).get()
    let loaded = resolve(file, some(2), some("cli-model"), none(int)).get()
    check loaded.concurrency == 2
    check loaded.delayMs == 100
    check loaded.defaultModel == "cli-model"
    check loaded.timeoutSec == 42.0
    check loaded.retryPolicy.maxRetries == 3

  test "resolve rejects concurrency below 1":
    let yaml = """
questions:
  - name: is_spam
    type: noul
    question: Spam?
"""
    let file = loadFromString(yaml).get()
    let badConc = resolve(file, some(0), none(string), none(int))
    check badConc.isErr
    check badConc.unsafeError() == "concurrency must be at least 1"

  test "resolve rejects negative delay_ms":
    let yaml = """
delay_ms: -1
questions:
  - name: is_spam
    type: noul
    question: Spam?
"""
    let file = loadFromString(yaml).get()
    let badDelay = resolve(file, none(int), none(string), none(int))
    check badDelay.isErr
    check badDelay.unsafeError() == "delay_ms must be non-negative"

  test "resolve defaults max_retries to 3 when omitted":
    let yaml = """
questions:
  - name: is_spam
    type: noul
    question: Spam?
"""
    let file = loadFromString(yaml).get()
    let loaded = resolve(file, none(int), none(string), none(int)).get()
    check loaded.retryPolicy.maxRetries == 3

  test "resolve applies max_retries from YAML and CLI override wins":
    let yaml = """
max_retries: 5
questions:
  - name: is_spam
    type: noul
    question: Spam?
"""
    let file = loadFromString(yaml).get()
    check resolve(file, none(int), none(string), none(int)).get().retryPolicy.maxRetries == 5
    check resolve(file, none(int), none(string), some(1)).get().retryPolicy.maxRetries == 1

  test "resolve max_retries 0 disables retries":
    let yaml = """
max_retries: 0
questions:
  - name: is_spam
    type: noul
    question: Spam?
"""
    let file = loadFromString(yaml).get()
    check resolve(file, none(int), none(string), none(int)).get().retryPolicy.maxRetries == 0

  test "resolve rejects negative max_retries":
    let yaml = """
max_retries: -1
questions:
  - name: is_spam
    type: noul
    question: Spam?
"""
    let file = loadFromString(yaml).get()
    let badRetries = resolve(file, none(int), none(string), none(int))
    check badRetries.isErr
    check badRetries.unsafeError() == "max_retries must be non-negative"
