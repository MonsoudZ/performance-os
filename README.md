# PerformanceOS

PerformanceOS turns daily training, nutrition, body-composition, and recovery
logs into **transparent coaching decisions**. Every recommendation the app makes
can be traced back to the evidence that produced it — no black box.

## The core idea: an auditable decision DAG

The app never stores "advice" as prose. It stores immutable **coaching
decisions**, each one a row in `coaching_decisions` carrying:

| Column | Meaning |
| --- | --- |
| `decision_type` | `daily_readiness`, `double_progression`, `daily_nutrition`, `weekly_review`, `daily_training` |
| `rule_key` / `rule_version` | which rule produced it, so old decisions stay interpretable when rules change |
| `inputs` (jsonb) | a snapshot of exactly what the rule saw |
| `output` (jsonb) | the recommendation itself |
| `confidence` | `low` / `moderate` / `high`, driven by how much evidence existed |
| `retracted_at` / `retraction_reason` | decisions are never edited or deleted — they are retracted |

Decisions link to each other through `coaching_decision_links` (`role` is one of
`readiness`, `progression`, `nutrition`, `weekly_review`). `DailyTrainingOrchestrator`
composes the day's readiness decision, each lift's progression decision, and the
nutrition decision into a single `daily_training` parent. That parent is what the
dashboard renders, and its children are the audit trail behind
*"What should I do today?"*.

Because the inputs are snapshotted, every evaluator is **idempotent**: it compares
the current input snapshot against the last decision and short-circuits when
nothing has changed. Re-running the pipeline is always safe.

### The evaluators

| Service | Produces |
| --- | --- |
| `ReadinessEvaluator` | A 0–100 readiness score from sleep, soreness, fatigue, stress, HRV, and resting HR. Objective wearable metrics only count once a 7-day personal baseline exists. |
| `DoubleProgressionEvaluator` | Per-lift next-weight directives from logged sets, with stall detection over 3 sessions and a 10% deload. |
| `NutritionEvaluator` | Goal-aware energy and protein guidance, fed by `NutritionTargetResolver` and `ExpenditureEstimator` (adaptive TDEE, gated on evidence). |
| `WeeklyEvidenceReview` | A 7-day rollup that checks actual rate of change against goal-specific bands. |
| `DailyTrainingOrchestrator` | The composed daily plan, modulated by readiness, mesocycle phase, and deload weeks. |
| `CoachNarrator` | Optional. Asks Claude to explain the decision graph in plain language, grounded *only* on the serialized decisions — never the database. |
| `CoachBudget` | How many coach questions an account has left today, and the claim that stops two asked at once from both taking the last one. |
| `ScheduledWeeklyReviewJob` | Runs each user's weekly review at their own local hour, so a calorie correction does not wait to be asked for. |

### How a write becomes a new plan

```
controller action
  └─ TrainingRecomputable / NutritionRecomputable concern
       └─ Solid Queue job
            └─ DailyPlanRecompute pipeline (all evaluators, all idempotent)
                 └─ Turbo::StreamsChannel.broadcast_refresh_to(user)
```

Logging a set, editing a food entry, or finishing a mesocycle enqueues a
recompute; open pages morph themselves when the new decision lands.

## Features

- **Auth** — native Rails 8 sessions, `has_secure_password`, password reset by email.
- **Goals** — one active goal period at a time, across seven goal types.
- **Program generation** — `ProgramGenerator` builds a starting program from your
  goal, experience level, training days per week, and available equipment. It is
  additive and idempotent; "refresh from profile" also retires lifts you no longer
  have the equipment for.
- **Mesocycles** — blocks with a focus (hypertrophy / strength / power), deload
  weeks, and accumulation set ramps. A block owns its rep/RIR scheme: every target
  follows it while it runs and goes back to its own numbers when it ends, with no
  "apply" step and nothing overwritten. Finishing one suggests the next.
- **Training targets** — effective-dated exercise prescriptions (rep range, RIR
  range, working sets, increment). Editing one supersedes it rather than mutating
  it, and any one lift can opt out of the block and keep its own numbers.
- **Workout templates and logging** — scheduled templates, prefilled set rows,
  live Turbo updates.
