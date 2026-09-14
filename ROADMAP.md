# Roadmap

Outstanding work, roughly in priority order. Items are grouped by the kind of
risk they carry, not by size.

## Correctness

- [x] **`unit_system` is honored across the UI.** Storage stays canonical —
  kilograms and centimetres — so every evaluator, decision and progression
  comparison is unit-agnostic and switching systems changes nothing about a
  user's data. Conversion happens at two boundaries only: `MeasurementsHelper`
  on the way out, `MeasurementParams` on the way in.

  Two things were deliberate. Controllers name their measurement fields
  explicitly instead of the concern inferring them from a `_kg` suffix, because a
  silent name-based rule would quietly capture any future column that matches and
  corrupt stored training data. And decision prose stays in kilograms, since a
  decision is an immutable record; where a decision carries the numbers behind its
  headline, the view composes its own sentence rather than doing string surgery on
  the record, falling back to the stored text when it cannot.

  Conditioning followed: distance and pace were hardcoded to kilometres and
  `/km`. `WeeklyConditioningSummary` now reports exact metres, `ConditioningDirective`
  targets metres and writes no unit into its prose at all, and the view composes
  the progress sentence in the reader's units.

  Remaining: `DoubleProgressionEvaluator` still writes kilograms into two
  `headline` strings. Both are rebuilt by `progression_headline` for display, so
  no user reads them, but making the stored output unit-neutral would need a
  `rule_version` bump.

- [x] **Measurements are stored exactly.** Columns held two decimal places, which
  is coarser than a unit conversion needs: 45.25 lb was stored as 20.53 kg and
  read back as 45.3, and re-saving the set persisted the altered value. Weight
  columns now hold six decimals and length four — the scales are derived, not
  chosen, from what it takes for a typed value to survive the round trip, and the
  tests pin that. `Units` does BigDecimal arithmetic throughout, and nothing is
  padded or truncated to a fixed width: a value renders at the precision it has.
  Measurement inputs take `step="any"`, so a 1.25 kg micro-plate is enterable.

## Security

- [x] **Dependency backlog cleared.** `bundler-audit` reported 24 advisories across
  9 gems (nokogiri is counted once per platform variant, so the raw line count
  looks far larger). All updated, including Rails 8.1.3 → 8.1.3.1 for the Active
  Storage arbitrary-file-read / RCE (CVE-2026-66066).

  `json` is now pinned to `~> 2.19, >= 2.19.9` rather than taking 3.0: json 3.0
  made `JSON.parse` accept its options as keywords, while
  `ActiveSupport::JSON.decode` still passes them positionally, so every jsonb
  attribute raised `ArgumentError` on deserialize — which in this app is every
  coaching decision. 2.19.9 carries the CVE fix, so the pin costs no security.
  Revisit when Rails supports json 3.

- [x] **`resolv` patched and under audit.** Ruby 4.0.6 predates the 2026-08-27
  advisory, so it bundles a vulnerable `resolv`. Declaring `resolv >= 0.7.2` in the
  Gemfile pulls the fix for CVE-2026-80212 and CVE-2026-80213 and puts a default
  gem under `bundler-audit`, which only ever sees what is in the lockfile.

- [x] **Push endpoints are allow-listed.** `push_subscriptions.endpoint` was
  stored unvalidated and the hourly reminder job POSTs to it from the server, so
  any signed-in user could aim it at cloud metadata or an internal service — a
  blind SSRF. Endpoints must now be HTTPS on a vendor push host, extendable via
  `WEB_PUSH_ALLOWED_HOSTS`. Filtering by IP range was rejected deliberately: it
  does not survive a hostname that resolves elsewhere after the check, which is
  CVE-2026-80213 exactly.

## Test coverage

- [x] **System tests exist, starting with the workout logger.** Capybara driving
  Chrome over CDP (Cuprite, so there is no chromedriver version to keep in step
  with Chrome). Seven tests cover the logger: prefilled rows through to saved
  sets, the live volume readout including warm-up exclusion, duplicating a set,
  removing and renumbering, adding an exercise from the catalog search, an
  imperial round trip, and the no-target empty state. Wired into `bin/ci` and
  into CI, which uploads screenshots on failure.

- [x] **System coverage extended past the logger.** `template_editor` and `push`
  are covered, as is the check-in through to the rendered plan — 20 browser tests
  in total. Every Stimulus controller now has tests. The template editor's suite
  found a live bug: a removed row stayed on screen because a class setting
  `display` outranks the user agent's `[hidden]` rule.
