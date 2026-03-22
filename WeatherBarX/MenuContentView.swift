import AppKit
import Charts
import SwiftUI

private enum MenuDetailColors {
    static let detail = Color(nsColor: NSColor.labelColor)
    static let meta = Color(nsColor: NSColor.secondaryLabelColor)
    static let iconColumnWidth: CGFloat = 20
}

enum TemperatureChartLabelAlignmentResolver {
    static func alignment(forRunStartingAt startIndex: Int, endingAt endIndex: Int, pointCount: Int) -> Alignment {
        if startIndex <= 1 {
            return .leading
        }

        if endIndex >= pointCount - 2 {
            return .trailing
        }

        return .center
    }
}

private enum AddLocationMode: String, CaseIterable, Identifiable {
    case search
    case detect
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual:
            return "Manual"
        case .detect:
            return "Detect"
        case .search:
            return "Search"
        }
    }
}

private struct DetailRow: View {
    let iconName: String
    let text: String
    let accessibilityIdentifier: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .frame(width: MenuDetailColors.iconColumnWidth, alignment: .center)

            Text(text)

            Spacer(minLength: 0)
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct TemperatureUnitToggleLabel: View {
    let temperatureUnit: TemperatureUnit

    var body: some View {
        HStack(spacing: 0) {
            unitText("°F", isSelected: temperatureUnit == .fahrenheit)
            Text("/")
                .foregroundStyle(.tertiary)
            unitText("°C", isSelected: temperatureUnit == .celsius)
        }
    }

    private func unitText(_ text: String, isSelected: Bool) -> some View {
        Text(text)
            .fontWeight(isSelected ? .semibold : .regular)
            .foregroundStyle(isSelected ? .primary : .tertiary)
    }
}

private struct WeatherCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            content
        }
        .padding(8)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct TemperatureTrendCardModel {
    let title: String
    let points: [WeatherViewModel.TemperatureChartPoint]
    let high: Int?
    let highAt: Date?
    let low: Int?
    let lowAt: Date?
    let markers: [WeatherViewModel.TimeMarker]
    let xDomain: ClosedRange<Date>?
    let yDomain: ClosedRange<Double>?
    let valueText: (Int) -> String
    let markerLabelText: (WeatherViewModel.TimeMarker) -> String
    let markerTimeText: (Date) -> String
    let hourLabelText: (Date) -> String
    let timeZoneIdentifier: String?
    let details: TemperatureTrendDetailsModel?
}

private struct TemperatureTrendDetailsModel {
    let highDetailText: String
    let lowDetailText: String
    let sunriseText: String
    let sunsetText: String
}

private enum TemperatureTrendCardTab: String {
    case today
    case next24Hours

    var title: String {
        switch self {
        case .today:
            return "Today's Temperatures"
        case .next24Hours:
            return "Next 24 Hours"
        }
    }
}

private struct TemperatureTrendCardView: View {
    @Binding var isShowingDetails: Bool
    @Binding var selectedTab: TemperatureTrendCardTab
    let todayModel: TemperatureTrendCardModel
    let next24HourModel: TemperatureTrendCardModel?

    var body: some View {
        WeatherCard(title: "") {
            temperatureHeader

            TemperatureTrendChartContentView(model: activeModel)

            if let details = activeModel.details {
                TemperatureTrendDetailsView(
                    isExpanded: $isShowingDetails,
                    highDetailText: details.highDetailText,
                    lowDetailText: details.lowDetailText,
                    sunriseText: details.sunriseText,
                    sunsetText: details.sunsetText
                )
            }
        }
    }

    private var activeModel: TemperatureTrendCardModel {
        if selectedTab == .next24Hours, let next24HourModel {
            return next24HourModel
        }

        return todayModel
    }

    private var temperatureHeader: some View {
        HStack(spacing: 8) {
            if next24HourModel != nil {
                tabButton(for: .next24Hours)

                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            tabButton(for: .today)
        }
    }

    private func tabButton(for tab: TemperatureTrendCardTab) -> some View {
        Button(action: {
            selectedTab = tab
        }) {
            Text(tab.title)
                .font(.caption.weight(selectedTab == tab ? .semibold : .regular))
                .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(tab == .next24Hours && next24HourModel == nil)
    }
}

private struct TemperatureTrendDetailsView: View {
    @Binding var isExpanded: Bool
    let highDetailText: String
    let lowDetailText: String
    let sunriseText: String
    let sunsetText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                isExpanded.toggle()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                    Text("Details")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        DetailRow(
                            iconName: "thermometer.high",
                            text: highDetailText,
                            accessibilityIdentifier: "high-detail-text"
                        )

                        DetailRow(
                            iconName: "thermometer.low",
                            text: lowDetailText,
                            accessibilityIdentifier: "low-detail-text"
                        )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        DetailRow(
                            iconName: "sunrise",
                            text: sunriseText,
                            accessibilityIdentifier: "sunrise-text"
                        )

                        DetailRow(
                            iconName: "sunset.fill",
                            text: sunsetText,
                            accessibilityIdentifier: "sunset-text"
                        )
                    }
                }
                .font(.subheadline)
                .foregroundColor(MenuDetailColors.detail)
                .padding(.top, 4)
            }
        }
        .accessibilityIdentifier("weather-details-disclosure")
    }
}

private struct PrecipitationWindChartView: View {
    let title: String
    let precipitationPoints: [WeatherViewModel.TemperatureChartPoint]
    let windPoints: [WeatherViewModel.TemperatureChartPoint]
    let markers: [WeatherViewModel.TimeMarker]
    let xDomain: ClosedRange<Date>?
    let windDomain: ClosedRange<Double>?
    let windUnitText: String
    let hourLabelText: (Date) -> String
    let timeZoneIdentifier: String?

    @State private var plotFrame: CGRect = .zero

