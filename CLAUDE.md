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
  own so development and test are untouched. **Structural** — the committed file
  loads into the same database the migrations build — is what breaks when a
  migration's dump is not committed, and it compares two dumps from the *same*
  server, so it means the same thing on any Postgres and runs in GitHub Actions
  too. **Canonical** — the file is byte-for-byte what this server dumps — is the
  churn above, is only a sensible question of the server you are asking, and so
  runs under `--canonical` from `bin/ci` alone.

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
