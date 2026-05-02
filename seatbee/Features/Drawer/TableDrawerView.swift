import SwiftUI

struct TableDrawerView: View {
    let table: SeatTable
    @State private var selectedTab = "Seats"
    @Environment(\.dismiss) private var dismiss

    private let tabs = ["Seats", "Notes", "Tags"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(table.name)
                    .font(SBFont.displayMedium)
                    .foregroundStyle(Color.sbCharcoal)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.sbWarm)
                        .frame(width: 32, height: 32)
                        .background(Color.sbIvory2)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, SBSpacing.cardPadding)
            .padding(.top, SBSpacing.screenMargin)

            // Action strip
            actionStrip
                .padding(.top, SBSpacing.screenMargin)

            // Tabs
            tabRow
                .padding(.top, SBSpacing.screenMargin)

            // Content
            ScrollView {
                switch selectedTab {
                case "Seats":
                    seatsContent
                case "Notes":
                    notesContent
                case "Tags":
                    tagsContent
                default:
                    EmptyView()
                }
            }
            .padding(.top, SBSpacing.lg)
        }
        .background(Color.sbIvory)
    }

    // MARK: - Action Strip

    private var actionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                actionButton(icon: "pencil", label: "Rename")
                actionButton(icon: "lock", label: "Lock")
                actionButton(icon: "doc.on.doc", label: "Duplicate")
                actionButton(icon: "arrow.triangle.2.circlepath", label: "Rotate")
                actionButton(icon: "trash", label: "Delete")
            }
            .padding(.horizontal, SBSpacing.cardPadding)
        }
    }

    private func actionButton(icon: String, label: String) -> some View {
        Button { HapticEngine.light() } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.sbCharcoal)
                Text(label.uppercased())
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbWarm)
            }
            .frame(width: 64, height: 56)
            .background(Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tabs

    private var tabRow: some View {
        HStack(spacing: 24) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    withAnimation(.seatbee) { selectedTab = tab }
                } label: {
                    VStack(spacing: 6) {
                        Text(tab)
                            .font(SBFont.bodySemibold)
                            .foregroundStyle(selectedTab == tab ? Color.sbCharcoal : Color.sbWarm)
                        Rectangle()
                            .fill(selectedTab == tab ? Color.sbGold : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, SBSpacing.cardPadding)
    }

    // MARK: - Seats Content

    private var seatsContent: some View {
        VStack(spacing: 6) {
            ForEach(0..<table.seats, id: \.self) { index in
                HStack(spacing: 10) {
                    // Drag handle
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sbWarm2)

                    // Seat badge
                    ZStack {
                        Circle()
                            .fill(Color.sbGold)
                            .frame(width: 22, height: 22)
                        Text("\(index + 1)")
                            .font(SBFont.inter(10, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    // Guest name or empty
                    Text("Seat \(index + 1)")
                        .font(SBFont.bodySmall)
                        .foregroundStyle(Color.sbCharcoal)

                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, SBSpacing.cardPadding)
            }

            // Add seat button
            Button { HapticEngine.light() } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("Add seat")
                }
                .font(SBFont.bodySemibold)
                .foregroundStyle(Color.sbGoldDk)
                .frame(maxWidth: .infinity)
                .padding(12)
                .overlay(
                    RoundedRectangle(cornerRadius: SBRadius.button)
                        .strokeBorder(Color.sbLine2, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, SBSpacing.cardPadding)
            .padding(.top, SBSpacing.lg)
        }
    }

    // MARK: - Notes & Tags

    private var notesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No notes yet")
                .font(SBFont.body)
                .foregroundStyle(Color.sbWarm)
                .padding(SBSpacing.cardPadding)
        }
    }

    private var tagsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No tags yet")
                .font(SBFont.body)
                .foregroundStyle(Color.sbWarm)
                .padding(SBSpacing.cardPadding)
        }
    }
}

#Preview {
    TableDrawerView(table: SeatTable(
        id: "1", name: "Table 5", type: .round, seats: 8,
        x: 100, y: 100, assignments: [:]
    ))
}
