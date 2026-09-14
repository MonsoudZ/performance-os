# Working in this codebase

PerformanceOS turns training, nutrition, body-composition and recovery logs into
coaching decisions a user can audit. Most of the conventions below exist to
protect that claim: if a recommendation cannot be traced to the evidence behind
it, the product does not work.

## Setup

```sh
bundle install
bin/rails db:prepare && bin/rails db:seed
bin/dev
```

`bin/ci` runs everything CI runs: rubocop, brakeman, bundler-audit, importmap
audit, the test suite, and a seed replant. Run it before pushing.

Tests are Minitest. `bin/rails test` for the suite, `bin/rails test path:line`
for one. `bin/rails test:system` runs the browser tests separately — `bin/rails
test` does not include them.

System tests use Capybara with Cuprite, which talks CDP to Chrome directly, so
there is no chromedriver whose version has to match the browser. Any Chrome on
the box is found automatically; set `CHROME_BIN` to override. Put a test there
only when the behaviour needs JavaScript — the logger's rows and volume readout,
a Turbo morph — and leave server-rendered output to controller tests, which are
an order of magnitude faster.

## The decision DAG

Recommendations are rows in `coaching_decisions`, linked parent-to-child through
`coaching_decision_links`. A decision is **immutable**: never update `output` or
`inputs` on a saved decision, and never delete one.

| `decision_type` | Written by | Links to children with role |
| --- | --- | --- |
| `daily_readiness` | `ReadinessEvaluator` | — |
| `double_progression` | `DoubleProgressionEvaluator` | — |
| `daily_nutrition` | `NutritionEvaluator` | — |
| `weekly_review` | `WeeklyEvidenceReview` | `readiness`, `progression`, `nutrition` |
| `daily_training` | `DailyTrainingOrchestrator` | `readiness`, `progression`, `nutrition` |

Those five types and four roles are also enforced by check constraints; adding
one means a migration.

To correct a decision, **retract** it (`decision.retract!(reason:)`) and write a
new one. Retracted decisions stay in the table and stay visible to the user — a
withdrawn recommendation is part of the record. `AccountDeletion` is the single
exception and deletes them: erasing an account erases its audit trail too. Every lookup that feeds a new
decision must scope to `active_evidence`; the `withdrawn` scope is its complement
and exists only so the UI can show what was taken back.

Every decision is readable at `/coaching_decisions/:id`, which renders `inputs`
and `output` through `coaching_decisions/_snapshot`. That partial assumes nothing
about their shape, so a new rule needs no view work; add a case to
`CoachingDecisionsHelper#decision_reference` if it snapshots a new kind of id, and
a suffix to `MEASUREMENT_SUFFIXES` if it records a new kind of measurement.

Say "withdrawn" to users and "retracted" in code. A new retraction reason needs
an entry in `CoachingDecision::RETRACTION_EXPLANATIONS` so it reads as a sentence
rather than a rule name, and decisions render through
`coaching_decisions/_progression` so the exercise page, the workout session and
the dashboard cannot drift apart.

### Writing an evaluator

Each one follows the same shape, and new ones should:

1. Own a `RULE_KEY` and a `RULE_VERSION`. Bump the version when the shape of
   `inputs` or `output` changes, and say why in a comment above it.
2. Snapshot everything the rule saw into `inputs` — ids, not associations.
3. Be **idempotent**: compare the current input snapshot against the latest
   decision — scoped to `active_evidence`, so a withdrawn one is never a match —
   and return that one unchanged if nothing moved. The recompute pipeline re-runs
   evaluators freely and relies on this. Two things make the comparison work:
   round-trip the snapshot through `JSON.parse(...to_json)` so it has the shapes
   Postgres hands back, and make sure `inputs` really does hold everything the
   rule read, or a re-run can short-circuit onto a conclusion that has moved on.
4. Set `confidence` from how much evidence actually existed, not from how
   confident the wording sounds.

### The recompute pipeline

A write that feeds a decision does not evaluate inline. It goes:

```
controller → TrainingRecomputable / NutritionRecomputable
           → Solid Queue job
           → DailyPlanRecompute (runs the evaluators)
           → Turbo::StreamsChannel.broadcast_refresh_to(user)
```

If you add a controller action that changes something an evaluator reads, call
the matching `recompute_*` helper.