    private let leftAxisTicks = [0, 20, 40, 60, 80, 100]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow
            chartBody
            hourLabelRow
        }
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            legendRow
        }
    }

    private var chartBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("%")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)

                Spacer()

                Text(windUnitText)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 2)

            Chart {
                TemperaturePeriodBackgroundMarks(
                    segments: periodBackgroundSegments,
                    yDomain: 0 ... 100
                )
                TemperatureHourGridMarks(
                    hours: xAxisMarkValues,
                    emphasizedHours: emphasizedHourMarks,
                    yDomain: 0 ... 100
                )

                ForEach(precipitationPoints) { point in
                    BarMark(
                        x: .value("Hour", point.time),
                        y: .value("Precipitation", point.temperature)
                    )
                    .foregroundStyle(Color.red.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    .opacity(0.9)
                }

                ForEach(windPoints) { point in
                    LineMark(
                        x: .value("Hour", point.time),
                        y: .value("Wind", normalizedWindValue(for: point.temperature))
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.blue.opacity(0.9))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))

                    PointMark(
                        x: .value("Hour", point.time),
                        y: .value("Wind", normalizedWindValue(for: point.temperature))
                    )
                    .foregroundStyle(Color.blue.opacity(0.9))
                    .symbolSize(18)
                }

                TemperatureTimeMarkerMarks(
                    markers: markers.filter { $0.kind == .current },
                    yDomain: 0 ... 100
                )
            }
            .overlay(alignment: .topLeading) {
                GeometryReader { geometry in
                    WindAxisOverlay(
                        labels: windAxisOverlayLabels,
                        plotFrame: plotFrame,
                        containerSize: geometry.size
                    )
                }
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .background(Color.primary.opacity(0.04))
                    .overlay {
                        GeometryReader { geometry in
                            TemperaturePeriodWatermarkOverlay(
                                segments: periodBackgroundSegments,
                                xDomain: xDomain,
                                plotWidth: geometry.size.width,
                                plotHeight: geometry.size.height
                            )
                        }
                    }
                    .border(Color.primary.opacity(0.2), width: 1)
                    .clipped()
            }
            .ifLet(xDomain) { chart, domain in
                chart.chartXScale(domain: domain)
            }
            .chartYScale(domain: 0 ... 100)
            .chartBackground { chartProxy in
                GeometryReader { geometry in
                    let frame = geometry[chartProxy.plotAreaFrame]

                    Color.clear
                        .onAppear {
                            plotFrame = frame
                        }
                        .onChange(of: frame) { newFrame in
                            plotFrame = newFrame
                        }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: leftAxisTicks) { value in
                    AxisGridLine()
                        .foregroundStyle(Color.primary.opacity(0.14))
                    AxisTick()
                    AxisValueLabel {
                        if let amount = axisValue(from: value) {
                            Text("\(amount)")
                                .font(.system(size: 9))
                        }
                    }
                }
            }
            .frame(height: 44)
        }
    }

    private var legendRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                Text("Precipitation")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
                Text("Wind")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
    }

    private var hourLabelRow: some View {
        GeometryReader { geometry in
            let fallbackLeftInset: CGFloat = 22
            let leftInset = plotFrame == .zero ? fallbackLeftInset : plotFrame.minX
            let usableWidth = plotFrame == .zero ? max(0, geometry.size.width - fallbackLeftInset - 4) : plotFrame.width

            ZStack(alignment: .topLeading) {
                ForEach(Array(xAxisMarkValues.enumerated()), id: \.offset) { _, date in
                    let label = hourLabelText(date)

                    Text(label)
                        .font(.system(size: label == "Noon" || label == "Midnight" ? 7.5 : 8))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(x: leftInset + usableWidth * (xPosition(for: date) ?? 0.5), y: 4)
                }
            }
        }
        .frame(height: 9)
    }

    private var xAxisMarkValues: [Date] {
        guard let xDomain else {
            return []
        }

        let calendar = chartCalendar
        var marks: [Date] = []
        var current = xDomain.lowerBound

        while current <= xDomain.upperBound {
            marks.append(current)
            guard let next = calendar.date(byAdding: .hour, value: 3, to: current) else {
                break
            }
            current = next
        }

        return marks
    }

    private var emphasizedHourMarks: Set<Date> {
        Set(
            xAxisMarkValues.filter { date in
                let hour = chartCalendar.component(.hour, from: date)
                let minute = chartCalendar.component(.minute, from: date)
                let second = chartCalendar.component(.second, from: date)
                return minute == 0 && second == 0 && (hour == 0 || hour == 12)
            }
        )
    }

    private var periodBackgroundSegments: [TemperaturePeriodBackgroundSegment] {
        guard let xDomain else {
            return []
        }

        var segments: [TemperaturePeriodBackgroundSegment] = []
        var currentStart = xDomain.lowerBound

        while currentStart < xDomain.upperBound {
            let hour = chartCalendar.component(.hour, from: currentStart)
            let nextBoundaryHour = hour < 12 ? 12 : 24

            let nextBoundary = nextBoundaryHour == 24
                ? (chartCalendar.date(byAdding: .day, value: 1, to: chartCalendar.startOfDay(for: currentStart)) ?? xDomain.upperBound)
                : (chartCalendar.date(bySettingHour: 12, minute: 0, second: 0, of: currentStart) ?? xDomain.upperBound)

            let segmentEnd = min(nextBoundary, xDomain.upperBound)
            if currentStart < segmentEnd {
                segments.append(
                    TemperaturePeriodBackgroundSegment(
                        start: currentStart,
                        end: segmentEnd,
                        isAM: hour < 12
                    )
                )
            }

            currentStart = segmentEnd
        }

        return segments
    }

    private func normalizedWindValue(for windValue: Int) -> Double {
        guard let windScale = readableWindScale else {
            return 0
        }

        let range = windScale.upperBound - windScale.lowerBound
        guard range > 0 else {
            return 50
        }

        return ((Double(windValue) - windScale.lowerBound) / range) * 100
    }

    private func xPosition(for date: Date) -> CGFloat? {
        guard let xDomain else {
            return nil
        }

        let total = xDomain.upperBound.timeIntervalSince(xDomain.lowerBound)
        guard total > 0 else {
            return nil
        }

        let offset = date.timeIntervalSince(xDomain.lowerBound)
        return min(max(CGFloat(offset / total), 0), 1)
    }

    private func axisValue(from value: AxisValue) -> Int? {
        if let amount = value.as(Int.self) {
            return amount
        }

        if let amount = value.as(Double.self) {
            return Int(amount.rounded())
        }

        return nil
    }

    private func windAxisLabel(for precipitationScaleValue: Int) -> String {
        guard let windScale = readableWindScale else {
            return "--"
        }

        let fraction = Double(precipitationScaleValue) / 100
        let windValue = windScale.lowerBound + ((windScale.upperBound - windScale.lowerBound) * fraction)
        return String(Int(windValue.rounded()))
    }

    private var windAxisOverlayLabels: [(text: String, fraction: CGFloat)] {
        guard let windScale = readableWindScale else {
            return leftAxisTicks.map { tick in
                (text: windAxisLabel(for: tick), fraction: CGFloat(Double(tick) / 100))
            }
        }

        return windScale.ticks.map { tick in
            let fraction = (Double(tick) - windScale.lowerBound) / (windScale.upperBound - windScale.lowerBound)
            return (text: String(tick), fraction: CGFloat(fraction))
        }
    }

    private var readableWindScale: ReadableWindScale? {
        let values = windPoints.map(\.temperature)
        guard !values.isEmpty else {
            return nil
        }

        let maximum = Double(values.max() ?? 0)
        let step = niceWindStep(for: maximum / 5)
        let upperBound = max(step * 5, step)
        let ticks = stride(from: 0.0, through: upperBound, by: step).map { Int($0.rounded()) }

        return ReadableWindScale(
            lowerBound: 0,
            upperBound: upperBound,
            ticks: ticks
        )
    }

    private func niceWindStep(for rawStep: Double) -> Double {
        let preferredSteps: [Double] = [
            1, 2, 3, 4, 5, 6, 8,
            10, 12, 15, 20, 25, 30,
            40, 50, 60, 80, 100
        ]

        let minimumStep = max(rawStep, 1)
        return preferredSteps.first(where: { $0 >= minimumStep }) ?? ceil(minimumStep / 10) * 10
    }

    private var chartCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if let timeZoneIdentifier,
           let timeZone = TimeZone(identifier: timeZoneIdentifier) {
            calendar.timeZone = timeZone
        }
        return calendar
    }
}

