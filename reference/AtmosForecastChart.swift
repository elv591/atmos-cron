import SwiftUI

/// Redesigned 24-hour temperature chart for the Atmos widget.
///
/// Drop-in replacement for the bare auto-scaled spline. Pure SwiftUI
/// (GeometryReader + Path), no Swift Charts, no dependencies — works in a
/// WidgetKit extension on iOS 16+.
///
/// What it adds over a raw line:
///  - a "now" dot + label, so the headline temp lands on the curve
///  - H/L labeled on the curve at the hour they occur
///  - real clock ticks every 6 h (NOW · 2A · 8A · 2P) instead of +12H offsets
///  - a dimmed sunset→sunrise night band
///  - y-domain padded to a minimum span with 5° gridlines, so a calm day
///    draws a calm line
///  - monotone interpolation — the curve passes through the data without
///    the overshoot bumps a Catmull-Rom spline invents
///  - optional rain-chance lane (dot columns) where hourly probability ≥ 20%
struct AtmosForecastChart: View {

    struct HourPoint {
        let time: Date
        let temp: Double
        /// Precipitation probability 0–100. Pass nil to omit the rain lane.
        let precipChance: Double?
    }

    let points: [HourPoint]
    /// Dark bands, e.g. from `AtmosForecastChart.nightIntervals(...)`.
    var nightIntervals: [DateInterval] = []
    /// Minimum number of degrees the y-axis spans (padding beyond the data).
    var minSpan: Double = 20

    // Styling — defaults match the widget; swap fonts for the Atmos face.
    var lineColor: Color = Color(red: 0.88, green: 0.23, blue: 0.18)
    var ink: Color = .white
    var rainColor: Color = Color(red: 0.50, green: 0.69, blue: 0.77)
    var labelFont: Font = .system(size: 10, weight: .medium, design: .monospaced)
    var valueFont: Font = .system(size: 12, weight: .semibold, design: .monospaced)

    private var showRain: Bool {
        points.contains { ($0.precipChance ?? 0) >= 20 }
    }

    var body: some View {
        GeometryReader { geo in
            if points.count >= 2 {
                chart(in: geo.size)
            }
        }
    }

    // MARK: - Layout

    private struct Frame {
        let plot: CGRect          // where the line lives
        let tickY: CGFloat        // baseline for clock labels
        let rain: CGRect?         // rain lane, if shown
        let yLabelX: CGFloat      // x for gridline value labels
    }

    private func frame(in size: CGSize) -> Frame {
        let yLabelLane: CGFloat = 26
        let tickLane: CGFloat = 20
        let rainLane: CGFloat = showRain ? 18 : 0
        let plot = CGRect(x: 0, y: 6,
                          width: size.width - yLabelLane,
                          height: size.height - 6 - tickLane - rainLane)
        let rain = showRain
            ? CGRect(x: 0, y: size.height - rainLane + 2, width: plot.width, height: rainLane - 4)
            : nil
        return Frame(plot: plot,
                     tickY: plot.maxY + tickLane * 0.62,
                     rain: rain,
                     yLabelX: size.width - yLabelLane / 2)
    }

