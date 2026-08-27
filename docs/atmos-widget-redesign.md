# Atmos widget: temperature-graph redesign spec

Status: **spec + reference implementation** — the widget itself lives in the
Atmos iOS app (a local Xcode project, not on GitHub), so it can't be patched
from here. A complete drop-in SwiftUI view implementing this spec is at
[`reference/AtmosForecastChart.swift`](../reference/AtmosForecastChart.swift):
pure GeometryReader + Path, no Swift Charts, no dependencies, iOS 16+,
WidgetKit-safe. Drag it into the Atmos project and feed it the hourly data the
widget already has.

## The problem

The medium widget's red line is the next 24 hours of temperature (left = now,
right = this time tomorrow), but it reads as a random squiggle because the chart
withholds every cue needed to see that:

| Issue | Effect |
|---|---|
| No "now" marker | Headline temp (e.g. 80°) appears nowhere on the curve |
| Auto-fit y-axis | 16° of range stretched to full height; a 2° wobble looks like a front |
| Relative x labels (`+12H`) | Reader must do clock math; the overnight dip isn't obviously "dawn" |
| H/L only in header | 91°/75° are printed above but unfindable on the curve |
| Overshooting spline | Catmull-Rom-style smoothing invents bumps the forecast doesn't contain |

## The redesign

Same data, six rendering changes:

1. **Now-dot + label** — white point at the line's start, annotated with the
   current temp. Ties the headline number to the curve.
2. **Clock ticks, not offsets** — x-axis ticks every 6 h in local time
   (`NOW · 2A · 8A · 2P · 8P`).
3. **Night band** — dimmed rect (`white.opacity(0.05)`) from sunset to sunrise,
   so the overnight dip explains itself.
4. **H/L labeled on the curve** — `91°` above the peak, `75°` under the trough,
   at the hour they occur.
5. **Honest scale** — pad the y-domain to a minimum 20 °F span (centered on the
   data) and draw faint 5° gridlines with small right-edge labels. Calm days
   draw calm lines.
6. **Monotone interpolation** — `.interpolationMethod(.monotone)` instead of an
   overshooting spline.

Optional: a short rain-chance lane pinned under the chart — dotted columns from
the hourly `precipitation_probability` series, drawn only where ≥ 20%. Keep it
a separate mini-plot (own 0–100% scale, ~14 pt tall) — never a second y-axis on
the temperature chart.

## Data

Everything is already in the Open-Meteo response the app uses
(`hourly=temperature_2m,precipitation_probability`). The night band needs one
addition to the request: `&daily=sunrise,sunset`.

## Swift Charts sketch

```swift
Chart {
    // Night band first, so everything draws above it
    RectangleMark(xStart: .value("", sunset), xEnd: .value("", sunrise))
        .foregroundStyle(.white.opacity(0.05))

    ForEach(hours) { h in
        AreaMark(x: .value("Hour", h.time), y: .value("°F", h.temp))
            .interpolationMethod(.monotone)
            .foregroundStyle(.linearGradient(
                colors: [atmosRed.opacity(0.12), .clear],
                startPoint: .top, endPoint: .bottom))
        LineMark(x: .value("Hour", h.time), y: .value("°F", h.temp))
            .interpolationMethod(.monotone)   // kills the overshoot bumps
            .lineStyle(StrokeStyle(lineWidth: 2.5))
            .foregroundStyle(atmosRed)
    }

    PointMark(x: .value("Hour", now), y: .value("°F", currentTemp))
        .foregroundStyle(.white)
        .annotation(position: .topTrailing) { Text(currentTempText).font(.footnote.bold()) }
    // + annotations at the hi/lo hours: "91°", "75°"
}
.chartYScale(domain: paddedDomain(lo: lo, hi: hi, minSpan: 20))
.chartYAxis { AxisMarks(values: .stride(by: 5)) { AxisGridLine().foregroundStyle(.white.opacity(0.08)) } }
.chartXAxis {
    AxisMarks(values: .stride(by: .hour, count: 6)) {
        AxisValueLabel(format: .dateTime.hour())   // "2 AM", not "+6H"
    }
}
```

`paddedDomain(lo:hi:minSpan:)` widens `hi - lo` to at least `minSpan`, centered
on the data, then rounds outward to whole degrees.

The hourly strip below the chart already works; one optional tweak is a small
rain % under any hour at ≥ 20%.
