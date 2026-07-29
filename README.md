# atmos-cron

Scheduled trigger for the [Atmos](https://github.com/elv591) personal weather app's
severe-weather alert engine. Every ~5 minutes, GitHub Actions fires an
authenticated request to the alert-check endpoint, which polls NWS active
alerts for registered locations and pushes anything new via APNs.

No data lives here — just the schedule. The auth secret is stored in
Actions secrets (`ATMOS_CRON_SECRET`).

A monthly keepalive commit prevents GitHub's 60-day scheduled-workflow
auto-disable.