private struct ReadableWindScale {
    let lowerBound: Double
    let upperBound: Double
    let ticks: [Int]
}

private struct WindAxisOverlay: View {
    let labels: [(text: String, fraction: CGFloat)]
    let plotFrame: CGRect
    let containerSize: CGSize

    var body: some View {
        if plotFrame != .zero, containerSize != .zero {
            ZStack(alignment: .topLeading) {
                ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                    Text(label.text)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(
                            x: max(plotFrame.minX + 8, plotFrame.maxX - 10),
                            y: plotFrame.maxY - (plotFrame.height * label.fraction)
                        )
                }
            }
            .allowsHitTesting(false)
        }
    }
}

private struct NextTenDayForecastCardView: View {
    let forecasts: [WeatherViewModel.DailyForecastChartPoint]
    let temperatureText: (Int?) -> String
    let dateText: (Date) -> String

    var body: some View {
        WeatherCard(title: "Next 5 Days") {
            HStack(alignment: .top, spacing: 2) {
                ForEach(forecasts) { forecast in
                    forecastTile(for: forecast)
                }
            }
        }
    }

    private func forecastTile(for forecast: WeatherViewModel.DailyForecastChartPoint) -> some View {
        VStack(spacing: 3) {
            Text(dateText(forecast.date))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                Text(temperatureText(forecast.highTemperature))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.red)
                Text("/")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text(temperatureText(forecast.lowTemperature))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.blue)
            }

            Image(systemName: forecast.condition.iconName(isDaylight: true))
                .font(.system(size: 16))
                .foregroundStyle(.orange)
                .frame(height: 18)

            HStack(spacing: 2) {
                Image(systemName: "umbrella.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.red)
                Text("\(forecast.precipitationProbability)%")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.vertical, 2)
    }
}

private struct TemperatureTrendChartContentView: View {
    let model: TemperatureTrendCardModel
    private let hourMarkOffsets = [0, 3, 6, 9, 12, 15, 18, 21, 24]
    @State private var plotFrame: CGRect = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            topMarkerRow

            Chart {
                TemperaturePeriodBackgroundMarks(
                    segments: periodBackgroundSegments,
                    yDomain: model.yDomain
                )
                TemperatureHourGridMarks(
                    hours: xAxisMarkValues,
                    emphasizedHours: emphasizedHourMarks,
                    yDomain: model.yDomain
                )
                TemperatureLineMarks(
                    points: model.points,
                    high: model.high,
                    highAt: model.highAt,
                    low: model.low,
                    lowAt: model.lowAt,
                    valueText: model.valueText
                )
                TemperatureTimeMarkerMarks(
                    markers: model.markers,
                    yDomain: model.yDomain
                )
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .background(Color.primary.opacity(0.04))
                    .overlay {
                        GeometryReader { geometry in
                            TemperaturePeriodWatermarkOverlay(
                                segments: periodBackgroundSegments,
                                xDomain: model.xDomain,
                                plotWidth: geometry.size.width,
                                plotHeight: geometry.size.height
                            )
                        }
                    }
                    .border(Color.primary.opacity(0.2), width: 1)
                    .clipped()
            }
            .ifLet(model.xDomain) { chart, domain in
                chart.chartXScale(domain: domain)
            }
            .ifLet(model.yDomain) { chart, domain in
                chart.chartYScale(domain: domain)
            }
            .chartBackground { chartProxy in
                GeometryReader { geometry in
                    let frame = geometry[chartProxy.plotAreaFrame]

                    Color.clear
                        .onAppear {
                            plotFrame = frame
                        }
                        .onChange(of: frame) { newFrame in
                            plotFrame = newFrame
                        }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                        .foregroundStyle(Color.primary.opacity(0.14))
                    AxisTick()
                    AxisValueLabel {
                        if let temperature = axisTemperature(from: value) {
                            Text(model.valueText(temperature))
                                .font(.system(size: 9))
                        }
                    }
                }
            }
            .frame(height: 44)