- [x] **The invariant-carrying models are covered.** `CoachingDecision`
  (retraction, `active_evidence`, the JSONB scopes, link roles and the
  restrict-on-delete that stops cited evidence disappearing), `DateRanged` and its
  three including models, `ExercisePrescription`, `WorkoutTemplate`, and
  `SetEntry` including the generated 1RM column's precision.

- [x] **The remaining models are covered where a rule actually lives.** They are
  thin, so the tests are about the rules rather than the files: volume landmarks
  are ordered and every muscle the catalog trains has them, scores and trends are
  unique per user per day at the index rather than only in a validation, and a
  trend is stored at the same scale as every other weight.

  The rule worth the most was the one four of them shared. `readiness_scores`,
  `weight_trends`, `expenditure_estimates` and `exercise_muscle_contributions`
  had no primary key, and Active Record builds every UPDATE and DELETE for a
  loaded record around one — so `save!`, `update!`, `destroy` and
  `dependent: :destroy` all emitted `WHERE "" IS NULL` and were rejected
  outright. It fails only on the *second* write for a given key, so it ships
  looking fine.

  That had already been a live bug in `ExpenditureEstimator`, and writing the
  test found three more, all on the join table: re-importing a catalog exercise
  whose muscles changed, deleting a custom exercise, and deleting a muscle group.

- [x] **The derived tables have primary keys.** `id: false` was a deliberate
  choice — every one of these rows is addressed by a natural key, so an id looked
  like dead weight — but it bought nothing and cost four bugs, each of which had
  to be worked around by reaching rows through their unique index with
  `update_all`. All four workarounds are gone: `ExpenditureEstimator`,
  `WeightTrendMaterializer` and `ExerciseCatalogImporter` write through
  `find_or_initialize_by` and `update!` like everything else in the app.

  The natural keys did not change. The unique index is still what makes "one per
  user per day" true; the id only makes the row addressable. `PrimaryKeysTest`
  fails if a keyless table appears again, and asserts those indexes are still
  there — an id that quietly replaced one would be a regression, not a fix.

## Views and navigation

- [x] **Exercise index and detail pages.** `exercises` had only `new`, so there
  was no way to browse the catalog or see a single lift's history.
- [x] **Per-decision audit view.** `/coaching_decisions/:id` shows one decision:
  the rule and version that wrote it, what it concluded, the input snapshot it was
  computed from, the decisions it cites and the ones citing it, and its withdrawal
  state. Every node in the dashboard's decision tree and every card in a
  progression trail links into it, and each page links on to its own parents and
  children, so the whole DAG is walkable from today's plan.

  The snapshot renderer assumes nothing about shape — the JSONB is written by
  whichever rule produced the decision — and resolves stored ids back to linked
  names, falling back to the raw id when the record is gone, which is exactly
  what a deleted workout leaves behind.
- [x] **Workout session index.** Past sessions were only reachable from the
  exercise history page; there is now a History page listing them newest first.
- [x] **Turbo's progress bar works again.** CSP set `style-src 'self'`, so the
  inline `<style>` Turbo injects for `.turbo-progress-bar` was refused on every
  page load: no loading indicator, and a console violation. Fixed by noncing
  `style-src` — Turbo signs that element with the `csp-nonce` meta tag — rather
  than adding `'unsafe-inline'`, which would have allowed every inline style on
  the page. The app now loads with zero CSP violations.

- [x] **First-run pass done.** Walking a freshly registered account through every
  page turned up a structural problem rather than a copy one: registration
  redirects to `/onboarding` once and *nothing ever links back to it*, so a user
  who skipped had no way to find out what was missing. The dashboard now carries
  the outstanding steps until setup is done, reading from `OnboardingProgress` —
  one object, so the checklist and the dashboard cannot disagree about what is
  left.

  The dead-end empty states (both on progress, plus conditioning and nutrition)
  now name the action that fills them instead of describing the absence.

## Product

