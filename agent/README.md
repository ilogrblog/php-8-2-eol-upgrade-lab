# Saved agent proposals

Twelve proposal-only passes by an AI coding agent, recorded so the example can be replayed without an AI account.

## How they were made

- **Agent:** Claude Code subagents, using the `haiku`, `sonnet` and `opus` model aliases, two runs each.
- **Starting points:**
  - `after-rector-*`: the fixture after `rector.php`, with three deprecations left. The input gate report is `runs/gate-report-after-rector.txt`.
  - `legacy-only-*`: the untouched legacy fixture, with fourteen deprecations. The input gate report is `runs/gate-report-legacy.txt`.
- **Prompt:** `PROMPT.txt`, identical for every run apart from the working directory.
- **Access:** each run edited its own copy of the code and the tests. The agent was told not to execute anything, and none reported doing so.
- **Records:** `runs/<run>/proposal.diff` is the change, taken as a diff of the agent's copy against its starting point. `runs/<run>/agent-report.md` is the agent's own summary, as returned.

The two input gate reports predate the `lint-declared` gate and the test supervisor. Both were added after these runs, and the article explains why. The saved proposals and reports are unchanged historical records; only the checks that replay them have been updated.

## Verdicts

`bin/check.sh` applies every proposal to a fresh copy and runs all the gates. An `after-rector` proposal is applied on top of `steps/01-rector.diff` and `steps/02-requires-php.diff`.

| Run | Verdict | Gates that refused it | Why |
| --- | --- | --- | --- |
| after-rector-haiku-1 | refused | tests-8.2 to tests-8.5 | `exit()` replaced `E_USER_ERROR` and ended the test process before it finished |
| after-rector-haiku-2 | refused | tests-8.4, tests-8.5, phpstan-target | `if (defined('E_STRICT'))` still reads the deprecated constant on 8.4 and 8.5 |
| after-rector-sonnet-1 | accepted by the gates | none | `E_STRICT` replaced with 2048 |
| after-rector-sonnet-2 | accepted by the gates | none | `E_STRICT` replaced with 2048 |
| after-rector-opus-1 | accepted by the gates | none | `E_STRICT` entry removed |
| after-rector-opus-2 | **merged** as `steps/03-agent-accepted.diff` | none | `E_STRICT` entry removed |
| legacy-only-haiku-1 | refused | tests-8.2 to tests-8.5 | `static::class` moves the subclass to its own log channel |
| legacy-only-haiku-2 | refused | tests-8.2 to tests-8.5 | `get_class($this)` changes the channel, and `exit()` ends the process |
| legacy-only-sonnet-1 | accepted by the gates | none | |
| legacy-only-sonnet-2 | accepted by the gates | none | |
| legacy-only-opus-1 | accepted by the gates | none | |
| legacy-only-opus-2 | accepted by the gates | none | `get_class()` replaced with `__CLASS__` |

"Accepted by the gates" means every gate passed. It does not mean the change is right. Two passing proposals can still disagree, and removing the `E_STRICT` label versus keeping it as 2048 is a choice a reviewer makes.

## Limits

Twelve runs on one small fixture with one prompt is an observation, not a benchmark. Model behaviour changes between releases, so rerunning the prompt today may give different diffs. The saved diffs are what the checks replay.
