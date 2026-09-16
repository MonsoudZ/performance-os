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

## The exercise catalog

`db/catalog/exercises.yml` is the shared catalog, owned by nobody
(`user_id: nil`) and imported idempotently by `bin/rails catalog:import`, so
adding an entry and re-running it is the whole job.

- **`staple: true` is what `ProgramGenerator` may prescribe on its own**, and it
  is opt-in. The generator picks the first compound in a muscle group, ranked by
  modality then *name*, so without this every exercise added to the catalog
  competes to become somebody's program: growing the catalog once made a barbell
  clean outrank a barbell row for "back" on the alphabet alone, and a decline
  dumbbell press outrank a flat one. A staple is the canonical movement, not
  every variant of it — the set is deliberately small and does not grow just
  because the catalog does.
- Everything else is fully available to log, to search, and to pick by hand. A
  user's own exercises are never staples.
- **Tests must not pin the catalog's size.** Assert on presence, or against
  `Exercise.where(user_id: nil).count`, so growing it fails nothing.
- The catalog is larger than `Api::V1::ExercisesController::MAX_LIMIT`, so
  `/api/v1/exercises` pages: `meta.next_offset` is the offset to ask for next and
  `nil` on the last page. One request stopped being enough the moment the catalog
  passed 100.

## A session and a workout are the same shape

A `WorkoutTemplate` and a logged `WorkoutSession` both answer "which exercises,
in which order", so `WorkoutTemplateFromSession` reads one out of the other and
the second time somebody trains it costs a name and a button rather than
rebuilding the workout by hand.

- **Warming up on something is not training it**, so an exercise with only
  warm-up sets is left out — unless the whole session was warm-ups, which is
  still worth saving as what it was rather than failing as an empty workout.
- **The suggested name steps around one already taken.** Running a template and
  saving the result is the ordinary case, so a prefilled name that collides would
  be a validation error on something the user never typed. A name they *do* type
  is never silently renamed.
- Saving lands in the template editor, because the day to schedule it on is the
  one thing a session cannot supply.
- The template is what gets created, so the action lives on
  `WorkoutTemplatesController` even though the route hangs off a session.

## What the logger opens with

`WorkoutLogPrefill` decides what is already in each row, and it is the
difference between logging a set and typing one.

- **Weight** comes from the latest `double_progression` decision for that
  prescription, falling back to the heaviest working set last time.
- **Reps and RIR depend on whether the load moved.** Repeating a load, the guess
  is what *that set* actually did — you are trying to beat last time, so
  matching it should cost no typing. After an increase, the reps reset to
  `rep_min`: that is what earning the increase costs under double progression,
  and opening at `rep_max` asks the user to correct the app on every row, which
  is what it used to do.
- With no prior set the target stands, and a set planned beyond what was done
  last time falls back to the target rather than blanking.
- Prefilling at all means somebody can save numbers they did not do. That was
  already true; the change is that the plausible guess replaced the optimistic
  one, which is the safer of the two to leave unread.

## One-tap food

`FrequentFoods` decides which foods the nutrition page offers as a single tap,
and at what portion.

- **Ranked by how often a food is logged**, not by what was logged last. Pure
  recency meant a few unusual meals pushed the staples off the list exactly when
  they were wanted. `WINDOW_DAYS` bounds it so something dropped from the
  rotation stops being offered.
- **The portion is the memory worth keeping** — the last quantity logged for that
  food, so nobody retypes "80" every morning.
- **The meal is the one happening now**, from `FoodLogEntry.meal_type_for`, not
  the meal the food was last eaten at. Carrying the old one over filed an entry
  stamped 8pm under breakfast, and this page groups by meal, so the record
  contradicted its own timestamp.

## The check-in is not prefilled, deliberately

`ReadinessEvaluator` scores sleep quality, soreness, fatigue and stress, and
those four are the part only the user knows. Sleep *hours* prefills from the
watch because the watch measured it; the four ratings are `required` and start
empty, and should stay that way.

Prefilling them from yesterday would make "save without reading" record a day
that was never answered — the same mistake as materialising a readiness check-in
from a day that only synced steps, and the same reason that is forbidden: a score
built from nothing is worse than no score. Reducing the taps here means finding
something that measures the user, not something that guesses for them.