- [x] **Wearable ingestion widened.** Workouts, body mass, steps, active energy
  and basal energy now sync alongside HRV, resting heart rate and sleep. Each one
  becomes a record the app already reads rather than a new kind of thing: a
  workout becomes a `ConditioningSession` (and so feeds the weekly conditioning
  target), a weigh-in becomes a `BodyMetric` (and so feeds the weight trend,
  expenditure and calorie targets), and energy gives `ExpenditureEstimator` a
  second way to answer.

  That second way is deliberately subordinate. Energy balance — intake against
  what the user's weight actually did — is measured outcome and stays primary;
  the device's basal-plus-active figure is a model, so it is only used while
  there is not yet a week of real evidence, never rises above low confidence, and
  is recorded on the row as `basis`. It counts complete local days only: a TDEE
  read off a day at breakfast would have set that day's calorie target at a few
  hundred kilocalories.

  Steps and energy were the one thing that could not be insert-only. They accrue
  all day, so the device sums them per local day and the server treats a repeat
  send as a correction — otherwise a day first synced at lunchtime stayed at its
  lunchtime total forever. Everything else still keys on an immutable HealthKit
  UUID.

  Two bugs fell out of building it. `ExpenditureEstimator` wrote through `save!`
  to a table with no primary key, so the second estimate for any date raised
  `PG::SyntaxError` — it reaches rows through the unique index now, the way
  `WeightTrendMaterializer` always did. And the nutrition page printed the weight
  trend in bare kilograms under a form labelled in pounds.
- [x] **A mesocycle carries its own targets.** Rep and RIR schemes used to be
  *applied*: a button rewrote every active target to the focus's preset,
  superseding each one. Three things were wrong with that. Starting a block did
  nothing until you remembered to press it. Ending a block left its scheme behind
  forever, because nothing knew the numbers had come from anywhere. And a rep
  range you had chosen by hand was gone the first time you pressed it, with no
  way back.

  `TrainingTargets` composes them at read time instead, so starting or ending a
  block recomposes the plan through the same recompute pipeline as every other
  input, and a target's stored numbers stay its own — the fallback for when no
  block is running. `follows_block_scheme: false` opts one lift out and keeps it
  on its own numbers, while still taking the block's volume ramp: opting out says
  "this rep range is mine", not "ignore the block".

  The split that made it work: the block owns the *scheme* (reps, RIR, baseline
  sets), and `DailyTrainingOrchestrator` keeps owning *today's volume* (the
  accumulation ramp, deload and recovery cuts). Both used to be described as
  block behaviour while only one of them was composed.

  `DoubleProgressionEvaluator` goes to `2.0.0`: it judges reps and RIR against
  the composed targets, resolved on the session's own date rather than today, and
  snapshots what was in force and where it came from — the prescription alone no
  longer answers that.
- [x] **Withdrawn decisions are surfaced.** Retraction was implemented, tested and
  filtered out of every lookup, but only the exercise page showed it. Now the
  workout session that caused a withdrawal lists what it no longer recommends,
  and the dashboard says when an earlier version of today's plan was withdrawn
  and why. `CoachingDecision#retraction_explanation` turns the rule's reason into
  a sentence, and one shared partial renders a decision so the three places
  cannot drift apart.

- [x] **Every evaluator is idempotent now.** `DoubleProgressionEvaluator` was the
  one that was not: it wrote a fresh decision on every run, so a retried job or a
  second save left a lift's trail full of identical entries differing only by
  timestamp. Worse, it compounded — the daily plan snapshots
  `progression_decision_ids`, so each duplicate progression decision minted a
  duplicate plan behind it.

  It compares the input snapshot against the live decision for that lift and
  returns it unchanged, like the other four. Two details made that sound rather
  than merely quiet: the snapshot now records `prior_decision_ids`, the earlier
  decisions the stall rule reads to turn a third hold into a deload — they were
  always part of what the rule saw and never part of what it recorded — and a
  re-run no longer counts the session's own earlier verdict as evidence against
  itself. `rule_version` is 3.0.0.

- [x] **An account can be deleted.** `User` declared `dependent: :destroy` across
  twenty associations and the cascade had never run — it could not. Two
  invariants that exist to protect a live account stood in the way: a decision
  cited by another cannot be deleted, and an exercise with logged sets against it
  cannot either. Both are right, and erasure has to lift them rather than be
  blocked by them, so `AccountDeletion` does it explicitly and in a transaction.

  The declaration order on `User` was wrong too — Rails destroys in declaration
  order and several associations reference each other — and there was a third
  thing no amount of ordering fixes: `restrict_with_exception` asks the
  *association* whether it is empty, so the objects used to lift the guards still
  held stale collections that said it was not. The service reloads before it
  destroys.

  It is behind the account's password rather than a confirm dialog alone, since a
  dialog only proves someone clicked and a session left open on a shared machine
  can click. The test populates every one of the twenty associations and erases
  it, asserts nothing of anyone else's moves, and asserts a failure mid-cascade
  leaves the account whole.

