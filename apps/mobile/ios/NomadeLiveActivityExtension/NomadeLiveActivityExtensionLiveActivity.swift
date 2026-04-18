import ActivityKit
import SwiftUI
import WidgetKit

struct NomadeLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var subtitle: String
        var conversationId: String
        var turnId: String
        var status: String
    }

    var id: String
}

struct NomadeLiveActivityExtensionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NomadeLiveActivityAttributes.self) { context in
            NomadeLiveActivityContentView(
                state: context.state
            )
            .activityBackgroundTint(backgroundTint(for: context.state))
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    liveActivityIcon(for: context.state, size: 28)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(liveActivityTitle(for: context.state))
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                        Text(liveActivitySubtitle(for: context.state))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 6) {
                        LiveActivityStatusBadge(
                            text: statusLabel(for: context.state),
                            accent: accentColor(for: context.state),
                            isCompleted: isCompleted(context.state)
                        )
                        if isCompleted(context.state) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(accentColor(for: context.state))
                        } else {
                            ProgressView()
                                .tint(accentColor(for: context.state))
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        Image(systemName: bottomMessageIcon(for: context.state))
                            .foregroundStyle(accentColor(for: context.state))
                        Text(bottomMessage(for: context.state))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: compactLeadingSymbol(for: context.state))
                    .foregroundStyle(accentColor(for: context.state))
            } compactTrailing: {
                if isCompleted(context.state) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(accentColor(for: context.state))
                } else {
                    ProgressView()
                        .tint(accentColor(for: context.state))
                }
            } minimal: {
                Image(systemName: compactLeadingSymbol(for: context.state))
                    .foregroundStyle(accentColor(for: context.state))
            }
            .keylineTint(accentColor(for: context.state))
        }
    }

    private func liveActivityTitle(
        for state: NomadeLiveActivityAttributes.ContentState
    ) -> String {
        let trimmed = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Nomade" : trimmed
    }

    private func liveActivitySubtitle(
        for state: NomadeLiveActivityAttributes.ContentState
    ) -> String {
        let trimmed = state.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Running request" : trimmed
    }

    private func isCompleted(_ state: NomadeLiveActivityAttributes.ContentState) -> Bool {
        state.status == "completed"
    }

    private func accentColor(for state: NomadeLiveActivityAttributes.ContentState) -> Color {
        isCompleted(state) ? Color.green : Color.blue
    }

    private func backgroundTint(for state: NomadeLiveActivityAttributes.ContentState) -> Color {
        if isCompleted(state) {
            return Color.green.opacity(0.12)
        }
        return Color(uiColor: .secondarySystemBackground)
    }

    private func statusLabel(for state: NomadeLiveActivityAttributes.ContentState) -> String {
        isCompleted(state) ? "Ready" : "Working"
    }

    private func bottomMessage(for state: NomadeLiveActivityAttributes.ContentState) -> String {
        if isCompleted(state) {
            return "Your reply is ready in Nomade."
        }
        return "Nomade is generating your reply."
    }

    private func bottomMessageIcon(for state: NomadeLiveActivityAttributes.ContentState) -> String {
        isCompleted(state) ? "sparkles" : "bolt.fill"
    }

    private func compactLeadingSymbol(for state: NomadeLiveActivityAttributes.ContentState) -> String {
        isCompleted(state) ? "checkmark.bubble.fill" : "ellipsis.message.fill"
    }

    @ViewBuilder
    private func liveActivityIcon(
        for state: NomadeLiveActivityAttributes.ContentState,
        size: CGFloat
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                .fill(accentColor(for: state).opacity(isCompleted(state) ? 0.16 : 0.14))
                .frame(width: size, height: size)
            Image(systemName: isCompleted(state) ? "checkmark.circle.fill" : "ellipsis.message.fill")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(accentColor(for: state))
        }
    }
}

private struct NomadeLiveActivityContentView: View {
    let state: NomadeLiveActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent.opacity(isCompleted ? 0.16 : 0.14))
                    .frame(width: 46, height: 46)
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "ellipsis.message.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    LiveActivityStatusBadge(
                        text: isCompleted ? "Ready" : "Working",
                        accent: accent,
                        isCompleted: isCompleted
                    )
                }

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Image(systemName: isCompleted ? "sparkles" : "bolt.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                    Text(isCompleted ? "Your reply is ready in Nomade." : "Nomade is generating your reply.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var title: String {
        let trimmed = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Nomade" : trimmed
    }

    private var subtitle: String {
        let trimmed = state.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Running request" : trimmed
    }

    private var isCompleted: Bool {
        state.status == "completed"
    }

    private var accent: Color {
        isCompleted ? .green : .blue
    }
}

private struct LiveActivityStatusBadge: View {
    let text: String
    let accent: Color
    let isCompleted: Bool

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(accent.opacity(isCompleted ? 0.14 : 0.1))
            )
    }
}