    private func chart(in size: CGSize) -> some View {
        let f = frame(in: size)
        let temps = points.map(\.temp)
        let domain = Self.paddedDomain(lo: temps.min() ?? 0, hi: temps.max() ?? 0, minSpan: minSpan)
        let t0 = points.first!.time, t1 = points.last!.time
        let span = max(t1.timeIntervalSince(t0), 1)

        func xAt(_ date: Date) -> CGFloat {
            let u = date.timeIntervalSince(t0) / span
            return f.plot.minX + CGFloat(min(max(u, 0), 1)) * f.plot.width
        }
        func yAt(_ temp: Double) -> CGFloat {
            let u = (domain.upperBound - temp) / (domain.upperBound - domain.lowerBound)
            return f.plot.minY + CGFloat(u) * f.plot.height
        }

        let pts = points.map { CGPoint(x: xAt($0.time), y: yAt($0.temp)) }
        let line = Self.monotonePath(pts)

        // H/L indices — center the low label across a flat overnight run.
        let maxVal = temps.max()!, minVal = temps.min()!
        let hiIdx = temps.firstIndex(of: maxVal)!
        let loIdx = (temps.firstIndex(of: minVal)! + temps.lastIndex(of: minVal)!) / 2

        return ZStack(alignment: .topLeading) {
            // Night bands
            ForEach(Array(nightIntervals.enumerated()), id: \.offset) { _, night in
                let x0 = xAt(night.start), x1 = xAt(night.end)
                if x1 - x0 > 1 {
                    Rectangle()
                        .fill(ink.opacity(0.05))
                        .frame(width: x1 - x0, height: f.plot.height)
                        .position(x: (x0 + x1) / 2, y: f.plot.midY)
                }
            }

            // 5° gridlines with right-edge value labels
            ForEach(Self.gridValues(in: domain), id: \.self) { g in
                Path { p in
                    p.move(to: CGPoint(x: f.plot.minX, y: yAt(g)))
                    p.addLine(to: CGPoint(x: f.plot.maxX, y: yAt(g)))
                }
                .stroke(ink.opacity(0.08), lineWidth: 1)
                Text("\(Int(g))°")
                    .font(labelFont)
                    .foregroundStyle(ink.opacity(0.45))
                    .position(x: f.yLabelX, y: yAt(g))
            }

            // Area fill under the curve
            line
                .appendingBaseline(from: pts, atY: f.plot.maxY)
                .fill(LinearGradient(colors: [lineColor.opacity(0.13), .clear],
                                     startPoint: .top, endPoint: .bottom))

            // The temperature line
            line.stroke(lineColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            // High / low, at the hour they occur (skip if "now" already is one)
            if hiIdx != 0 {
                Text("\(Int(maxVal.rounded()))°")
                    .font(valueFont)
                    .foregroundStyle(ink)
                    .position(x: min(max(pts[hiIdx].x, 16), f.plot.maxX - 16),
                              y: max(pts[hiIdx].y - 14, 8))
            }
            if loIdx != 0 {
                Text("\(Int(minVal.rounded()))°")
                    .font(valueFont)
                    .foregroundStyle(ink.opacity(0.75))
                    .position(x: min(max(pts[loIdx].x, 16), f.plot.maxX - 16),
                              y: min(pts[loIdx].y + 15, f.plot.maxY - 2))
            }

            // Now: dot on the curve + current temp beside it
            Circle()
                .fill(ink)
                .frame(width: 8, height: 8)
                .position(pts[0])
            Text("\(Int(points[0].temp.rounded()))°")
                .font(valueFont)
                .foregroundStyle(ink)
                .position(x: pts[0].x + 20,
                          y: pts[0].y < 24 ? pts[0].y + 16 : pts[0].y - 13)

            // Clock ticks every 6 hours
            ForEach(Array(Self.tickDates(from: t0, to: t1).enumerated()), id: \.offset) { i, tick in
                let x = xAt(tick)
                Path { p in
                    p.move(to: CGPoint(x: x, y: f.plot.maxY))
                    p.addLine(to: CGPoint(x: x, y: f.plot.maxY + 5))
                }
                .stroke(ink.opacity(0.28), lineWidth: 1)
                Text(i == 0 ? "NOW" : Self.hourLabel(tick))
                    .font(labelFont)
                    .foregroundStyle(ink.opacity(0.5))
                    .position(x: min(max(x, 16), f.plot.maxX - 12), y: f.tickY)
            }

            // Rain-chance lane: dot columns where the story is
            if let lane = f.rain {
                ForEach(Array(points.enumerated()), id: \.offset) { _, pt in
                    if let chance = pt.precipChance, chance >= 20 {
                        let dots = max(1, Int((min(chance, 100) / 100 * 4).rounded(.up)))
                        ForEach(0..<dots, id: \.self) { d in
                            Circle()
                                .fill(rainColor.opacity(0.6))
                                .frame(width: 3, height: 3)
                                .position(x: xAt(pt.time),
                                          y: lane.maxY - 2 - CGFloat(d) * 4.5)
                        }
                    }
                }
                Text("RAIN")
                    .font(labelFont)
                    .foregroundStyle(ink.opacity(0.35))
                    .position(x: f.yLabelX, y: lane.midY)
            }
        }
    }

    // MARK: - Scale helpers

    /// Widens `hi - lo` to at least `minSpan` degrees, centered on the data,
    /// with a couple of degrees of breathing room on each side.
    static func paddedDomain(lo: Double, hi: Double, minSpan: Double = 20) -> ClosedRange<Double> {
        var low = lo.rounded(.down) - 2
        var high = hi.rounded(.up) + 2
        let deficit = minSpan - (high - low)
        if deficit > 0 {
            low -= (deficit / 2).rounded(.up)
            high += (deficit / 2).rounded(.up)
        }
        return low...high
    }

    static func gridValues(in domain: ClosedRange<Double>) -> [Double] {
        var values: [Double] = []
        var g = (domain.lowerBound / 5).rounded(.up) * 5
        while g <= domain.upperBound {
            // Skip lines hugging the edges — they read as a border, not a grid.
            if g - domain.lowerBound >= 1.5 && domain.upperBound - g >= 1.5 { values.append(g) }
            g += 5
        }
        return values
    }

    static func tickDates(from start: Date, to end: Date) -> [Date] {
        var ticks: [Date] = []
        var t = start
        while t <= end {
            ticks.append(t)
            t = t.addingTimeInterval(6 * 3600)
        }
        return ticks
    }

    /// "2A", "12P" — the compact style the hourly strip already uses.
    static func hourLabel(_ date: Date) -> String {
        let h = Calendar.current.component(.hour, from: date)
        let suffix = h >= 12 ? "P" : "A"
        var h12 = h % 12
        if h12 == 0 { h12 = 12 }
        return "\(h12)\(suffix)"
    }

    /// Pairs each sunset with the following sunrise (open-meteo
    /// `daily=sunrise,sunset` arrays) and clamps the result to `span` —
    /// including the case where the span starts mid-night.
    static func nightIntervals(sunrises: [Date], sunsets: [Date], covering span: DateInterval) -> [DateInterval] {
        var events = sunrises.map { ($0, true) } + sunsets.map { ($0, false) }
        events.sort { $0.0 < $1.0 }
        var intervals: [DateInterval] = []
        // Night at span start unless the first event we see is a sunset.
        var nightStart: Date? = (events.first?.1 == false) ? nil : span.start
        for (date, isSunrise) in events {
            if isSunrise {
                if let start = nightStart, date > start {
                    intervals.append(DateInterval(start: start, end: date))
                }
                nightStart = nil
            } else if nightStart == nil {
                nightStart = date
            }
        }
        if let start = nightStart, span.end > start {
            intervals.append(DateInterval(start: start, end: span.end))
        }
        return intervals.compactMap { $0.intersection(with: span) }.filter { $0.duration > 60 }
    }

    // MARK: - Curve

    /// Fritsch–Carlson monotone cubic interpolation: smooth, but never
    /// overshoots the data the way Catmull-Rom-style smoothing does.
    static func monotonePath(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        guard pts.count > 2 else {
            pts.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }
        let n = pts.count
        var dx = [CGFloat](repeating: 0, count: n - 1)
        var slope = [CGFloat](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            dx[i] = max(pts[i + 1].x - pts[i].x, 0.001)
            slope[i] = (pts[i + 1].y - pts[i].y) / dx[i]
        }
        var tangent = [CGFloat](repeating: 0, count: n)
        tangent[0] = slope[0]
        tangent[n - 1] = slope[n - 2]
        for i in 1..<(n - 1) {
            tangent[i] = slope[i - 1] * slope[i] <= 0 ? 0 : (slope[i - 1] + slope[i]) / 2
        }
        for i in 0..<(n - 1) {
            if slope[i] == 0 {
                tangent[i] = 0
                tangent[i + 1] = 0
            } else {
                let a = tangent[i] / slope[i]
                let b = tangent[i + 1] / slope[i]
                let h = (a * a + b * b).squareRoot()
                if h > 3 {
                    tangent[i] = 3 * slope[i] * a / h
                    tangent[i + 1] = 3 * slope[i] * b / h
                }
            }
        }
        for i in 0..<(n - 1) {
            let s = dx[i] / 3
            path.addCurve(
                to: pts[i + 1],
                control1: CGPoint(x: pts[i].x + s, y: pts[i].y + tangent[i] * s),
                control2: CGPoint(x: pts[i + 1].x - s, y: pts[i + 1].y - tangent[i + 1] * s)
            )
        }
        return path
    }
}

private extension Path {
    /// Closes a line path down to a baseline so it can be gradient-filled.
    func appendingBaseline(from pts: [CGPoint], atY baseline: CGFloat) -> Path {
        var p = self
        guard let last = pts.last, let first = pts.first else { return p }
        p.addLine(to: CGPoint(x: last.x, y: baseline))
        p.addLine(to: CGPoint(x: first.x, y: baseline))
        p.closeSubpath()
        return p
    }
}

// MARK: - Preview (the Jacksonville evening from the screenshot)

struct AtmosForecastChart_Previews: PreviewProvider {
    static var previews: some View {
        let cal = Calendar.current
        let start = cal.date(bySettingHour: 20, minute: 0, second: 0, of: Date())!
        let temps: [Double] = [80, 79, 78, 77, 77, 76, 76, 75, 75, 75, 75, 75,
                               76, 79, 83, 86, 89, 91, 90, 88, 90, 89, 87, 85, 83]
        let probs: [Double] = [15, 10, 10, 5, 5, 5, 5, 5, 5, 5, 10, 10,
                               15, 20, 30, 40, 55, 60, 50, 45, 40, 30, 25, 20, 15]
        let points = temps.indices.map { i in
            AtmosForecastChart.HourPoint(
                time: start.addingTimeInterval(Double(i) * 3600),
                temp: temps[i],
                precipChance: probs[i]
            )
        }
        let sunrise = cal.date(byAdding: .hour, value: 11, to: start)!
        let nights = AtmosForecastChart.nightIntervals(
            sunrises: [sunrise],
            sunsets: [start.addingTimeInterval(-600)],
            covering: DateInterval(start: start, end: start.addingTimeInterval(24 * 3600))
        )

        AtmosForecastChart(points: points, nightIntervals: nights)
            .frame(width: 320, height: 210)
            .padding(20)
            .background(Color(red: 0.08, green: 0.08, blue: 0.08))
            .previewLayout(.sizeThatFits)
    }
}
