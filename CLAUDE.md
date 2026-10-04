# Auto Pool Temp: project handoff

Durable context for any session or machine. Keep this updated and committed.

## What it is
A Rails 8 app that watches the weather forecast for the pool's location and
texts the owner when the pool heater setpoint should change. It plans ahead
using how fast the pool heats and cools.

Owner: Mitch (GitHub `catmando`). Repo: https://github.com/catmando/auto-pool-temp (public).
Single user for now; sign-up closes after the first account.

## Requirements (from the owner)
- The target pool temp is a straight line from outside air temp. Default anchors are
  95°F air → 80°F pool and 35°F air → 102°F pool. Both anchors are user-adjustable.
  **The line keeps extrapolating past the anchors (no clamping), by owner's choice.**
- User-set heat-up and cool-down rates (°F/day) decide how early to act.
- Text via Twilio, 1/2/3 checks per day, **only when the setting should change**.
- Each text states the assumed current setting; the user can reply with the real one.
- Weather: use hourly temps if the provider has them. If it only has daily
  high/low, assume the high is at ~3 PM and the low at ~3 AM (`Weather::Forecast.from_daily`).
- The algorithm must be a swappable module the owner can experiment with.
- RSpec, with full specs written alongside the code.

## Status (2026-10-03)
- Done: auth, settings UI (geolocation, Open-Meteo place search, curve,
  rates, alerts, strategy), dashboard with SVG forecast/plan chart, preview and
  check-now buttons, "my heater is actually at X" form, text log, hourly
  scheduler, Twilio sender, inbound SMS webhook with signature validation.
- Verified: 186 specs green, RuboCop clean, Brakeman 0 warnings, bundler-audit clean.
  A manual run against the live Open-Meteo API (Austin, TX) works and the dashboard renders.
- **Twilio is not wired up yet.** Without credentials, texts are logged
  (`Sms::LogSender`) and stored in `text_messages` with status `logged`.
- **Running locally on the owner's Mac for now** via `bin/dev`, which starts Puma with the Solid Queue
  supervisor (`SOLID_QUEUE_IN_PUMA=1`), so the hourly scheduler runs in the same process. Development
  uses a separate queue DB (`storage/development_queue.sqlite3`). Checks missed while the Mac sleeps
  run at the next hourly tick (`Pool#due?` catches up). Inbound SMS replies need a public URL, so use a
  tunnel (cloudflared/ngrok) or wait until it is hosted.
- **Hosting for later.** Options discussed: Render/Fly (~$5–7/mo),
  Kamal/Hatchbox on a VPS (Kamal config is generated), or a home machine.

## Next steps
1. Finish Twilio: the owner is creating a trial account (2026-10-03). Put keys in
   `bin/rails credentials:edit` under `twilio:` (account_sid, auth_token, from_number), or in ENV
   `TWILIO_*` (ENV wins). Then `bin/rails twilio:status`, `bin/rails twilio:test_sms`, and
   `bin/tunnel` for replies. Trial accounts can only text verified numbers. Upgrading needs
   A2P 10DLC (or toll-free verification) for US numbers.
   **`config/master.key` is gitignored. Copy it to other machines yourself, or the
   credentials (Twilio keys) won't decrypt.**
2. Eventually choose hosting. The job runner must run all the time, either `bin/jobs` or Puma with
   `SOLID_QUEUE_IN_PUMA=1`, so `ScheduledChecksJob` fires hourly.
3. Tune the algorithm with real data (see below).

## Architecture
- `Weather::Forecast` is a normalized time series of air temps (°F), with
  `temp_at`, `smoothed` (centered 24h moving average) and `.from_daily`.
- `Weather::OpenMeteo` is the provider (forecast + geocoding, no API key). The app-wide
  provider is `Weather.provider`, which specs swap for `FakeWeather`.
- `TargetCurve` maps air temp to ideal pool temp from the two anchors.
- `Recommenders` holds the **swappable algorithms**. `Recommenders.registry` maps key to class.
  Every class subclasses `Recommenders::Base`, implements `#call`, and returns a
  `Recommenders::Result(raw_target, reason, details)`. A pool picks one with `pool.strategy`.
  To add an algorithm: write a class and add it to the registry; nothing else changes.
  - `linear`: the curve applied to the smoothed air temp now.
  - `lookahead` (default): a backward pass over the forecast. It clamps the plan to
    the heat/cool rates so the pool starts changing early enough. It **only anticipates
    a change that is at least as extreme** (as far from the curve's midpoint) as the
    current target. So it pre-heats for a cold snap but does not pre-cool *during* a cold
    snap just because mild weather follows. A forward pass then models lag for the chart.
    If anticipation is needed before the next scheduled check, it recommends the target
    being chased (a heater runs flat out until it reaches its setpoint). This
    asymmetry is a judgment call the owner may want to revisit.
- `PoolCheck` fetches the forecast, runs the recommender, saves a `Recommendation`, and
  texts if `pool.needs_change?` (min_change hysteresis). After a successful text it
  assumes the user followed it. `notify: false` gives a preview.
- `Sms::TwilioSetup` plus the `twilio:status`, `twilio:webhook[url]` and `twilio:test_sms` rake tasks.
  `bin/tunnel` starts a cloudflared quick tunnel to localhost:3000 and points the Twilio number's
  incoming-SMS webhook at it (the URL changes every run). The signed-webhook check was verified
  through a real tunnel. Dev `config.hosts` allows `.trycloudflare.com` and `.ngrok-free.app`.
- `SmsReply` handles inbound texts: a number (actual setting, then re-advise),
  STATUS, PAUSE/RESUME, or help.
- `Sms.sender` uses `TwilioSender` when configured, otherwise `LogSender`. `TextMessage.deliver`
  logs every send and never raises.
- Scheduling: `config/recurring.yml` runs `ScheduledChecksJob` hourly at :05. It enqueues
  `PoolCheckJob` for pools whose local check hour (`Pool::CHECK_HOURS`: 7am / 7am+5pm /
  7am+1pm+7pm) has arrived and which haven't been checked this hour.
- Pool time zone: set from geolocation or search, and also adopted from Open-Meteo's
  response on each check.

## How to run
```sh
bundle install
bin/rails db:prepare
bin/dev                  # http://localhost:3000 — web UI + scheduler in one process
bundle exec rspec        # full suite
bin/ci                   # rubocop + audits + brakeman + rspec
```
Ruby 3.4.7 (`.ruby-version`), Rails 8.1, SQLite. The Gemfile.lock includes the Windows
(`x64-mingw-ucrt`) platform.

Quick manual check from the console:
`PoolCheck.call(User.first.pool, notify: false).recommendation`

## Conventions
- Specs: `spec/models` (domain), `spec/requests`, `spec/jobs`, `spec/helpers`,
  `spec/system` (rack_test, no JS). Factories are in `spec/factories`. Fakes are in `spec/support`.
  WebMock blocks all real HTTP in specs.
- Every user gets a pool on create (`User after_create`). The `:pool` factory reuses it.