- [x] **The job pipeline survives its own edge cases.** `ApplicationJob` was the
  untouched Rails stub, with `retry_on` and `discard_on` both commented out, and
  eight of the nine jobs take an Active Record object as an argument.

  That made account deletion leave wreckage: anything still queued for the user
  raised `ActiveJob::DeserializationError` on deserialize and sat in
  `solid_queue_failed_executions` forever. Those jobs are discarded now — there
  is nothing left to recompute, so they are finished rather than failed — and
  logged, because a live account losing records would be a different problem.

  The other half matters more day to day. With no `retry_on`, one deadlock
  permanently failed a recompute and the user's plan silently stopped updating,
  with nothing on screen to say so. Transient contention now retries five times
  with backoff, which is safe precisely because every evaluator is idempotent.
  The retry list is deliberately narrow: a `StatementInvalid` is usually a bug.

- [x] **An account can be exported.** The delete-account copy used to say "there
  is no export, so take anything you want to keep first", which documented a gap
  rather than filling it. One JSON file now holds everything: profile, every
  workout and set, weigh-ins, food, conditioning, wearable samples, and every
  coaching decision with the evidence it cites.

  Its spec is the complement of deletion — whatever erasure destroys, the export
  hands back — and that symmetry is asserted rather than described: both run off
  one shared `AccountFixture`, so an association added to `User` and forgotten in
  either fails a test. Two departures are deliberate and tested. Credentials are
  never exported, though deletion removes them. Catalog exercises the account
  trained on *are* exported, though deletion leaves them, because without them an
  exported set is a weight against an integer.

  Generated in the request rather than queued, since no object storage is
  configured to put a file in. A few years of training is single-digit megabytes;
  the comment on the controller says what would change that answer.

- [x] **Registration is throttled.** Signing in and resetting a password were
  both capped; creating an account was not, so it was the one unauthenticated
  write anyone could issue without limit. Ten per client IP per hour — far past
  anything a household or office behind one address does, far under what filling
  a table takes.

  It is a Rack::Attack throttle rather than the controller-level `rate_limit`
  that sessions and passwords use, because Rack::Attack is the mechanism this app
  can actually test: `config.cache_store` is `:null_store` in test, so Rails'
  `rate_limit` cannot count there and those two declarations are unexercised by
  the suite. They still work in production against Solid Cache.

  What this does not do is stop a caller with many addresses. Email verification
  is the answer to that, and there is none — registration signs you straight in.
  Worth building before the sign-up page is advertised anywhere.

- [x] **Email is confirmed, and email works at all.** The second half was the
  bigger discovery: production mail was the untouched Rails scaffold — SMTP
  commented out, every link built against a literal `example.com` — so password
  reset had been quietly dead the whole time. It is configured from the
  environment now, like every other outside service here, and production logs at
  boot when it is not.

  Confirmation itself is deliberately not a wall. A new account signs in and can
  log training straight away; what it cannot do is ask the AI coach, which is the
  one surface where an unconfirmed address spends real money rather than
  occupying a table row. Walling off the whole app behind an email that may be
  slow, filtered or misaddressed costs more than it protects.

  And it is not enforced when mail cannot be delivered. A confirmation nobody can
  complete is an outage, not a control, so the gate asks whether the service
  exists — the same question `CoachNarrator.configured?` asks — and the boot
  warning says so out loud rather than failing open in silence.

  One mailbox is capped at a few accounts — see below.

- [x] **An email address can be changed.** The new one confirms itself before it
  takes effect, so a typo costs nothing and the account keeps working throughout.
  The current password is required and the *old* address is told a change was
  asked for — that second email is the one that reaches the real owner if it was
  not them who asked, and it deliberately carries no link and asks for no action.

  Unlike new-account confirmation this fails closed when mail is undeliverable:
  refusing to start leaves the account exactly as it was, while starting one
  would park a request nobody could ever confirm.

  Writing the test for the race — somebody registering the address between the
  request and the click — turned up a real bug. The rescue cleared the pending
  request on a record that still held the rejected address in memory, so the save
  failed the same way and the request stuck forever, unconfirmable and
  uncancellable. It reloads first now.

- [x] **One mailbox holds a few accounts, not unlimited ones.** A unique
  `email_address` says nothing about how many addresses reach one inbox:
  sub-addressing works everywhere, Gmail ignores dots, and confirmation confirms
  all of them because they all arrive. Addresses are reduced to the mailbox they
  land in and capped at three — enough for a household sharing an inbox, far
  under what multiplying accounts for free AI-coach quota needs.

  Deliberately narrow in one place: dots are only ignored for Gmail, not
  everywhere, because at most hosts `a.b@` and `ab@` are two different people and
  merging them would refuse a stranger's sign-up over a name that looked similar.

  Covered on both ways into a mailbox. Validating only registration would have
  left the email-change flow as the way around it.

