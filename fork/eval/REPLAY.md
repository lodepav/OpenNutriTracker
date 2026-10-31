# Replay: a Claude Code subagent plays the model

The real-model checks (archive/PLAN-phases.md, phase 4) run first on answers written by a Haiku subagent
of Claude Code, not on a paid API call. The app's code runs unchanged from the request it
builds to the screen; only the HTTP call is swapped for `ReplayAiClient`
(`lib/fork/dev/replay_ai.dart`), which answers from files.

What this does not check: the clients' own request and response handling against a real
API (one live call per client does that), and models other than Claude's current Haiku
(OpenRouter does that). The subagent also runs under Claude Code's own instructions, so its
answers are close to the raw API's, not identical.

## The loop

1. **Record.** Run the app or the harness in replay mode. Every request with no answer is
   saved under `<dir>/requests/` as `<key>.json` (system prompt, tool, text) and `<key>.jpg`
   if it carries a photo, and fails as retryable.
2. **Answer.** Spawn one subagent (`model: haiku`) with the prompt below and `<dir>`.
3. **Replay.** Run the same thing again; the same requests now get the answers.

The key is a hash of the request body, so a changed prompt, photo or note is a new request.

### Photo test set

```sh
python3 -I fork/tools/fetch_eval_photos.py
FORK_EVAL_REPLAY=build/fork-eval/replay/haiku flutter test test/fork/eval   # records
# answer with the subagent
FORK_EVAL_REPLAY=build/fork-eval/replay/haiku flutter test test/fork/eval   # scores
```

The report lands in `build/fork-eval/<time>/report.md` as usual, under the model
`replay:haiku`.

### Progress-photo pairs (AI body comparison)

```sh
python3 -I fork/tools/fetch_body_pairs.py
FORK_EVAL_REPLAY=build/fork-eval/replay-bodies/haiku flutter test test/fork/eval/body_compare_eval_test.dart
# answer with the subagent: the prompt below, saying it stands in for a fitness app's
# progress-photo comparison and that each item's query is `key=value` as the system
# prompt says, though the tool is named for meal items
FORK_EVAL_REPLAY=build/fork-eval/replay-bodies/haiku flutter test test/fork/eval/body_compare_eval_test.dart
```

### In the app (emulator)

```sh
FAKE_AI=replay fork/tools/emulator.sh
# type or photograph meals; each unanswered one fails with "try again"
fork/tools/ai_replay.sh pull build/fork-eval/replay/app
# answer with the subagent
fork/tools/ai_replay.sh push build/fork-eval/replay/app
# retry in the app
```

## Subagent prompt

> You are standing in for the language model behind a nutrition app's meal logging. In
> `<dir>/requests/` each `<key>.json` is one API request the app made: `system` is the system
> prompt, `text` the user's message, `image` (if not null) the photo in that folder, and
> `tool` the one tool you must call. For every `<key>.json` with no `<dir>/answers/<key>.json`:
> read it and its photo, follow the system prompt exactly as the model would, and write the
> tool call's input to `<dir>/answers/<key>.json`: one JSON object matching
> `tool.input_schema`, nothing else. Answer each request on its own, from its own photo and
> text; do not look at other requests' answers, the app's code, or anything else in the
> repository. Write no other files. Do them one at a time: read one request and its photo,
> check that its answer does not exist yet, write it under that same key, then move to the
> next. End with one line per request: the key and the items you named.

A Haiku subagent once wrote answers under the wrong keys, and once re-answered requests that
already had answers. For Haiku, list the keys to answer in the prompt
(`for f in <dir>/requests/*.json; do k=$(basename $f .json); [ -f <dir>/answers/$k.json ] ||
echo $k; done`), and check the answers' timestamps afterwards.
