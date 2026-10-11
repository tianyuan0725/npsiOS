import SwiftUI
import UIKit

// MARK: - Formatting helpers
func formatBytes(_ n: Int64) -> String {
    guard n > 0 else { return "0 B" }
    let units = ["B", "KB", "MB", "GB", "TB", "PB"]
    var v = Double(n)
    var i = 0
    while v >= 1024 && i < units.count - 1 {
        v /= 1024
        i += 1
    }
    return String(format: "%.1f %@", v, units[i])
}

func formatInt(_ n: Int?) -> String {
    guard let n = n else { return "-" }
    return "\(n)"
}

// MARK: - Status badge
struct StatusBadge: View {
    let isOn: Bool
    let onText: String
    let offText: String

    init(_ isOn: Bool, on: String = "在线", off: String = "离线") {
        self.isOn = isOn
        self.onText = on
        self.offText = off
    }

    var body: some View {
        Text(isOn ? onText : offText)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isOn ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
            .foregroundColor(isOn ? .green : .gray)
            .clipShape(Capsule())
    }
}

// MARK: - Stat card for dashboard
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    var accent: Color = .blue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(accent)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
    }
}

// MARK: - Loading / error overlay
struct LoadingView: View {
    var body: some View {
        ProgressView("加载中…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground).opacity(0.4))
    }
}

// MARK: - Empty state (iOS 16 compatible)
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Reusable labeled text field
struct LabeledField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(10)
        }
    }
}