- [x] **The coach has a daily budget.** Four commits in a row capped how many
  *accounts* one person could hold — the registration throttle, confirmation, the
  per-mailbox cap — and none of them capped what a single account could spend.
  `POST /coach_narratives` was the only endpoint in the app that costs real money
  per press and the only outbound-call endpoint with no limit at all; food search
  was throttled precisely because it calls Open Food Facts.

  Twenty questions per the user's own local day, which is far past what
  understanding one day's plan takes and far under what scripting a bill needs.
  It is a product limit rather than an attack response, so it is enforced in a
  service and rendered as a sentence: the panel withdraws the ask form, says when
  the budget refills, and keeps the answers already given on screen. It starts
  counting down out loud with five left, because a wall nobody saw coming is the
  actual failure.

  A question the coach could not answer is refunded — the call raised rather than
  billed, and the user got no answer — while a pending one still counts, since it
  is already in flight.

  The part worth the test: counting and inserting are two statements, so two
  questions asked at the same instant both read the same count and both insert. A
  probe confirmed it — two granted, twenty-one rows against a limit of twenty —
  and confirmed a lock on the user's own row fixes it. `CoachBudgetRaceTest` runs
  non-transactionally so its threads can see each other, and fails if the lock is
  ever removed.

- [x] **Sessions expire, and a user can see where they are signed in.** `Session`
  was `belongs_to :user` and nothing else, the cookie was `permanent` — twenty
  years — and the row recorded only when it was created. A session on a lost
  phone lived forever, and nothing in the app could see it, let alone end it.
  Password reset was already revoking sessions, which was the right instinct
  with nothing else behind it.

  Two clocks now, because neither covers what the other does. Thirty days idle
  ends a session nobody is using, which is the lost-phone case. A hundred and
  eighty days absolute ends one somebody *is* using, which idle expiry can never
  reach. `active` and `expired` are exact complements and a test asserts they
  partition the table, because a sweep that disagrees with the request path
  either deletes live sessions or leaves dead ones.

  Activity is its own column, written at most once an hour. `updated_at` moves
  for reasons that have nothing to do with the user being there, and writing on
  every request would add a write to every page load to sharpen a thirty-day
  window by minutes.

  The expiry is the backstop; the list is the actual protection. `/profile/edit`
  names each device — browser and platform, address, when it was last used —
  marks the one you are reading it on, and offers both one-at-a-time sign-out and
  "everywhere else", which is the button someone reaches for when a name in that
  list is wrong. An unrecognized user agent is shown verbatim rather than as
  "Unknown", since the raw string is worth more to the person deciding.

- [x] **`db/schema.rb` stopped rewriting itself.** Two check constraints were
  committed in a form Postgres does not produce, so every `db:migrate` or
  `db:prepare` left the file dirty with a diff nobody wrote — and each of the
  last few changes had to strip that churn out by hand before committing.

  Postgres stores a check constraint as a parsed expression and prints it back
  in its own normal form, so `metric_type IN ('a', 'b')` in a migration is not
  what the dump says. Measuring settled it rather than guessing: the committed
  form was not a fixed point — loading that schema and dumping it again changed
  those two lines — while the regenerated form survives both `db:migrate` from
  nothing and a `db:schema:load` round trip unchanged.

  The constraints are identical either way, which is asserted rather than
  assumed: `CheckConstraintsTest` inserts past the models and proves each one
  still accepts every listed value and rejects an unlisted one. That needed the
  expenditure bases to be a named list (`ExpenditureEstimator::BASES`) like
  `WearableSample::METRIC_UNITS` already was, so the test can ask about
  everything the app writes rather than two strings copied into it.

- [x] **CI's Postgres is pinned.** The workflow asked for `postgres`, which is
  `postgres:latest`, so the major version CI tested against could change without
  anyone committing anything — and this repo has already lost a build to a
  behaviour difference between majors, when a RESTRICT violation turned out to
  arrive as a different exception class on 16 than on 18.

  Pinned to `postgres:18`, which is what `latest` already resolved to, so nothing
  about what runs changed — only whether it can change by itself. The patch level
  still floats, so fixes arrive without a commit.

  What this does not close is that CI is a major ahead of the development
  container, so a version-dependent failure can still reach CI having passed
  `bin/ci`. That is now written down in CLAUDE.md rather than rediscovered.

## Developer experience

- [x] **`CLAUDE.md` written.** Covers the evaluator contract, the recompute
  pipeline, the units boundary and its two invariants, and a table of the five
  `decision_type` values and four link roles with the service that owns each —
  which previously had to be reassembled from check constraints.