`ApplicationJob` decides what happens when one of these fails, and both rules
depend on what the jobs are:

- **Transient database contention is retried** (`ApplicationJob::RETRYABLE_DATABASE_ERRORS`,
  five attempts with backoff), which is only safe because the evaluators are
  idempotent. Keep that list narrow: a `StatementInvalid` is usually a bug, and
  retrying one five times only delays finding it.
- **A job whose record no longer exists is discarded, not failed.** Every job
  here takes Active Record objects, so deleting an account raises on deserialize
  for anything still queued. It is logged — if it shows up for a live account,
  records are disappearing some other way.

## Training targets and blocks

An `ExercisePrescription` stores a baseline; a `Mesocycle` owns the scheme. What
a lift is actually asked to do on a day is composed by `TrainingTargets`, never
read off the prescription:

```ruby
TrainingTargets.new(user, on: date).targets_for(prescription)
#=> rep_min, rep_max, target_rir_min, target_rir_max, working_sets, source
```

- **Views must not print `rep_min`/`working_sets` to describe the present.** Use
  `training_targets_for(prescription)`. `ExercisePrescription#target_label` is
  still right for a *past* target, which is a record of what was stored.
- **The block owns the scheme; the day owns the volume.** Reps, RIR and the
  baseline set count come from `TrainingTargets`. The accumulation ramp and the
  deload/recovery cuts stay in `DailyTrainingOrchestrator`, which is the thing
  that knows about today, and apply whether or not the target follows the scheme.
- `follows_block_scheme: false` means "this rep range is mine", not "ignore the
  block" — such a target still gets the block's volume ramp.
- A rule that reads targets must resolve them **on the date it is reasoning
  about**, not today. `DoubleProgressionEvaluator` uses the session's local date,
  so a decision records what was prescribed at the time.

## Units and measurements

The database stores **kilograms, centimetres and metres**, always, for every
user. Evaluators, decisions and the progression engine are unit-agnostic, so
switching unit systems changes nothing about stored data.

Conversion happens at exactly two boundaries:

- **Out**: `MeasurementsHelper` — `weight`, `length`, `distance`, `pace`. Views
  must never print a bare `_kg`/`_cm`/`_meters` attribute or a literal unit.
- **In**: `MeasurementParams#to_canonical_units` — controllers name their
  measurement fields explicitly. Do not infer them from a `_kg` suffix; a silent
  name-based rule would capture the next column that happens to match and
  corrupt stored training data.

Two rules make measurements trustworthy, and both have tests that will fail if
you break them:

- **Never round a measurement to a fixed width.** Values render at the precision
  they have, trailing zeros trimmed. Only *derived* figures — a 1RM projection,
  a session volume — pass `precision:`, and they pass it at the call site.
- **Storage scale must exceed display scale.** `Units::WEIGHT_SCALE` is 6 because
  pounds are shown to 4; anything less lets the stored rounding leak back and a
  user's entry silently changes when they re-save. Arithmetic is BigDecimal,
  never Float.

Decision prose stays in canonical units — a decision is a record. Where a
decision carries the numbers behind its sentence, the *view* rebuilds it in the
reader's units (`progression_headline`, `lift_headline`, `conditioning_progress`)
rather than doing string surgery on stored text.

## Conventions elsewhere

- **Controllers are thin.** Anything with a rule in it belongs in `app/services`.
- **Effective-dated records** (`ExercisePrescription`, `GoalPeriod`, `Mesocycle`)
  use the `DateRanged` concern. Editing one supersedes it rather than mutating
  it, so history stays readable.
- **Invariants live in the database** as check constraints and partial unique
  indexes — one active goal per user, valid rep ranges, retraction consistency.
  Add the constraint as well as the validation.
- **No Redis.** Solid Queue, Solid Cable and Solid Cache are all Postgres-backed.
- **No JS build step.** Importmaps and Propshaft. Stimulus controllers address
  elements through `data-*-target`, never through an `aria-label` or a class name
  — those are user-facing strings that will be reworded.
- **CSP is enforced.** Inline `<script>` and `<style>` need the request nonce;
  inline `style=` attributes are allowed. If something renders but does not work,
  check the console for a CSP violation before anything else.

## Wearable ingestion

