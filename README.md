# PerformanceOS

PerformanceOS turns daily training, nutrition, body-composition, and recovery logs into transparent coaching decisions.

The first two vertical slices establish the product loop:

1. Native Rails authentication protects each athlete’s data.
2. A daily recovery check-in writes an immutable readiness decision.
3. Effective-dated exercise prescriptions define rep, RIR, set, and load targets.
4. Workout logs snapshot what actually happened.
5. `DoubleProgressionEvaluator` compares facts against the active prescription.
6. `DailyTrainingOrchestrator` composes readiness, goals, prescriptions, and progression decisions.
7. Food logs snapshot macros while weight entries create immutable EWMA trend points.
8. `NutritionEvaluator` emits goal-aware energy and protein guidance, with adaptive expenditure gated by evidence.
9. Explicit parent-child links preserve the complete audit tree behind “What Should I Do Today?”

## Stack

- Ruby 4.0
- Rails 8.1
- PostgreSQL
- Hotwire-ready server-rendered UI

## Local setup

```sh
bundle install
bin/rails db:prepare
bin/rails db:seed
bin/rails server
```

Then open `http://localhost:3000`.

The seeded demo account is:

- Email: `athlete@performanceos.local`
- Password: `performance`

## Next vertical slices

- Body-weight trend snapshots
- Nutrition logging and adaptive expenditure

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...