            hourLabelRow
        }
    }

    private var topMarkerRow: some View {
        GeometryReader { geometry in
            let fallbackLeftInset: CGFloat = 22
            let leftInset = plotFrame == .zero ? fallbackLeftInset : plotFrame.minX
            let usableWidth = plotFrame == .zero ? max(0, geometry.size.width - fallbackLeftInset - 4) : plotFrame.width

            ZStack(alignment: .topLeading) {
                ForEach(model.markers.filter { $0.kind != .current }) { marker in
                    if let xPosition = xPosition(for: marker.time) {
                        HStack(spacing: 3) {
                            Image(systemName: marker.kind == .sunrise ? "sunrise" : "sunset.fill")
                                .font(.system(size: 8, weight: .semibold))
                            Text(model.markerTimeText(marker.time))
                                .font(.caption2)
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(markerLabelColor(for: marker).opacity(0.22))
                        )
                        .overlay(
                            Capsule()
                                .stroke(markerLabelColor(for: marker).opacity(0.55), lineWidth: 1)
                        )
                        .help(model.markerLabelText(marker))
                        .fixedSize()
                        .position(x: leftInset + usableWidth * xPosition, y: 6)
                    }
                }
            }
        }
        .frame(height: 12)
    }

    private var xAxisMarkValues: [Date] {
        guard let xDomain = model.xDomain else {
            return []
        }

        let calendar = chartCalendar
        let start = xDomain.lowerBound
        let end = xDomain.upperBound

        if isFullDayDomain,
           calendar.component(.minute, from: start) == 0,
           calendar.component(.second, from: start) == 0 {
            return hourMarkOffsets.compactMap { hourOffset in
                if hourOffset == 24 {
                    return xDomain.upperBound
                }

                return calendar.date(byAdding: .hour, value: hourOffset, to: start)
            }
        }

        var firstComponents = calendar.dateComponents([.year, .month, .day, .hour], from: start)
        let roundedHour = ((firstComponents.hour ?? 0) / 3) * 3
        firstComponents.hour = roundedHour
        firstComponents.minute = 0
        firstComponents.second = 0

        guard var current = calendar.date(from: firstComponents) else {
            return []
        }

        if current < start {
            current = calendar.date(byAdding: .hour, value: 3, to: current) ?? current
        }

        var marks: [Date] = []
        while current <= end {
            marks.append(current)
            guard let next = calendar.date(byAdding: .hour, value: 3, to: current) else {
                break
            }
            current = next
        }

        return marks
    }

    private var hourLabelRow: some View {
        GeometryReader { geometry in
            let fallbackLeftInset: CGFloat = 22
            let leftInset = plotFrame == .zero ? fallbackLeftInset : plotFrame.minX
            let usableWidth = plotFrame == .zero ? max(0, geometry.size.width - fallbackLeftInset - 4) : plotFrame.width

            ZStack(alignment: .topLeading) {
                ForEach(Array(xAxisMarkValues.enumerated()), id: \.offset) { index, date in
                    let label = model.hourLabelText(date)

                    Text(label)
                        .font(.system(size: label == "Noon" || label == "Midnight" ? 7.5 : 8))
                        .foregroundStyle(labelOpacity(for: index) == 0 ? .clear : .secondary)
                        .opacity(labelOpacity(for: index))
                        .fixedSize()
                        .position(x: leftInset + usableWidth * (xPosition(for: date) ?? 0.5), y: 4)
                }
            }
        }
        .frame(height: 9)
    }

    private func xPosition(for date: Date) -> CGFloat? {
        guard let xDomain = model.xDomain else {
            return nil
        }

        let total = xDomain.upperBound.timeIntervalSince(xDomain.lowerBound)
        guard total > 0 else {
            return nil
        }

        let offset = date.timeIntervalSince(xDomain.lowerBound)
        return min(max(CGFloat(offset / total), 0), 1)
    }

    private func labelOpacity(for index: Int) -> Double {
        guard !xAxisMarkValues.isEmpty else {
            return 1
        }

        return 1
    }

    private func axisTemperature(from value: AxisValue) -> Int? {
        if let temperature = value.as(Int.self) {
            return temperature
        }

        if let temperature = value.as(Double.self) {
            return Int(temperature.rounded())
        }

        return nil
    }

    private func markerColor(for marker: WeatherViewModel.TimeMarker) -> Color {
        switch marker.kind {
        case .sunrise:
            return Color.yellow.opacity(0.75)
        case .current:
            return Color.red.opacity(0.7)
        case .sunset:
            return Color.indigo.opacity(0.55)
        }
    }

    private func markerLabelColor(for marker: WeatherViewModel.TimeMarker) -> Color {
        switch marker.kind {
        case .sunrise:
            return Color.indigo.opacity(0.55)
        case .current:
            return Color.red.opacity(0.7)
        case .sunset:
            return Color.yellow.opacity(0.75)
        }
    }

    private var chartCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if let timeZoneIdentifier = model.timeZoneIdentifier,
           let timeZone = TimeZone(identifier: timeZoneIdentifier) {
            calendar.timeZone = timeZone
        }
        return calendar
    }

    private var isFullDayDomain: Bool {
        guard let xDomain = model.xDomain else {
            return false
        }

        let start = xDomain.lowerBound
        let end = xDomain.upperBound
        return chartCalendar.component(.hour, from: start) == 0 &&
            chartCalendar.component(.minute, from: start) == 0 &&
            chartCalendar.component(.second, from: start) == 0 &&
            chartCalendar.component(.hour, from: end) == 0 &&
            chartCalendar.component(.minute, from: end) == 0 &&
            chartCalendar.component(.second, from: end) == 0
    }

    private var emphasizedHourMarks: Set<Date> {
        Set(
            xAxisMarkValues.filter { date in
                let hour = chartCalendar.component(.hour, from: date)
                let minute = chartCalendar.component(.minute, from: date)
                let second = chartCalendar.component(.second, from: date)
                return minute == 0 && second == 0 && (hour == 0 || hour == 12)
            }
        )
    }

    private var periodBackgroundSegments: [TemperaturePeriodBackgroundSegment] {
        guard let xDomain = model.xDomain else {
            return []
        }

        var segments: [TemperaturePeriodBackgroundSegment] = []
        var currentStart = xDomain.lowerBound

        while currentStart < xDomain.upperBound {
            let hour = chartCalendar.component(.hour, from: currentStart)
            let nextBoundaryHour = hour < 12 ? 12 : 24

            let nextBoundary = nextBoundaryHour == 24
                ? (chartCalendar.date(byAdding: .day, value: 1, to: chartCalendar.startOfDay(for: currentStart)) ?? xDomain.upperBound)
                : (chartCalendar.date(bySettingHour: 12, minute: 0, second: 0, of: currentStart) ?? xDomain.upperBound)

            let segmentEnd = min(nextBoundary, xDomain.upperBound)
            if currentStart < segmentEnd {
                segments.append(
                    TemperaturePeriodBackgroundSegment(
                        start: currentStart,
                        end: segmentEnd,
                        isAM: hour < 12
                    )
                )
            }

            currentStart = segmentEnd
        }

        return segments
    }
}