Samples arrive at `POST /api/v1/wearable_sync` authenticated by a per-device
bearer token, land in `wearable_samples`, and are turned into records by
`WearableDayMaterializer` — one job per affected local day, then one pass of the
evaluator pipeline over the result. `WearableSample::METRIC_UNITS` is the list of
what the server accepts and the unit each metric must arrive in; the server
converts nothing and the check constraint enforces the same list, so adding a
metric means a migration.

Three rules are easy to break:

- **The device's unit is canonical.** A sample whose `unit` disagrees with its
  `metric_type` is rejected rather than converted — only the device knows what it
  measured, so a mismatch means the payload is wrong.
- **Ingestion is insert-only, except for daily totals.** HealthKit UUIDs name
  immutable samples, so replaying a batch is safe. Steps and energy
  (`WearableSample::DAILY_TOTAL_METRICS`) are summed on the device and keyed by
  date instead, because they are still accruing when first sent; those, and only
  those, may be corrected in place.
- **A materialized record is created once and then left alone**, so a session the
  user corrected by hand survives the next sync. The exception is the day's
  weigh-in, which is derived from that day's samples and re-derives when more
  arrive.

A day that synced only steps must not produce a readiness check-in — an
unanswered day on the record as an answered one gets scored, and a score built
from nothing is worse than no score.

## Deleting an account

`AccountDeletion` is the only thing that calls `user.destroy`, and two rules
stand behind it:

- **The order of `has_many` declarations on `User` is load-bearing.** Rails
  destroys them in declaration order and several reference each other, so
  anything pointing at another row is declared before the row it points at.
- **Two guards protect a live account and have to be lifted deliberately.** A
  cited decision cannot be deleted (model and database), and an exercise with
  logged sets cannot be deleted (`restrict_with_error`). The service releases
  citations and workout history first, then reloads the user — those guards ask
  the *association* whether it is empty, and the objects that lifted them still
  hold loaded, stale collections that say otherwise.

Adding a `has_many` to `User` means placing it in that order and extending
`AccountDeletionTest`'s fixture, which populates every association on purpose.

## Empty states

An empty state names the action that fills it and links to it. "No workouts
logged yet" is a description; a user who reads it still has to work out where to
go. What a new account is missing is answered in one place — `OnboardingProgress`
— which both `/onboarding` and the dashboard read, because the dashboard is the
only route back to that checklist once a user has left it.

## Things that are easy to get wrong

- Any URL a client supplies and the server later requests is an SSRF vector.
  Push endpoints are allow-listed against vendor hosts in `PushSubscription` for
  this reason.
- `bundler-audit` only sees gems in `Gemfile.lock`. Default gems like `resolv`
  are invisible to it unless declared in the `Gemfile`.
- **Every table needs a primary key, including the derived ones.** Four here
  were created with `id: false` because each row is addressed by a natural key —
  one per user per day, one per exercise/muscle pair. Active Record builds every
  UPDATE and DELETE for a loaded record around the primary key, so with none it
  emits `WHERE "" IS NULL` and Postgres rejects it: `save!`, `update!`, `destroy`
  and `dependent: :destroy` all fail, and only on the *second* write for a given
  key, so the bug ships looking fine. They have ids now; `PrimaryKeysTest` fails
  if a keyless table appears again. The unique index on the natural key is still
  what enforces "one per user per day" — the id does not.
- Catalog exercises (`user_id: nil`) survive `db:seed:replant`. Tests must not
  assume an empty `exercises` table — use distinctive names and assert on
  presence rather than totals — and note that a test database prepared with
  `db:reset` (which seeds) starts with them while `db:test:prepare` does not.
- `assert_select "sel", "some message"` treats the second argument as a **text
  match**, not a message, and `assert_select "sel", text: "x", "message"` is a
  syntax error because a positional argument cannot follow a hash. Either brace
  the hash — `assert_select "sel", { text: "x" }, "message"` — or put the
  rationale in a comment above the assertion. The same applies to `assert_text`,
  where two positional strings are read as `(type, text)`.
- Several classes uppercase their text in CSS (`.eyebrow`, `.confidence`, table
  headers). Capybara matches *rendered* text, so a system test asserting
  "Session complete" fails against "SESSION COMPLETE". Assert on a heading or
  body copy the stylesheet leaves alone, or use a regexp.
