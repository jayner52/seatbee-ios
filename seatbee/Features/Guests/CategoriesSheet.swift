import SwiftUI

// MARK: - Categories sheet (web parity)
//
// Web stores categories as a canonical list of `{id, name, color}` on
// the plan (`plan.rawCategories`); each guest's `categories: [String]`
// holds only the IDs. Categories created in the web app get random
// short IDs ("0hyga5jk9") that the user never sees on the web — names
// are looked up from rawCategories before display. This sheet does
// the same lookup so iOS shows real names + the user's chosen colour.
//
// Add / Delete also mutate `rawCategories` (not just per-guest IDs),
// so a category created on iOS round-trips to web with a name + color
// the AI generator and rules can see.

struct CategoriesSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var newCategoryName = ""
    @State private var selectedColor = "#C9A961"

    private let colorPresets = [
        "#C9A961", "#9CAF88", "#D4A5A5", "#8B9DC3",
        "#DDA0DD", "#87CEEB", "#98D8C8", "#FFD700",
        "#F4A460", "#20B2AA", "#778899", "#DB7093",
    ]

    /// Canonical id → {name, color} list, sorted alphabetically by name.
    /// Falls back to the ID as the name when an entry is missing one
    /// (defensive — should never happen on data created via this sheet).
    private var canonicalCategories: [(id: String, name: String, color: String?)] {
        guard let raw = appState.activePlan?.rawCategories else { return [] }
        return raw.compactMap { entry -> (String, String, String?)? in
            guard let id = entry["id"]?.value as? String else { return nil }
            let name = (entry["name"]?.value as? String) ?? id
            let color = entry["color"]?.value as? String
            return (id, name, color)
        }
        .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !canonicalCategories.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CATEGORIES")
                                .font(SBFont.capsLabel)
                                .foregroundStyle(Color.sbWarm)
                                .letterSpacing(1.5)

                            ForEach(canonicalCategories, id: \.id) { cat in
                                categoryRow(id: cat.id, name: cat.name, color: cat.color)
                            }
                        }
                    }

                    Spacer(minLength: 16)
                }
                .padding(.horizontal, SBSpacing.screenMargin)
                .padding(.top, 16)
            }
            .background(Color.sbIvory)
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.sbGoldDk)
                }
            }
            // Sticky Add Category form. Pinned at the bottom so users
            // with long category lists never have to scroll the new-
            // category input off screen to reach it. Same pattern as
            // PartiesSheet's pinned Create CTA.
            .safeAreaInset(edge: .bottom) {
                addCategoryBar
            }
        }
    }

    private var addCategoryBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ADD CATEGORY")
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)

            HStack(spacing: 12) {
                TextField("Category name", text: $newCategoryName)
                    .font(SBFont.body)
                    .padding(12)
                    .background(Color.sbIvory2)
                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
                    .onSubmit { addCategory() }

                Button {
                    addCategory()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.sbGold)
                }
                .buttonStyle(.plain)
                .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Color picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(colorPresets, id: \.self) { color in
                        Circle()
                            .fill(Color(hex: color))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.sbCharcoal, lineWidth: selectedColor == color ? 2 : 0)
                            )
                            .onTapGesture {
                                selectedColor = color
                                HapticEngine.selection()
                            }
                    }
                }
            }
        }
        .padding(.horizontal, SBSpacing.screenMargin)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            // Soft top border + ivory bg so the pinned bar reads as a
            // distinct surface from the scroll content above.
            Color.sbIvory
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.sbLine).frame(height: 1)
                }
        )
    }

    private func categoryRow(id: String, name: String, color: String?) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color.map { Color(hex: $0) } ?? Color.sbGold)
                .frame(width: 12, height: 12)

            Text(name)
                .font(SBFont.body)
                .foregroundStyle(Color.sbCharcoal)
                .lineLimit(1)

            Spacer()

            // Match by canonical ID — works even when name has changed.
            let count = appState.activePlan?.guests.filter {
                $0.categories.contains(id)
            }.count ?? 0
            Text("\(count) guests")
                .font(SBFont.caption)
                .foregroundStyle(Color.sbWarm)

            Button {
                deleteCategory(id: id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.sbWarm2)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.sbIvory2)
        .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
    }

    /// Web parity: pushes a `{id, name, color}` entry into rawCategories
    /// and saves the plan. The previous version did literally nothing
    /// (cleared the field, fired haptic, returned).
    private func addCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, var plan = appState.activePlan else { return }

        // Web uses 9-char base36 IDs (Math.random().toString(36).slice(2,11)).
        // Match that format so iOS-created categories visually match
        // existing web-created ones in any debug surface.
        let id = randomCategoryId()
        let entry: [String: AnyCodable] = [
            "id": AnyCodable(id),
            "name": AnyCodable(name),
            "color": AnyCodable(selectedColor),
        ]
        var raw = plan.rawCategories ?? []
        raw.append(entry)
        plan.rawCategories = raw

        appState.activePlan = plan
        newCategoryName = ""
        HapticEngine.success()
        Task { try? await appState.database.savePlanData(plan: plan) }
    }

    /// Removes the canonical entry AND strips the ID from every guest's
    /// `categories` array so we don't leave dangling references that
    /// would re-appear if `categories` ever fell back to "show all guest
    /// IDs" again.
    private func deleteCategory(id: String) {
        guard var plan = appState.activePlan else { return }
        plan.rawCategories?.removeAll { ($0["id"]?.value as? String) == id }
        for i in plan.guests.indices {
            plan.guests[i].categories.removeAll { $0 == id }
        }
        appState.activePlan = plan
        HapticEngine.medium()
        Task { try? await appState.database.savePlanData(plan: plan) }
    }

    private func randomCategoryId() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<9).compactMap { _ in chars.randomElement() })
    }
}

#Preview {
    CategoriesSheet()
        .environment(AppState())
}
