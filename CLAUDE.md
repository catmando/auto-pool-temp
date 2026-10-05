# Auto Pool Temp: project handoff

Durable context for any session or machine. Keep this updated and committed.

## What it is
A Rails 8 app that watches the weather forecast for the pool's location and
texts the owner when the pool heater setpoint should change. It plans ahead
using how fast the pool heats and cools.

Owner: Mitch (GitHub `catmando`). Repo: https://github.com/catmando/auto-pool-temp (public).
Single user for now; sign-up closes after the first account.

## Requirements (from the owner)
- The target pool temp is a straight line from outside air temp. Default anchors (since 2026-10-05) are
  95°F air → 75°F pool and 35°F air → 98°F pool, in the hidden **Advanced** settings. The line extrapolates past
  the anchors, but the ideal is **capped at 104°F** (safety), and so are heater settings.
- Users mostly see one **comfort slider, -10..+10°F** ("I like it warmer/cooler") added to the ideal
  (`pool.comfort_adjustment`). Advanced (collapsed): curve anchors, warm-day threshold, heat rate,
  cooling factor, min change, planner. Test mode is collapsed too.
- **Pool party mode** (`PoolParty`): start date/time and end date/time (defaults noon until 11:59 PM the same
  day; multi-day allowed) and a 0..+10 boost that
  *replaces* the comfort adjustment during the window. The water must be on target **when the party starts**:
  `Comfort` weights party hours 20x, and in the 24h before and 48h after, extra warmth barely counts
  (`:around`), so the planner pre-heats and cools off afterward freely. The dashboard shows each party's
  outlook (outside air, party target vs usual target, water at start) from the current plan; it warns when a
  party is no warmer than usual (the boost replaces, not adds to, the comfort setting). UI: the party section
  sits above the plan; each party is its own editable block ("Plan the party"), saved ones show the outlook
  and Delete, editing one hides those until re-saved, and a blank block sits at the end.
- **Run the pump around the clock** (`Decision#pump_extra`, `pool.pump_extended`): offered only when the normal
  pump hours can't keep up with the weather or a party, i.e. heating flat out from the ideal on the normal
  schedule would leave the water more than `pump_boost_threshold` (default 3°F, Advanced) short within the
  stage or the next day, or the water is already that far short now. The gate deliberately ignores the
  water's temperature otherwise (a water-dependent gate taught the planner to run cool to unlock it).
  Alerts say to run it around the clock / go back to the normal schedule; dashboard button; replies
  "pump on" / "pump normal".