private struct TemperaturePeriodBackgroundSegment: Identifiable {
    let start: Date
    let end: Date
    let isAM: Bool

    var id: String {
        "\(start.timeIntervalSinceReferenceDate)-\(end.timeIntervalSinceReferenceDate)-\(isAM)"
    }

    var midpoint: Date {
        Date(timeIntervalSinceReferenceDate: (start.timeIntervalSinceReferenceDate + end.timeIntervalSinceReferenceDate) / 2)
    }

    func watermarkY(in yDomain: ClosedRange<Double>) -> Double {
        yDomain.lowerBound + ((yDomain.upperBound - yDomain.lowerBound) * 0.5)
    }
}

private struct TemperaturePeriodBackgroundMarks: ChartContent {
    let segments: [TemperaturePeriodBackgroundSegment]
    let yDomain: ClosedRange<Double>?

    var body: some ChartContent {
        if let yDomain {
            ForEach(segments) { segment in
                RectangleMark(
                    xStart: .value(segment.isAM ? "AM Start" : "PM Start", segment.start),
                    xEnd: .value(segment.isAM ? "AM End" : "PM End", segment.end),
                    yStart: .value("Background Min", yDomain.lowerBound),
                    yEnd: .value("Background Max", yDomain.upperBound)
                )
                .foregroundStyle(segment.isAM ? Color.blue.opacity(0.06) : Color.orange.opacity(0.06))
            }
        }
    }
}

private struct TemperaturePeriodWatermarkOverlay: View {
    let segments: [TemperaturePeriodBackgroundSegment]
    let xDomain: ClosedRange<Date>?
    let plotWidth: CGFloat
    let plotHeight: CGFloat

    var body: some View {
        if let xDomain, plotWidth > 0, plotHeight > 0 {
            ZStack(alignment: .topLeading) {
                ForEach(segments) { segment in
                    Text(segment.isAM ? "AM" : "PM")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.12))
                        .position(
                            x: plotWidth * xPosition(for: segment.midpoint, in: xDomain),
                            y: plotHeight * 0.5
                        )
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func xPosition(for date: Date, in xDomain: ClosedRange<Date>) -> CGFloat {
        let total = xDomain.upperBound.timeIntervalSince(xDomain.lowerBound)
        guard total > 0 else {
            return 0.5
        }

        let offset = date.timeIntervalSince(xDomain.lowerBound)
        return min(max(CGFloat(offset / total), 0), 1)
    }
}

private struct TemperatureHourGridMarks: ChartContent {
    let hours: [Date]
    let emphasizedHours: Set<Date>
    let yDomain: ClosedRange<Double>?

    var body: some ChartContent {
        if let yDomain {
            ForEach(Array(hours.enumerated()), id: \.offset) { _, hour in
                RuleMark(
                    x: .value("Hour Grid", hour),
                    yStart: .value("Grid Min", yDomain.lowerBound),
                    yEnd: .value("Grid Max", yDomain.upperBound)
                )
                .foregroundStyle(Color.primary.opacity(0.18))
                .lineStyle(StrokeStyle(lineWidth: emphasizedHours.contains(hour) ? 3 : 1))
            }
        }
    }
}

private struct TemperatureLineMarks: ChartContent {
    let points: [WeatherViewModel.TemperatureChartPoint]
    let high: Int?
    let highAt: Date?
    let low: Int?
    let lowAt: Date?
    let valueText: (Int) -> String

    var body: some ChartContent {
        ForEach(points) { point in
            LineMark(
                x: .value("Hour", point.time),
                y: .value("Temperature", point.temperature)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(Color.accentColor)
            .lineStyle(StrokeStyle(lineWidth: 2))

            PointMark(
                x: .value("Hour", point.time),
                y: .value("Temperature", point.temperature)
            )
            .foregroundStyle(markerColor(for: point))
            .symbolSize(markerSize(for: point))
            .annotation(position: .overlay) {
                markerOverlay(for: point)
            }
        }

        if let highLabel = extremaLabel(temperature: high, at: highAt) {
            PointMark(
                x: .value("High Label Hour", highLabel.time),
                y: .value("High Label Temperature", highLabel.temperature)
            )
            .opacity(0.001)
            .annotation(position: .bottom, alignment: highLabel.alignment, spacing: 4) {
                extremaLabelText(highLabel.temperature, color: .orange)
                    .help("Daily high")
            }
        }

        if let lowLabel = extremaLabel(temperature: low, at: lowAt) {
            PointMark(
                x: .value("Low Label Hour", lowLabel.time),
                y: .value("Low Label Temperature", lowLabel.temperature)
            )
            .opacity(0.001)
            .annotation(position: .top, alignment: lowLabel.alignment, spacing: 4) {
                extremaLabelText(lowLabel.temperature, color: .cyan)
                    .help("Daily low")
            }
        }
    }

    private func markerColor(
        for point: WeatherViewModel.TemperatureChartPoint
    ) -> Color {
        if isHighPoint(point) {
            return .orange
        }

        if isLowPoint(point) {
            return .cyan
        }

        return .accentColor
    }

    @ViewBuilder
    private func markerOverlay(
        for point: WeatherViewModel.TemperatureChartPoint
    ) -> some View {
        if isHighPoint(point) {
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 8))
                .foregroundStyle(.orange)
        }

        if isLowPoint(point) {
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 8))
                .foregroundStyle(.cyan)
        }
    }

    private func markerSize(
        for point: WeatherViewModel.TemperatureChartPoint
    ) -> CGFloat {
        if isHighPoint(point) || isLowPoint(point) {
            return 40
        }

        return 14
    }

    private func extremaLabel(temperature: Int?, at time: Date?) -> (time: Date, temperature: Int, alignment: Alignment)? {
        guard
            let temperature,
            let time,
            let index = points.firstIndex(where: { $0.time == time })
        else {
            return nil
        }

        return (
            time,
            temperature,
            TemperatureChartLabelAlignmentResolver.alignment(
                forRunStartingAt: index,
                endingAt: index,
                pointCount: points.count
            )
        )
    }

    private func isHighPoint(_ point: WeatherViewModel.TemperatureChartPoint) -> Bool {
        point.time == highAt && point.temperature == high
    }

    private func isLowPoint(_ point: WeatherViewModel.TemperatureChartPoint) -> Bool {
        point.time == lowAt && point.temperature == low
    }

    private func extremaLabelText(_ temperature: Int, color: Color) -> some View {
        Text(valueText(temperature))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(color.opacity(0.2))
            )
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.55), lineWidth: 1)
            )
    }

}