- **Conditioning** — sessions with duration, distance, and average HR, summarized
  weekly into a zone-2 directive.
- **Nutrition** — food catalog, Open Food Facts search (free, keyless, barcode-aware),
  meal types, copy-yesterday.
- **Body composition** — weight and body-fat entries materialized into an EWMA
  weight trend.
- **Wearables** — an iOS HealthKit ingestion arm (see `native/ios/`) feeding HRV,
  resting HR and sleep into readiness, workouts into conditioning, body mass into
  the weight trend, and steps and energy into expenditure. Nothing it sends
  becomes a new kind of record: each metric turns into the thing a user could
  have logged by hand, so every rule downstream works unchanged.
- **Account export and deletion** — one JSON file holding everything the app
  knows, and a password-confirmed erasure of the same set.
- **Email confirmation and change** — new accounts can log training immediately
  but cannot spend money on the AI coach until the address is confirmed, and a
  new address confirms itself before it replaces the old one. One mailbox holds
  at most three accounts, counted against the inbox an address actually reaches
  rather than the string, and each account gets twenty coach questions per local
  day — the one action here that costs money per press.
- **Signed-in devices** — sessions expire on an idle and an absolute clock, and
  the profile page lists every device an account is signed in on with a way to
  end any of them, or all but the one you are holding.
- **Web Push** — hourly check-in reminders via a Solid Queue recurring task.
- **PWA** — manifest, service worker, and a mobile bottom tab bar.

## Stack

- Ruby 4.0.6, Rails 8.1
- PostgreSQL (check constraints and partial unique indexes carry a lot of the
  invariants — one active goal per user, valid rep ranges, retraction consistency)
- Solid Queue / Solid Cable / Solid Cache — no Redis
- Hotwire (Turbo + Stimulus) over Propshaft and importmaps — no JS build step

## Local setup

```sh
bundle install
bin/rails db:prepare
bin/rails db:seed
bin/dev
```

Then open `http://localhost:3000` and register an account.

`db:seed` imports the canonical exercise catalog from `db/catalog/exercises.yml`.
To also create a demo athlete with an active goal, a starting squat target, and a
small verified food catalog:

```sh
SEED_DEMO_USER=true bin/rails db:seed
```

- Email: `athlete@performanceos.local`
- Password: `performance`

## Environment variables

All of these are optional — the app runs without them, with the corresponding
feature dormant.

| Variable | Effect when unset |
| --- | --- |
| `ANTHROPIC_API_KEY` | The AI coach panel is hidden and `CoachNarrator` stays dormant. |
| `ERROR_REPORT_TO` | Failures are still recorded in `error_reports` and the log, but nobody is emailed about them. |
| `ANTHROPIC_MODEL` | Defaults to `claude-opus-4-8`. |
| `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` | Push delivery is a no-op. Generate a pair with `WebPush.generate_key`. |
| `VAPID_SUBJECT` | Defaults to `mailto:support@performance-os.app`. |
| `APP_HOST` | Every link in an email points at `example.com`, so password resets and confirmations go nowhere useful. Set it in production. |
| `SMTP_ADDRESS` | No mail is delivered at all: password reset is silently dead, and email confirmation is **not enforced**, since a confirmation nobody can complete would be an outage rather than a control. Production logs a warning at boot. `SMTP_PORT`, `SMTP_USER_NAME`, `SMTP_PASSWORD` and `SMTP_AUTHENTICATION` go with it. |
| `CABLE_ALLOWED_ORIGINS` | Comma-separated Action Cable origins, for running behind an SSL-terminating proxy in production. |
| `SOLID_QUEUE_IN_PUMA` | Runs the worker inside Puma. Always on in production. |

## Tests

Minitest, with the weight of the suite on `test/services/` where the evaluators live.

```sh
bin/rails db:test:prepare test
```

To run everything CI runs — style, three security scanners, tests, and a seed
replant — in one pass:

```sh
bin/ci
```

## Deployment

`railway.json` runs migrations and re-imports the exercise catalog before each
deploy:

```
bin/rails db:migrate && bin/rails catalog:import
```

The catalog import is idempotent, so adding exercises to `db/catalog/exercises.yml`
ships them on the next deploy.

## What's next

See [ROADMAP.md](ROADMAP.md).