## A lift with no target is the quiet failure

`DoubleProgressionEvaluator` skips any exercise it cannot find a prescription
for, so no decision is ever written for that lift, and `WorkoutLogPrefill` falls
back to the heaviest working set last time. It logs fine and never progresses —
the app repeating your numbers back at you, which is the one failure it exists to
prevent. Nothing said so until `TrainingTargetCoverage` did: the templates page
marks each uncovered lift and says what it costs, because the split is where you
would notice.

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

**Better still, a new rule writes no measurement into its prose at all.** Every
view that prints a stored sentence raw then shows the right thing to everybody,
and nothing depends on remembering which helper to route it through.
`DoubleProgressionEvaluator` used to write "Deload to 85 kg", and the audit
page's own heading showed that to an imperial reader directly above a table
rendering the same number in pounds. From `rule_version` 4.0.0 the sentence names
no unit and the weights stay where they always were, in `current_weight_kg` and
`next_weight_kg`.

Decisions already written are immutable, so `decision_headline` rebuilds an older
progression sentence from those weights wherever one is displayed. Their stored
text still appears verbatim in the snapshot table, which is the record of what
was written — the fix is that nothing new writes a unit there, not that history
gets rewritten.

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

## The weekly review runs itself

`WeeklyEvidenceReview` decides whether a week of evidence justifies changing the
calorie target, and `NutritionAdjustmentEvaluator` turns that verdict into one.
It used to be reachable only from a button on `/weekly_review`, which made the
one rule that changes a target depend on somebody remembering it.

- **`ScheduledWeeklyReviewJob` runs hourly and acts at each user's own
  `REVIEW_HOUR`**, like `CheckInReminderJob`, so a review lands on the week the
  user lives in rather than on UTC's. The button stays, for asking again before
  the next one is due.
- **It checks every day, not only when the week turns.** A review missed because
  the worker was down is picked up the next morning rather than skipped. The
  evaluator is idempotent, so a redundant run would be free anyway — the check
  only keeps one off the queue.
- **A week the account recorded nothing in gets no review.** Otherwise a dormant
  account collects "keep collecting evidence" on the record every week forever,
  which is the same mistake as scoring a readiness day nobody answered. Partial
  evidence *is* reviewed: that user is training and being told what is missing is
  the point.
- **An adjustment expires** (`NutritionAdjustmentEvaluator::AUTHORITY_DAYS`).
  `NutritionTargetResolver` prefers an adjustment over every other way of
  arriving at a target, so unbounded it kept setting calories long after the week
  it reasoned about, beating an expenditure estimate recomputed daily. Two weeks
  tolerates one missed review; after that the resolver falls back to measured
  evidence. Scheduling is why this should rarely fire — it is the net, not the
  plan.
- Decisions written before `rule_version` 2.0.0 carry no `expires_on`, and the
  evaluator's short-circuit means they are never rewritten, so the resolver
  derives the bound from `effective_on` when the field is absent. Old rows are
  held to the same rule rather than living forever by accident.

## The native API

`Api::V1::BaseController` authenticates a bearer token against a `Session` row,
so a phone is a signed-in device like any other: it appears in the list at
`/profile/edit`, it is ended from there, and `Current.user` works from an API
request exactly as it does from a browser one.

- **A token expires with the session that issued it.** There is deliberately no
  token expiry column — `Session::IDLE_TIMEOUT` and `ABSOLUTE_LIFETIME` are the
  only two clocks, and `authenticate_api_token` scopes to `active`. A third
  clock would be one more thing to drift out of step, and ending a device from
  the signed-in list has to end its token in the same breath.
- **SHA-256, not bcrypt.** The token is 256 random bits rather than something a
  person chose, so there is nothing to slow an attacker down over, and a plain
  digest makes the lookup one indexed read. Only the digest is stored; the token
  is shown once.