private struct TemperatureTimeMarkerMarks: ChartContent {
    let markers: [WeatherViewModel.TimeMarker]
    let yDomain: ClosedRange<Double>?

    var body: some ChartContent {
        if let yDomain {
            ForEach(markers) { marker in
                switch marker.kind {
                case .current:
                    RuleMark(
                        x: .value("Marker", marker.time),
                        yStart: .value("Marker Min", yDomain.lowerBound),
                        yEnd: .value("Marker Max", yDomain.upperBound)
                    )
                    .foregroundStyle(markerColor(for: marker))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                case .sunrise, .sunset:
                    PointMark(
                        x: .value("Marker", marker.time),
                        y: .value("Marker Top", yDomain.upperBound)
                    )
                    .symbol {
                        Image(systemName: "arrowshape.down.fill")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .symbolSize(30)
                    .foregroundStyle(markerColor(for: marker))
                }
            }
        }
    }

    private func markerColor(for marker: WeatherViewModel.TimeMarker) -> Color {
        switch marker.kind {
        case .sunrise:
            return Color.yellow.opacity(0.45)
        case .current:
            return Color.red.opacity(0.55)
        case .sunset:
            return Color.indigo.opacity(0.35)
        }
    }
}

private extension View {
    @ViewBuilder
    func ifLet<Value, Content: View>(_ value: Value?, transform: (Self, Value) -> Content) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}

private struct AddLocationEditorView: View {
    @Binding var mode: AddLocationMode
    @Binding var locationName: String
    @Binding var latitudeText: String
    @Binding var longitudeText: String
    @Binding var searchQuery: String
    let detectedLocation: SavedLocation?
    let searchedLocation: SavedLocation?
    let isDetectingLocation: Bool
    let isSearchingLocation: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onManualSave: () -> Void
    let onDetect: () -> Void
    let onDetectedSave: () -> Void
    let onSearch: () -> Void
    let onSearchedSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Add Location Mode", selection: $mode) {
                ForEach(AddLocationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityIdentifier("add-location-mode-picker")

            Group {
                switch mode {
                case .manual:
                    manualContent
                case .detect:
                    detectContent
                case .search:
                    searchContent
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("add-location-error-text")
            }

            HStack(spacing: 8) {
                Spacer()

                Button("Cancel", action: onCancel)
                    .controlSize(.small)
                    .accessibilityIdentifier("add-location-cancel-button")

                switch mode {
                case .manual:
                    Button("Save", action: onManualSave)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityIdentifier("add-location-save-button")
                case .detect:
                    Button("Use Detected", action: onDetectedSave)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(detectedLocation == nil || isDetectingLocation)
                        .accessibilityIdentifier("add-detected-location-button")
                case .search:
                    Button("Use Search Result", action: onSearchedSave)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(searchedLocation == nil || isSearchingLocation)
                        .accessibilityIdentifier("add-searched-location-button")
                }
            }
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private var manualContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Location name", text: $locationName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("add-location-name-field")

            TextField("Latitude", text: $latitudeText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("add-location-latitude-field")

            TextField("Longitude", text: $longitudeText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("add-location-longitude-field")
        }
    }

    private var detectContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onDetect) {
                HStack(spacing: 8) {
                    if isDetectingLocation {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "location.fill")
                    }
                    Text(isDetectingLocation ? "Detecting..." : "Detect Current Location")
                    Spacer()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isDetectingLocation)
            .accessibilityIdentifier("detect-current-location-button")

            Group {
                if let detectedLocation {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(detectedLocation.name)
                            .font(.subheadline.weight(.medium))
                            .accessibilityIdentifier("detected-location-name")
                        Text(String(format: "%.4f, %.4f", detectedLocation.latitude, detectedLocation.longitude))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("detected-location-coordinates")
                    }
                } else {
                    Text("Use your Mac's current location to fill this slot automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var searchContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("ZIP code or city name", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("search-location-query-field")

            Button(action: onSearch) {
                HStack(spacing: 8) {
                    if isSearchingLocation {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                    Text(isSearchingLocation ? "Searching..." : "Search")
                    Spacer()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isSearchingLocation)
            .accessibilityIdentifier("search-location-button")

            Group {
                if let searchedLocation {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(searchedLocation.name)
                            .font(.subheadline.weight(.medium))
                            .accessibilityIdentifier("searched-location-name")
                        Text(String(format: "%.4f, %.4f", searchedLocation.latitude, searchedLocation.longitude))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("searched-location-coordinates")
                    }
                } else {
                    Text("Search by ZIP code or city name and save the best match into this slot.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct MenuContentView: View {
    @ObservedObject var viewModel: WeatherViewModel
    let onRefresh: () -> Void
    let onQuit: () -> Void

    @State private var isShowingLocationOptions = false
    @State private var editingLocationSlotIndex: Int?
    @State private var addLocationMode: AddLocationMode = .search
    @State private var draftLocationName = ""
    @State private var draftLatitude = ""
    @State private var draftLongitude = ""
    @State private var searchQuery = ""
    @State private var detectedLocation: SavedLocation?
    @State private var searchedLocation: SavedLocation?
    @State private var isDetectingLocation = false
    @State private var isSearchingLocation = false
    @State private var addLocationError: String?
    @State private var isShowingWeatherDetails = false
    @State private var selectedTemperatureChartTab: TemperatureTrendCardTab = .next24Hours

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Button(action: toggleLocationOptions) {
                    HStack(spacing: 8) {
                        Text(viewModel.locationName)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Spacer()

                        Image(systemName: isShowingLocationOptions ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                )
                .accessibilityIdentifier("location-picker-button")

                if isShowingLocationOptions {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.alternateLocationSlots) { slot in
                            HStack(spacing: 8) {
                                Button(action: {
                                    handleLocationSlotTap(slot)
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: slot.isEmpty ? "plus.circle" : "mappin.and.ellipse")
                                            .foregroundStyle(slot.isEmpty ? .secondary : .primary)
                                        Text(slot.title)
                                            .foregroundStyle(slot.isEmpty ? .secondary : .primary)
                                        Spacer()
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("location-slot-\(slot.index)")

                                if !slot.isEmpty && viewModel.canDeleteLocation(at: slot.index) {
                                    Button(role: .destructive, action: {
                                        viewModel.deleteLocation(at: slot.index)
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Delete location")
                                    .accessibilityIdentifier("delete-location-slot-\(slot.index)")
                                }
                            }
                        }

                        if editingLocationSlotIndex != nil {
                            AddLocationEditorView(
                                mode: $addLocationMode,
                                locationName: $draftLocationName,
                                latitudeText: $draftLatitude,
                                longitudeText: $draftLongitude,
                                searchQuery: $searchQuery,
                                detectedLocation: detectedLocation,
                                searchedLocation: searchedLocation,
                                isDetectingLocation: isDetectingLocation,
                                isSearchingLocation: isSearchingLocation,
                                errorMessage: addLocationError,
                                onCancel: dismissAddLocationEditor,
                                onManualSave: submitManualLocation,
                                onDetect: detectCurrentLocation,
                                onDetectedSave: submitDetectedLocation,
                                onSearch: searchForLocation,
                                onSearchedSave: submitSearchedLocation
                            )
                            .accessibilityIdentifier("add-location-editor")
                        }
                    }
                    .padding(.leading, 2)
                }
            }

            Text(viewModel.summaryText)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("weather-summary-text")

            Group {
                if viewModel.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading")
                    }
                } else {
                    HStack(spacing: 10) {
                        Label(viewModel.temperatureText, systemImage: viewModel.conditionIconName)

                        Divider()
                            .frame(height: 18)

                        HStack(spacing: 3) {
                            Image(systemName: "wind")
                            Text(viewModel.windInlineText)
                        }
                        .foregroundStyle(.secondary)
                        .help("Wind")

                        HStack(spacing: 3) {
                            Image(systemName: "umbrella.fill")
                            Text(viewModel.precipitationInlineText)
                        }
                        .foregroundStyle(.secondary)
                        .help("Precipitation")

                        HStack(spacing: 3) {
                            Image(systemName: "humidity.fill")
                            Text(viewModel.humidityInlineText)
                        }
                        .foregroundStyle(.secondary)
                        .help("Humidity")
                    }
                }
            }
            .accessibilityIdentifier("temperature-label")

            if !viewModel.temperatureChartPoints.isEmpty {
                Divider()

                TemperatureTrendCardView(
                    isShowingDetails: $isShowingWeatherDetails,
                    selectedTab: $selectedTemperatureChartTab,
                    todayModel: TemperatureTrendCardModel(
                        title: "Today's Temperatures",
                        points: viewModel.temperatureChartPoints,
                        high: viewModel.temperatureChartHigh,
                        highAt: viewModel.temperatureChartHighAt,
                        low: viewModel.temperatureChartLow,
                        lowAt: viewModel.temperatureChartLowAt,
                        markers: viewModel.temperatureChartTimeMarkers,
                        xDomain: viewModel.temperatureChartXDomain,
                        yDomain: viewModel.temperatureChartYDomain,
                        valueText: viewModel.temperatureChartValueText(_:),
                        markerLabelText: viewModel.temperatureChartMarkerLabel(for:),
                        markerTimeText: viewModel.temperatureChartTimeText(_:),
                        hourLabelText: viewModel.temperatureChartHourLabelText(_:),
                        timeZoneIdentifier: viewModel.chartTimeZoneIdentifier,
                        details: TemperatureTrendDetailsModel(
                            highDetailText: viewModel.highDetailText,
                            lowDetailText: viewModel.lowDetailText,
                            sunriseText: viewModel.sunriseText,
                            sunsetText: viewModel.sunsetText
                        )
                    ),
                    next24HourModel: viewModel.next24HourTemperatureChartPoints.isEmpty ? nil : TemperatureTrendCardModel(
                        title: "Next 24 Hours",
                        points: viewModel.next24HourTemperatureChartPoints,
                        high: viewModel.next24HourTemperatureChartHigh,
                        highAt: viewModel.next24HourTemperatureChartHighAt,
                        low: viewModel.next24HourTemperatureChartLow,
                        lowAt: viewModel.next24HourTemperatureChartLowAt,
                        markers: viewModel.next24HourTemperatureChartTimeMarkers,
                        xDomain: viewModel.next24HourTemperatureChartXDomain,
                        yDomain: viewModel.next24HourTemperatureChartYDomain,
                        valueText: viewModel.temperatureChartValueText(_:),
                        markerLabelText: viewModel.temperatureChartMarkerLabel(for:),
                        markerTimeText: viewModel.temperatureChartTimeText(_:),
                        hourLabelText: viewModel.temperatureChartHourLabelText(_:),
                        timeZoneIdentifier: viewModel.chartTimeZoneIdentifier,
                        details: TemperatureTrendDetailsModel(
                            highDetailText: viewModel.next24HourHighDetailText,
                            lowDetailText: viewModel.next24HourLowDetailText,
                            sunriseText: viewModel.next24HourSunriseText,
                            sunsetText: viewModel.next24HourSunsetText
                        )
                    )
                )
                    .id("temperature-card-\(selectedTemperatureChartTab.rawValue)-\(viewModel.temperatureUnit)")
                    .accessibilityIdentifier("temperature-trend-chart")
            }

            if !viewModel.next24HourPrecipitationChartPoints.isEmpty && !viewModel.next24HourWindChartPoints.isEmpty {
                WeatherCard(title: "") {
                    PrecipitationWindChartView(
                        title: "Next 24 Hours",
                        precipitationPoints: viewModel.next24HourPrecipitationChartPoints,
                        windPoints: viewModel.next24HourWindChartPoints,
                        markers: viewModel.next24HourWindChartTimeMarkers,
                        xDomain: viewModel.next24HourWindChartXDomain,
                        windDomain: viewModel.next24HourWindChartYDomain,
                        windUnitText: viewModel.windChartUnitText,
                        hourLabelText: viewModel.temperatureChartHourLabelText(_:),
                        timeZoneIdentifier: viewModel.chartTimeZoneIdentifier
                    )
                }
                .id("secondary-card-\(viewModel.temperatureUnit)")
                .accessibilityIdentifier("secondary-trend-chart")
            }

            if !viewModel.next10DayForecastChartPoints.isEmpty {
                NextTenDayForecastCardView(
                    forecasts: viewModel.next10DayForecastChartPoints,
                    temperatureText: viewModel.temperatureChartValueText(_:),
                    dateText: viewModel.next10DayLabelText(_:)
                )
                .id("ten-day-card-\(viewModel.temperatureUnit)")
                .accessibilityIdentifier("ten-day-forecast-chart")
            }

            Divider()

            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 8) {
                    Text(viewModel.lastCheckText)
                        .font(.caption)
                        .foregroundColor(MenuDetailColors.meta)
                        .accessibilityIdentifier("last-check-text")

                    Spacer()

                    Button(action: onRefresh) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!viewModel.isRefreshButtonEnabled(at: context.date))
                    .help(viewModel.refreshButtonHelpText(at: context.date))
                    .accessibilityIdentifier("refresh-button")
                }
            }

            Divider()

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Button(action: onQuit) {
                        HStack(spacing: 8) {
                            Text("Quit")
                            Text("⌘Q")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .keyboardShortcut("q")
                    .accessibilityIdentifier("quit-button")
                }

                Divider()
                    .frame(height: 24)

                HStack(spacing: 8) {
                    Button(action: viewModel.toggleLaunchAtLogin) {
                        Label(viewModel.launchAtLoginButtonText, systemImage: viewModel.isLaunchAtLoginEnabled ? "checkmark.circle.fill" : "circle")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("launch-at-login-button")

                    Button(action: viewModel.toggleTemperatureUnit) {
                        TemperatureUnitToggleLabel(temperatureUnit: viewModel.temperatureUnit)
                    }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("temperature-unit-button")
                }
            }
        }
        .padding()
        .frame(width: 300)
    }

    private func toggleLocationOptions() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isShowingLocationOptions.toggle()
        }

        if !isShowingLocationOptions {
            dismissAddLocationEditor()
        }
    }

    private func handleLocationSlotTap(_ slot: LocationSlot) {
        if slot.isEmpty {
            draftLocationName = ""
            draftLatitude = ""
            draftLongitude = ""
            searchQuery = ""
            detectedLocation = nil
            searchedLocation = nil
            addLocationMode = .search
            addLocationError = nil
            isDetectingLocation = false
            isSearchingLocation = false
            editingLocationSlotIndex = slot.index
        } else {
            viewModel.selectLocation(at: slot.index)
            isShowingLocationOptions = false
            dismissAddLocationEditor()
        }
    }

    private func dismissAddLocationEditor() {
        editingLocationSlotIndex = nil
        addLocationError = nil
        searchQuery = ""
        detectedLocation = nil
        searchedLocation = nil
        isDetectingLocation = false
        isSearchingLocation = false
        addLocationMode = .search
    }

    private func submitManualLocation() {
        guard let slotIndex = editingLocationSlotIndex else {
            return
        }

        do {
            try viewModel.addLocation(
                at: slotIndex,
                name: draftLocationName,
                latitudeText: draftLatitude,
                longitudeText: draftLongitude
            )
            isShowingLocationOptions = false
            dismissAddLocationEditor()
        } catch let error as LocationInputError {
            addLocationError = error.errorDescription
        } catch {
            addLocationError = "Unable to save location."
        }
    }

    private func detectCurrentLocation() {
        guard !isDetectingLocation else {
            return
        }

        addLocationMode = .detect
        isDetectingLocation = true
        addLocationError = nil
        detectedLocation = nil

        Task {
            do {
                let location = try await viewModel.detectCurrentLocation()
                await MainActor.run {
                    detectedLocation = location
                    isDetectingLocation = false
                }
            } catch let error as LocationInputError {
                await MainActor.run {
                    addLocationError = error.errorDescription
                    isDetectingLocation = false
                }
            } catch {
                await MainActor.run {
                    addLocationError = "Unable to determine your current location."
                    isDetectingLocation = false
                }
            }
        }
    }

    private func searchForLocation() {
        guard !isSearchingLocation else {
            return
        }

        addLocationMode = .search
        isSearchingLocation = true
        addLocationError = nil
        searchedLocation = nil

        Task {
            do {
                let location = try await viewModel.searchLocation(query: searchQuery)
                await MainActor.run {
                    searchedLocation = location
                    isSearchingLocation = false
                }
            } catch let error as LocationInputError {
                await MainActor.run {
                    addLocationError = error.errorDescription
                    isSearchingLocation = false
                }
            } catch {
                await MainActor.run {
                    addLocationError = "Unable to find that location."
                    isSearchingLocation = false
                }
            }
        }
    }

    private func submitSearchedLocation() {
        guard let slotIndex = editingLocationSlotIndex, let searchedLocation else {
            return
        }

        do {
            try viewModel.addDetectedLocation(searchedLocation, at: slotIndex)
            isShowingLocationOptions = false
            dismissAddLocationEditor()
        } catch let error as LocationInputError {
            addLocationError = error.errorDescription
        } catch {
            addLocationError = "Unable to save location."
        }
    }

    private func submitDetectedLocation() {
        guard let slotIndex = editingLocationSlotIndex, let detectedLocation else {
            return
        }

        do {
            try viewModel.addDetectedLocation(detectedLocation, at: slotIndex)
            isShowingLocationOptions = false
            dismissAddLocationEditor()
        } catch let error as LocationInputError {
            addLocationError = error.errorDescription
        } catch {
            addLocationError = "Unable to save location."
        }
    }
}
