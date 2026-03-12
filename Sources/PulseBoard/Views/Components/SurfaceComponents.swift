import SwiftUI

struct AppBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.06, green: 0.08, blue: 0.14),
                Color(red: 0.08, green: 0.10, blue: 0.18),
                Color(red: 0.05, green: 0.06, blue: 0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            RadialGradient(
                colors: [
                    Color(red: 0.28, green: 0.45, blue: 0.96).opacity(0.30),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 540
            )
        )
        .overlay(
            RadialGradient(
                colors: [
                    Color(red: 0.56, green: 0.42, blue: 0.96).opacity(0.18),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 40,
                endRadius: 420
            )
        )
        .ignoresSafeArea()
    }
}

struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .background(.regularMaterial.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08))
            )
            .shadow(color: .black.opacity(0.22), radius: 22, x: 0, y: 14)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let tint: Color
    let systemImage: String

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(title, systemImage: systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Circle()
                        .fill(tint.opacity(0.24))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Image(systemName: systemImage)
                                .foregroundStyle(tint)
                        )
                }
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct StatusBadge: View {
    let status: MonitorStatus

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.symbolName)
                .font(.caption.weight(.bold))
            Text(status.label)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(status.tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(status.tint.opacity(0.14), in: Capsule())
    }
}

struct TagChip: View {
    let title: String
    var isSelected = false

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.24) : Color.white.opacity(0.06), in: Capsule())
            .overlay(
                Capsule().strokeBorder(isSelected ? Color.accentColor.opacity(0.7) : Color.white.opacity(0.08))
            )
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct SparklineView: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(size: proxy.size)
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(
                LinearGradient(colors: [tint.opacity(0.4), tint], startPoint: .leading, endPoint: .trailing),
                style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(height: 38)
    }

    private func normalizedPoints(size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let range = max(maxValue - minValue, 1)

        return values.enumerated().map { index, value in
            let x = size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
            let y = size.height - (CGFloat((value - minValue) / range) * size.height)
            return CGPoint(x: x, y: y)
        }
    }
}

struct AvailabilityStrip: View {
    let checks: [MonitorCheck]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(checks.prefix(24)) { check in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(check.resultingStatus.tint.opacity(0.85))
                    .frame(width: 8, height: 20)
            }
        }
    }
}