- **`api_token_digest` is a credential**, so it is in
  `AccountExport::EXCLUDED_COLUMNS`. It has to be named there separately —
  `except:` matches a column name exactly, so `token_digest` (the wearable
  device's) does not cover it.
- **Measurements cross this boundary in stored units**, like the export and for
  the same reason: it is a record being transported, not a rendering. The
  profile carries `unit_system` so the client converts at its own display edge.
  **So an API controller never calls `MeasurementParams#to_canonical_units`** —
  that is the web forms' converter, and a form posts whatever unit it displayed.
  `Api::V1::WorkoutSessionsController` did call it, which read an imperial
  user's kilograms as pounds: a round trip through the phone turned 100 kg into
  45.36. Worse, it only did so for a payload whose nested sets arrived as a hash
  keyed by index, because the converter's nested branch tests
  `respond_to?(:each_value)` and an array does not answer to that — so the same
  logical payload stored two different weights depending on how the client
  spelled it, and the array form a JSON client reaches for first was the one
  that looked correct.
- Sign-in has its own `Rack::Attack` throttle. The web one keys on `/session`
  and would never see `/api/v1/session`.
- The exercise catalog stays public and IP-throttled — a client needs it before
  it has anywhere to sign in to.

### Nutrition and the check-in over the API

Both write through the same services and the same recompute pipeline the web
uses, so a day logged from the phone is indistinguishable from one logged in a
browser. Four things here are worth keeping:

- **The four readiness ratings are refused, not defaulted.** On the web their
  `required` attributes stop an empty check-in; that markup does not reach a
  native client, so `Api::V1::ReadinessCheckInsController` names
  `DailyReadinessInput::SUBJECTIVE_FIELDS` and rejects a post missing any of
  them. Without it a phone could post an empty body and have the day scored from
  nothing — the same failure as materialising a check-in from a day that only
  synced steps. `ReadinessCheckInSerializer` reads the other half of the rule:
  an unanswered rating comes back null and nothing fills it in.
- **The day's numbers are read off the `daily_nutrition` decision**, as the
  nutrition page reads them, rather than summed again in the serializer. Summing
  separately would put a second, differently-derived total beside the one the
  audit page shows. The decision is a recompute behind after a log and there is
  none at all until something recomputes the day, which is what the web does too;
  the entries themselves are always live.
- **A logged entry's macros are computed from the food and the portion.** The
  client says what and how much; the server says what that is worth. Accepting
  both would let a portion and its macros disagree, and the entry is the evidence
  a nutrition decision is built from.
- **`/api/v1/foods/search` spends an outbound Open Food Facts request**, so it
  carries its own `Rack::Attack` throttle — the web rule keys on `/foods/search`
  and would never see it. It counts against the token's **digest**, not the
  token: the digest is what the database already stores and is worthless to
  whoever learns it, and keying on the device rather than the IP means a gym's
  shared address does not make one phone's typing count against another's.

### Weighing in over the API

A weigh-in is the evidence behind the calorie target — it feeds the weight
trend, the trend feeds the adaptive expenditure estimate, and that feeds
`NutritionTargetResolver` — so `Api::V1::BodyMetricsController` recomputes the
day a weigh-in was *measured on*, not today, exactly as the web does.

- **`source` is not accepted from the client.** A row claiming `healthkit` is
  one the next sync overwrites: `WearableBodyMassMaterializer` finds its row by
  (date, source) and re-derives it. A weight somebody typed has to be a row
  nothing else owns, so the controller forces `manual` and the serializer
  reports `derived` so a client can say that removing a watch-derived row only
  makes it come back.
- **The trend ships alongside the raw readings.** Every rule downstream reads the
  smoothed `ewma_kg`, never `raw_kg` — a single morning reading moves with water
  and yesterday's salt — but a client drawing only the trend cannot show the user
  the reading it is asking them to trust.
- `body_fat_pct` is serialized because the column exists and the export carries
  it, and is **not** accepted on write: nothing in the app reads it yet, and a
  write path would only manufacture data no rule consumes.

`DailyReadinessInput#source_after_check_in` is shared by the web and API
check-in writers so the two cannot drift. A row that already holds watch data
stays `mixed` when the user answers it: deciding this from the objective metrics
alone demoted a watch-synced night to `manual`, after which `sleep_from_watch?`
was false and the dashboard stopped saying where the sleep figure it was still
showing had come from.

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

## Staying signed in

A session used to be permanent in both places that matter — a twenty-year cookie
and a row with no clock — so a session on a lost phone lived forever and nothing
in the app could see it, let alone end it. It now has two clocks and a page.

- **Two clocks, because neither covers the other.** `Session::IDLE_TIMEOUT` ends
  a session nobody has used; `Session::ABSOLUTE_LIFETIME` ends one somebody is
  using, which idle expiry can never reach. `active` and `expired` must stay
  exact complements — a test asserts they partition the table — or the nightly
  sweep deletes rows the request path would have honoured.
- **`last_active_at` is written at most once an hour** (`ACTIVITY_PRECISION`).
  Writing it on every request would add a write to every page load to sharpen a
  thirty-day window by minutes. It is its own column rather than `updated_at`,
  which moves for reasons that have nothing to do with the user being there.
- **An expired session is deleted on the way in**, not just ignored, so it stops
  appearing in the user's list as a device they can't sign out of.
  `ExpiredSessionSweepJob` only exists for users who never come back to make
  that request.
- **The list is the real protection.** Idle and absolute expiry are backstops;
  what actually stops a stolen session is the user seeing a device they don't
  recognize on `/profile/edit` and ending it. `ActiveSessionsController` scopes
  every lookup to `Current.user.sessions`, so another account's id is a 404.
- Revoking the current session from that list is just signing out, and has to
  clear the cookie as well as the row.

## When something fails

Failures used to go to STDOUT and, once a job had given up, into
`solid_queue_failed_executions` — where a user's plan quietly not updating looks
exactly like nothing happening. `ErrorReporter` is a `Rails.error` subscriber,
which is the whole capture mechanism: Rails already routes unhandled request
errors and jobs that have exhausted their retries there.

- **Recording is unconditional; notifying is configured.** Every failure lands in
  `error_reports` and the log with no setup. An email needs `ERROR_REPORT_TO`
  *and* deliverable mail — the same question the confirmation gate asks, because
  an alert nobody receives is not a control. Production says so at boot.
- **One row per distinct failure, with a count.** The fingerprint is the error
  class plus the top frame from this app, so the same bug from two requests is
  one row while two bugs of one class stay apart. `NOTIFY_INTERVAL` means a
  failure hitting every user in a recompute sweep is one email, not a mailbox.
- **What Rails reports is already the right set**, and it was measured rather
  than assumed: a job retried five times reports *once*, at the attempt it gives
  up on; a job `discard_on` drops (an account deleted out from under a queued
  recompute) reports nothing; a routine 404 reports nothing.
- **The reporter never becomes the error.** Both the write and the send are
  rescued and logged — if the database is what broke, recording an error about it
  there breaks the same way, and raising would replace a useful exception with a
  useless one.
- **Context is an id, never the thing being worked on**: no params, no headers,
  no addresses. A message can still quote values from a failing query, so
  `error_reports` carries the same sensitivity as the data it is about, and is
  capped rather than left to grow.
- `error_reports` is deliberately **not** associated with `users` — these are
  records about the system, so they are neither exported with an account nor
  destroyed with one, and `AccountFixture` does not change.

## Email confirmation

New accounts are created unconfirmed and signed in anyway. Confirmation gates one
thing — asking the AI coach, the only surface where an unconfirmed address spends
money — and `EmailVerificationsMailer.enforced?` decides whether it gates at all:

- **If mail cannot be delivered, confirmation is not enforced.** Nobody can
  confirm, so a gate would be an outage rather than a control. Production logs a
  warning at boot (`config/initializers/mail.rb`) instead of failing open quietly.
- **Mail is configured from the environment** (`APP_HOST`, `SMTP_*`), like
  `web_push.rb` and `anthropic.rb`. Rails' production scaffold looks configured
  and is not — a commented-out SMTP block and a host of `example.com` — and both
  password reset and confirmation depend on it.
- Fixture users are confirmed. A test that wants an unconfirmed one clears
  `verified_at` itself, so the banner does not appear in every other test's markup.

## One mailbox, a few accounts

`email_address` being unique says nothing about how many addresses reach one
inbox: `me+1@`, `me+2@` and, on Gmail, `m.e@` all deliver to the same place, so
confirmation confirms every one of them. `EmailAddress.canonical` reduces an
address to the mailbox it lands in and `User::ACCOUNTS_PER_MAILBOX` caps how many
accounts that mailbox may hold.

- **Canonicalization is for counting only.** What a user typed is what is stored,
  what they sign in with and where mail goes. Nothing rewrites an address.
- **Dot-insensitivity is a short allow-list**, not a rule applied everywhere. At
  most hosts `a.b@` and `ab@` are two different people, and merging them would
  refuse a stranger's sign-up over a name that looks similar.
- **Both ways into a mailbox are covered** — a new account and a confirmed
  change. The validation on `User` fires whenever `email_address` changes;
  `EmailChangeRequest` checks it too, so the user hears it before following a
  link rather than after.
- Fixtures set `canonical_email_address` through the same rule, because fixtures
  insert rows directly and the callback never runs.

## What the coach costs

Asking the coach is the only action in this app that spends money per press, and
four separate guards stand around it. Each covers what the others cannot, so
adding a fifth means asking which gap it fills:

- the registration throttle caps sign-ups per IP,
- confirmation proves the address exists,
- `User::ACCOUNTS_PER_MAILBOX` caps accounts per inbox,
- `CoachBudget` caps what one account can spend once it is in.

`CoachBudget::DAILY_LIMIT` questions per **the user's own local day**, like every
other day boundary here — a budget refilling at UTC midnight would refill
mid-afternoon in Denver.

- **It is a product limit, not an attack response.** It lives here rather than in
  `Rack::Attack` because a user who has asked their questions should be told when
  they get more, not handed a 429. The panel withdraws the ask form, says when the
  budget refills, and leaves the answers already given on screen.
- **A failed narrative is refunded; a pending one is not.** A failure means the
  call raised rather than billed and the user got no answer. A pending one is a
  call already in flight, and refunding it would make a burst of unanswered
  questions free.
- **The count and the insert happen under a lock on the user's row**
  (`CoachBudget#claim`). They are two statements, so without it two questions
  asked at once both read the same count and both insert.
  `CoachBudgetRaceTest` runs non-transactionally and fails if the lock goes.

## Changing an email address

Nothing moves until the new address proves itself. `EmailChangeRequest` parks it
in `pending_email_address`; `EmailChangeConfirmation` swaps it, and only then.
Writing it straight in would mean a typo costs every route back into the account
— a password reset would go somewhere that does not exist — and would let anyone
holding a session take the account outright.

- **The current password is required**, the bar account deletion sets, and the
  **old address is told** a change was asked for. The second is the one that
  reaches the real owner when it was not them who asked.
- **Uniqueness is checked twice**: at request and again at confirmation, because
  somebody can register the address in between. On losing that race the request
  is cancelled — and the record has to be reloaded first, because the failed save
  left it holding the rejected address and saving it again fails the same way.
- **This flow fails closed** when mail is undeliverable, unlike new-account
  confirmation. Refusing to start leaves the account as it was; starting one
  would park a request that can never be confirmed.
- Confirming a new address also verifies the account — receiving mail there is
  the only question confirmation asks.

## Exporting and deleting an account

`AccountExport` and `AccountDeletion` are complements: whatever erasure destroys,
the export hands back first. Both are driven by `AccountFixture::ACCOUNT_MODELS`
and `populate_account`, one shared test fixture that builds an account which has
used every part of the app — so **adding a `has_many` to `User` means adding it
to that fixture**, and leaving it out of either service fails a test rather than
going unnoticed.

The export departs from that symmetry twice, deliberately:

- **Credentials are never exported** (`AccountExport::EXCLUDED_COLUMNS`), though
  deletion removes them. A test asserts none of them appears anywhere in the file.
- **Referenced catalog exercises are exported**, though they belong to nobody and
  deletion leaves them alone — without them an exported set is a weight against
  an integer.

Values are exported in stored units, like decision prose, because the file is a
record rather than a rendering; the header says so and names the reader's own
unit system.

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

Adding a `has_many` to `User` means placing it in that order as well as adding it
to `AccountFixture`.

## Flash messages

Everything the app says over the page renders into one `.flash-stack`. They used
to be individually `position: fixed` at the same coordinates, so a new account
got the welcome notice drawn exactly on top of the confirm-your-email banner,
and neither could be closed.

- **A notice sees itself out; an alert waits.** A notice reports that something
  went right, so `shared/_flash` gives it a `dismiss_after`. An alert is usually
  the explanation for why something did not — taking "That password is not right"
  away from the person still typing is the failure mode, so alerts pass 0. The
  Stimulus controller defaults to 0, so a view cannot forget to opt out.
- **Everything can be closed**, because a message fixed over the page that will
  not go away is worse than no message.
- A dismissed flash is **removed, not hidden** — a class that sets `display`
  outranks the user agent's `[hidden]` rule, which has already left one element
  on screen in this app.
- The verification banner lives in the same stack but is neither timed nor
  closable: it is a standing state rather than something that just happened, and
  dismissing it would only bring it back on the next page.

## Empty states

An empty state names the action that fills it and **offers it as a button**, not
as a link buried in a sentence. "No workouts logged yet" is a description; a user
who reads it still has to work out where to go, and "Log a workout and each
working set lands against the muscles it trains" hides the target inside the
prose.

It is also a placeholder rather than a lost paragraph: `.empty-state` reads down
the same left edge as the heading above it and stops at a readable measure.
Centred text with 36px of padding left one sentence floating in the middle of an
1106px-wide box on a page where everything else is left-aligned, and made the
panel 150px taller than its own content. A panel whose sole job is a rarely-used form folds it away: the nutrition page's
seven-field "add a food manually" is a `<details>`, because searching finds most
foods and the form was taking as much room as the food log itself. A `<details>`
rather than Stimulus — nothing else needs to know it is open, and it works
before any JavaScript does.

What a new account is missing is answered in one place — `OnboardingProgress`
— which both `/onboarding` and the dashboard read, because the dashboard is the
only route back to that checklist once a user has left it.

## Navigation

There are two of them and they must stay in step: `shared/_navigation` is the
desktop topbar, `shared/_mobile_tab_bar` the phone's, and the 560px breakpoint
hides one to show the other. A destination added to one and not the other either
cannot be reached on that device or shows up twice.

- **The topbar groups; it does not list.** Thirteen flat links wrapped onto three
  rows at 1400px and four below 1180px, and every new page added one more. It is
  `Today`, three `shared/_nav_menu` groups, the `Log workout` button and an
  account menu — one row at every width down to the breakpoint. A new page joins
  a group's `links` hash rather than the row.
- A menu says whether the page you are on is inside it, so `Training` reads as
  current on all six of its pages.
- The menus are a Stimulus controller rather than `<details>`, which the phone
  sheet still uses. A row of `<details>` stays open until clicked again, so
  opening the next leaves the last hanging over the page; a menu bar wants one
  open at a time, closing on Escape, on a click anywhere else, and on focus
  leaving it — tabbing past the last link used to leave it open over the page
  with nothing inside it focused to say so.
- **Testing the menus cannot use `page.driver.send_keys`.** It fires a click on
  the document before it types, which is a genuine outside click, so the menu
  under test closes before the key lands. Every early version of
  `NavKeyboardTest` "found" bugs that were only that — including a convincing
  one where Tab appeared to skip six links. Dispatch the key as an event to test
  the controller's own handlers, and assert the parts the browser does natively
  (Tab moving focus, Enter clicking a button) structurally instead: with a menu
  open, the next tabbable elements after the trigger are its own links.

## Styling that only a browser can check

`StylingTest` asserts two things that look fine in the markup and wrong on
screen, because both are computed style rather than anything a controller test
can see.

- **A link's colour is a default, not a per-call-site chore.** Seven links across
  the exercise, prescription, session, meal, onboarding and sign-up pages carried
  no class, or one like `.text-button` that sets no colour, and rendered in the
  browser's blue-and-underlined — an exercise name doing that inside an otherwise
  styled card. The bare `a` rule decides it now and anything wanting different
  still says so.
- **Specificity beats order, and `.stacked-form` is the trap here — twice now.**
  The logger's form carries that class, and `.stacked-form label > span` is one
  element more specific than `.set-field > span`, so the rule meant to hide the
  per-field labels never applied: every row printed "kg / Reps / RIR / Warm-up"
  above its inputs, under a header row already naming the columns. The per-field
  label is what the phone uses *instead* of that header, so both halves are
  asserted. The focus ring hit the same wall:
  `.stacked-form input:not([type="submit"]):not([type="checkbox"])` sets
  `outline: none`, and a plain `.stacked-form input:focus-visible` is *lower*
  specificity, so the ring silently did nothing. Its `:not()`s are load-bearing.
- **Text is checked against what is actually behind it.** `StylingTest` walks the
  visible text on every page, composites each translucent layer down to the page
  colour, and fails anything under AA for its size — 3:1 for large or bold-large,
  4.5:1 otherwise. The palette cannot answer this on its own: `--muted` cleared
  4.85:1 on a card and 4.45:1 on the page itself, so most of the small print in
  the app sat just under the bar on most of its pages, and one white-on-green
  label was at 4.40:1. Both were fixed by measuring, not by eye.
- **A keyboard user has to be able to see where they are.** Controls here set
  `outline: none` and signalled focus with a border colour and a 10%-opacity
  halo, which measures 1.18:1 against the white behind it — invisible. Focus is
  a 2px `outline` on `:focus-visible` (9.5:1, and unlike a thicker border it
  costs no layout). Note that `:focus-visible` is the one state a test cannot
  fake: Chrome decides it from *how* the element was focused, so the test presses
  Tab. `element.focus()` from a script leaves every field reporting no ring.
- **Native controls need `accent-color` or they are the operating system's
  blue** — twenty of them on the daily check-in alone, plus the weekday picker,
  the equipment list and the logger's warm-up boxes. One property on `:root`
  paints all of them, and it is the only way to reach a native control's own
  colour without rebuilding it.
- **Panels on a page share both edges.** `.form-panel` centres itself at 920px,
  which is right when the page *is* a form and wrong when the form is one section
  among panels — on the block, goal and conditioning pages it sat 130px inside
  its neighbours on both sides. `.form-panel--section` lines the panel up and
  caps the fields instead.

## The phone is the narrow case, and it is tested

`ResponsiveLayoutTest` loads every authenticated page at 390px and fails if the
document is wider than the viewport, naming the element that sticks out. Sideways
scroll is invisible on a desktop and makes every page feel broken on the device
this app is mostly used from.

It is one property over every page rather than an assertion per view, and it does
bite: a `flex-wrap: nowrap` added to fit a row on one line failed it immediately.
Two things it does *not* catch, so do not assume it does — a wrapping flex row
just wraps rather than overflowing, and two navigations showing at once is a
duplication rather than an overflow, which is why the topbar-versus-tab-bar
assertion is separate.

## Live updates and unsaved input

Four pages subscribe to the user's stream (`turbo_stream_from Current.user`) and
every recompute ends in `broadcast_refresh_to`, which the layout's
`turbo_refresh_method_tag :morph` applies as a morph rather than a reload. A
morph rewrites form fields from the server's render, so a refresh arriving while
somebody is filling a form takes what they typed with it — a wearable sync
landing mid-check-in blanked all four ratings, with nothing on screen to say why.

- **A form on one of those pages opts into `unsaved-input`.** The controller puts
  `data-turbo-permanent` on at the first keystroke and takes it off at submit, so
  a form holds its ground only while there is something to lose and still takes
  the server's render once it has been sent. It wires its own events rather than
  listing them in `data-action`, so a view cannot half-subscribe.
- **Ids must be unique, and Rails does not give you that for free.** Turbo matches
  permanent elements with `getElementById`, so a duplicate makes a refresh
  preserve whichever copy it finds first. `form_with model:` names a field after
  the *model*, not the record, so a partial rendered in a loop repeats every id it
  contains; a model-less `form_with` names fields after themselves. Pass
  `id: dom_id(record, :field)` in a loop, or `id: nil` for a hidden field nothing
  addresses. `ElementIdsTest` renders every authenticated page and fails on a
  repeat.
- **A system test must wait for `turbo:morph`, not for a timeout.** A broadcast
  arrives over the socket with no request for Capybara to wait on, and a fixed
  sleep lets a test pass by racing the refresh instead of surviving it — which is
  how one of these passed against a deliberately broken controller.
- A form inside the `nutrition_log` frame that redirects to a whole page needs
  `data: { turbo_frame: "_top" }`, or the response has nowhere to render.

## Things that are easy to get wrong

- Any URL a client supplies and the server later requests is an SSRF vector.
  Push endpoints are allow-listed against vendor hosts in `PushSubscription` for
  this reason.
- **Throttles belong in `Rack::Attack`, not in `rate_limit`.** Both exist here,
  but `config.cache_store` is `:null_store` in test, so a controller-level
  `rate_limit` counts nothing there and cannot be tested — the declarations on
  `SessionsController` and `PasswordsController` only bite in production. Every
  throttle with a test behind it is a Rack::Attack one.
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
- **CI runs a newer Postgres than the dev container, so `bin/ci` green is not
  CI green.** Development here is Postgres 16; `.github/workflows/ci.yml` pins
  the service to `postgres:18` — pinned so the version only moves when someone
  edits that line, rather than whenever Docker Hub retags `latest`. Behaviour
  that differs between majors has already bitten twice: a RESTRICT violation
  surfaces as a different exception class on each, so a test asserting the
  narrower class passed locally and failed the build. Assert on the parent class
  and the message rather than on whichever class the local server happens to
  raise.

- **`db/schema.rb` is whatever a rebuild produces, not what looks tidiest.**
  Postgres stores a check constraint as a parsed expression and prints it back
  in its own normal form, so `metric_type IN ('a', 'b')` in a migration is not
  what the dump says. Two constraints were committed in a form Postgres does not
  produce — loading that schema and dumping it again changed them — so every
  `db:migrate` or `db:prepare` left the file dirty with a diff nobody wrote. The
  committed form is now the one both `db:migrate` and `db:schema:load` converge
  on and re-dump unchanged. If those two lines ever look wrong, re-derive them
  with a rebuild rather than hand-editing them back; the constraints are
  identical either way, and `CheckConstraintsTest` proves it by inserting an
  unlisted value.

  `bin/schema-check` guards both halves of this, on a scratch database of its
  own so development and test are untouched. **Structural** — the file plus any
  migration newer than it, against the file alone — is what breaks when a
  migration's dump is not committed. Note that `db:migrate` on an empty database
  *loads* `db/schema.rb` and stamps the versions rather than replaying
  migrations, so only the migrations the file does not account for actually run;
  that is the set worth comparing, and it is not a full replay, because Postgres
  normalises constraint text on load and a raw migration would be reported as
  drift for spelling `IN (...)` differently. Both sides are dumped by the same
  server, so it means the same thing on any Postgres and runs in GitHub Actions
  too. **Canonical** — the file is byte-for-byte what this server dumps — is the
  churn above, is only a sensible question of the server you are asking, and so
  runs under `--canonical` from `bin/ci` alone.

  A practical consequence: `bin/rails db:migrate` on an existing database writes
  the raw form of a new check constraint into the dump, while a rebuild writes
  the normalised one. `--canonical` catches it; the fix is to regenerate with a
  rebuild rather than to hand-edit, as above.

- **`bin/ci` seeds the test database as its last step, so the run after it
  starts on a seeded one.** `Tests: Seeds` is `db:seed:replant` under
  `RAILS_ENV=test`, and `bin/setup`'s `db:prepare` does not wipe what it leaves
  — ten muscle groups and the whole exercise catalog. So a test that creates a
  row the seeds also create passes on a clean database and fails on the next
  `bin/ci`, and looks intermittent because a new migration reloads the schema
  and clears the seeds in between. Three did: two `MuscleGroup.create!("chest")`
  and an `Exercise.create!("Pendlay Row")`. Use `find_or_create_by!` for a name
  the seeds own, or a `Zzz` name of your own. To reproduce this class of failure
  deliberately, run `env RAILS_ENV=test bin/rails db:seed:replant` and then the
  suite.
- Catalog exercises (`user_id: nil`) survive `db:seed:replant`, as above. Tests
  must not assume an empty `exercises` table — use distinctive names and assert
  on presence rather than totals — and note that a test database prepared with
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