- Heater rate **°F per hour** (the owner's: 2). Heat loss/gain to the air follows the owner's standard model
  (`PoolEnvironment`, 2026-10-05), times a **cooling factor** (default 1):
  - cover on: 100°F water at 35°F air loses ~3°F/day, proportional to the water-air gap; air warmer than the
    water warms it 0.3°F/day per degree of gap
  - cover off: loses ~6°F/day at 35°F air and ~2°F/day at 90°F (gap term plus constant evaporation)
- "I have a pool cover" checkbox. With one, the planner decides cover on/off at each check, alerts say
  "take the cover off" / "put the cover back on", and `pool.cover_on` tracks the assumed state (dashboard
  button, or reply "cover on/off").
- **The heater only runs while the pump runs.** One or two daily pump windows (default 4–10am and
  4–10pm). With the pump off the water cools at the cool rate, even below the heater setting.
- Text via Twilio, 1/2/3 checks per day, **only when the setting should change**.
- Each text states the assumed current setting; the user can reply with the real one.
- Weather: use hourly temps if the provider has them. If it only has daily
  high/low, assume the high is at ~3 PM and the low at ~3 AM (`Weather::Forecast.from_daily`).
- The algorithm must be a swappable module the owner can experiment with.
- RSpec, with full specs written alongside the code. **Every change must add or update a spec** (owner,
  2026-10-05). For time/weather-dependent planner behavior, sweep start hours (a single sample missed the
  flip-flop bug); for user-visible features add an end-to-end spec (e.g. save a party, then the dashboard plan
  reflects it). JavaScript behavior gets `js: true` system specs (Cuprite / headless Chrome; set
  BROWSER_PATH if Chrome isn't in a standard place).

## Status (2026-10-04)
- Done: auth, settings UI (geolocation, Open-Meteo place search, curve,
  rates, alerts, strategy), dashboard with SVG forecast/plan chart, preview and
  check-now buttons, "my heater is actually at X" form, message log, hourly
  scheduler, **notification channels (SMS via Twilio, Telegram bot)** with
  **contact confirmation** (texted 6-digit code / Telegram one-time deep link),
  inbound replies on both channels.
- Verified: 441 specs green, RuboCop clean, Brakeman 0 warnings, bundler-audit clean.
- **Twilio is configured** (trial account, number +1 628-296-1482, keys in encrypted
  credentials), **but US carriers block its texts: error 30034, unregistered A2P 10DLC.**
  Long term the owner wants SMS, which needs an account upgrade plus A2P 10DLC registration
  (Sole Proprietor). **Short term: Telegram** (being set up 2026-10-04; bot token goes in
  credentials under `telegram: bot_token:`).
- The owner's real account exists locally (Rochester, NY; cell +1 585-278-6308, which is verified
  on Twilio as a trial recipient).
- **Deployed on Fly.io (2026-10-04): https://auto-pool-temp.fly.dev**. App `auto-pool-temp` (org: personal),
  region ewr, one always-on 512 MB machine (`auto_stop_machines = "off"`, because the scheduler lives there),
  1 GB encrypted volume `pool_data` mounted at `/rails/storage` (all four SQLite DBs; daily snapshots,
  5 kept). Secret: `RAILS_MASTER_KEY`. Puma runs Solid Queue (`SOLID_QUEUE_IN_PUMA=1`), and the
  recurring `scheduled_pool_checks` runs **in production only**. Thruster listens on 8080 (non-root).
  `bin/docker-entrypoint` starts as root, chowns the volume, then drops to the `rails` user via `setpriv`.
  The Telegram and Twilio webhooks point at Fly.
- **Memory:** about 540 MB at rest (Puma + 4 Solid Queue processes) on a 512 MB machine, so `fly.toml` adds
  512 MB swap. A `fly ssh console -C "bin/rails runner ..."` without swap took production down (2026-10-04).
  For read-only queries prefer `sqlite3 -json /rails/storage/production.sqlite3 '...'` over ssh.
- **Local dev:** `bin/dev` (foreman, `Procfile.dev`) runs web only, with no scheduler. `TUNNEL=1 bin/dev` also
  runs `bin/tunnel`, which **takes the webhooks away from production**. Hand them back with
  `bin/rails "notify:webhooks[https://auto-pool-temp.fly.dev]"`. The dev queue DB is
  `storage/development_queue.sqlite3`. Foreman rewrites `PORT` for each process, so the port is passed as `APP_PORT`.

## Next steps
1. Done (2026-10-04): Telegram (@mitch_pool_temp_bot) is linked to the owner's chat and is the active channel.
   Replies (setpoint numbers, STATUS) work through the tunnel.
2. Done: deployed to Fly. Deploy again with `fly deploy`. Logs: `fly logs`. Console:
   `fly ssh console -C "bin/rails console"`. The owner still needs to sign up on the live site and reconnect Telegram there.
3. SMS for real: upgrade Twilio, then register A2P 10DLC (or verify a toll-free number).
   **`config/master.key` is gitignored. Copy it to other machines yourself, or the
   credentials won't decrypt.**
4. Partly done: SMS delivery status is looked up from Twilio (`TextMessage#refresh_delivery_status!`)
   on the Settings page, the Messages page, and right after sending a code, with error codes explained
   in plain English. Still TODO: PoolCheck assumes the user followed an alert as soon as Twilio
   *queues* it, so a later carrier rejection doesn't undo that (fix with a status callback or a recheck).
5. `bin/tunnel` now waits for the tunnel to answer `/up` before registering webhooks, because Telegram
   rejects hostnames it can't resolve yet, and retries. The first version registered too early
   (2026-10-04). The fix passes `ruby -c` but hasn't been run end to end.
6. Keep tuning the planner with the owner using the Lab page (2026-10-04: the owner wants to iterate).
7. UI is **Telegram-only** for now (no channel picker or phone field). SMS code paths and specs remain
   for when A2P registration is done. Sign-up stays closed; the sign-in page says so.

## Architecture
- `Weather::Forecast` is a normalized time series of air temps (°F), with
  `temp_at`, `smoothed` (centered 24h moving average) and `.from_daily`.
- `Weather::OpenMeteo` is the provider (forecast + `time_zone_for`, no API key). `Geocoder` (OpenStreetMap
  Nominatim) turns ZIP codes or cities into coordinates and names map picks; specs use `FakeGeocoder`.
  Settings has a Leaflet map (vendored via importmap) with ZIP search, use-my-location, and click-to-pick,
  then Confirm (`LocationsController`). The app-wide
  provider is `Weather.provider`, which specs swap for `FakeWeather`.
- `TargetCurve` maps air temp to ideal pool temp from the two anchors.
- `Recommenders` holds the **swappable planners**. `Recommenders.registry` maps key to class; a pool
  picks one with `pool.strategy`. Each planner produces a **heater schedule**: one whole-degree setting
  per scheduled check (1–3/day), held until the next check (`Recommenders::SchedulePlanner`).
  The shared base simulates the water hour by hour from its current temperature (`PoolPhysics.step`,
  the water always gains/loses heat to the hourly air temp via `PoolEnvironment`, and the heater adds up to
  heat_rate while the pump runs (`PumpSchedule#on_fraction`), stopping at the setting. Each stage's decision is
  a setting plus cover on/off (`SchedulePlanner::Decision`). scores it with
  `Comfort`, merges multi-day ramps into one setting change (`merge_ramps`: while the water is moving
  flat out, a further setting does the same thing), and writes the reason text.
  - **Change discipline** (`Search#best_decision`): the cover stays on unless off is noticeably better, and
    the setting stays put unless a change is noticeably better (`KEEP_SETTING_SLACK` = 2 °F·hours). At 0.5 the
    plan flip-flopped (91/92) about every check in steady weather (~19 changes in 16 days); found and fixed
    2026-10-05. Planning starts from the pool's actual heater setting (`current_setpoint`).
  - `search` (default): dynamic programming over water temperature (0.5°F grid) and integer settings,
    over the whole 16-day forecast, minimizing total discomfort. It prefers keeping the current setting
    unless a change helps noticeably (`KEEP_SETTING_SLACK`), and breaks ties toward the next day's ideal.
  - `follow`: baseline. Each check is set to that period's ideal; it never plans ahead.
  - Tried and dropped (2026-10-04): `head_start` (rule-of-thumb deadlines; erratic, pre-cooled
    during a cold snap) and the old continuous `lookahead`/`linear` (ignored the actual water temp,
    which is why it said nonsense like "has to start heating now").
- **Comfort model (owner's framing: comfort, not cost):** the ideal comes from the curve applied to the
  24h-average air. On a day at or above the **warm-day threshold** (default 80°F), water a little *cooler*
  than ideal feels fine; below it, a little *warmer* feels fine (`Comfort::LEEWAY` = 2°F free in that
  direction). Off in the other direction counts in full. The owner said there's no right answer to how
  lopsided this should be, so it's not a setting.
- **Lab page (`/lab`, `PlannerLab`)**: runs every planner on the live forecast plus made-up weather
  (cold snap, heat wave, choppy fall), with the pool's own settings, and shows comfort scores and charts.
  Use it to compare and tune planners. Latest results: Search is best in every scenario.
- **Planner benchmark** (`PlannerBenchmark`, `spec/models/planner_benchmark_spec.rb`): fixed scenarios (the
    Rochester Oct 4 forecast in `spec/fixtures/forecasts/`, plus the made-up patterns on fixed dates, with the owner's
    settings). The spec fails if the default planner's **mean_error** (average |expected water - ideal|, the owner's
    headline metric) or **mean_discomfort** gets worse than `spec/fixtures/planner_baseline.yml` on any scenario.
    The baseline was re-recorded for the pump model, then for the air/cover model, on 2026-10-05 (scores from different physics aren't
    comparable). `bin/rails planner:benchmark` compares; `bin/rails planner:record_baseline` accepts improvements (commit the diff).
    To add a scenario, drop a forecast JSON in `spec/fixtures/forecasts/` and re-record.
  - **Test mode** (`ForecastSnapshot`, `pool.test_snapshot`): plan against a saved forecast with "now" frozen at
    `taken_at` and no alerts; the scheduler skips test-mode pools. Save from Settings (live forecast, or the
    one behind the current plan) or `bin/rails "snapshots:from_recommendation[ID,NAME]"`. Snapshot 1 in
    production is the owner's Oct 4 3pm Rochester forecast (the Friday-overshoot case).
  - `CurrentPlan` re-plans by itself (no alert) when the plan is >1h old, made before the app booted (so a deploy
    with planner changes shows up on the next refresh), or older than `pool.updated_at`. Used by the dashboard.
    **Settings autosave** on every change (`autosave_controller.js`, JSON PATCH). The plan chart is only on
    the dashboard; the owner asked to remove it from Settings (2026-10-04). The dashboard cards distinguish the heater dial (only used to decide
    alerts) from the measured water temp (where the plan starts); the owner confused them on 2026-10-04
    (settings, heater setting, water reading, test mode). The "Preview now" button is gone.
- Water temperature: `pool.estimated_water_temp(time)` advances the last known value (reported with
  "water 86" by reply or on the dashboard, or banked by `record_setpoint!`) toward the heater setting.
  With nothing known, it's assumed to match the setting.
- `PoolCheck` fetches the forecast, runs the recommender, saves a `Recommendation`, and
  texts if `pool.needs_change?` (min_change hysteresis). After a successful text it
  assumes the user followed it. `notify: false` gives a preview.
- `Sms::TwilioSetup` plus the `twilio:status`, `twilio:webhook[url]` and `twilio:test_sms` rake tasks.
  `bin/tunnel` starts a cloudflared quick tunnel to localhost:3000 and points the Twilio number's
  incoming-SMS webhook at it (the URL changes every run). The signed-webhook check was verified
  through a real tunnel. Dev `config.hosts` allows `.trycloudflare.com` and `.ngrok-free.app`.
- `Notifications`: channels `sms` and `telegram`. `pool.notification_channel` picks one, and
  `Notifications.sender(channel)` / `.address(pool)` route messages. `TextMessage.deliver` logs every
  message (any channel) and never raises. Alerts only go out when `pool.notifiable?` (enabled and
  contact confirmed).
  - SMS confirmation: `PhoneVerification` (6-digit code, bcrypt digest, 10 min TTL, 5 tries, 30s
    resend wait). Changing the phone number un-confirms it. Users can reply to the text with the code.
  - Telegram: `TelegramBot` (Bot API over Net::HTTP; webhook secret derived from the token) and
    `TelegramLink` (one-time t.me/<bot>?start=<token> deep link, 30 min TTL).
  - `InboundMessage` handles replies on both channels (codes, /start, setpoint numbers, STATUS,
    PAUSE/RESUME) and replies on the same channel.
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
bin/dev                  # local web app, http://localhost:3000 (no scheduler; production runs it)
TUNNEL=1 bin/dev         # also take over the bot webhooks (hand them back afterwards, see above)
fly deploy               # ship to https://auto-pool-temp.fly.dev
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
