import SwiftUI

// MARK: - Bulk meal & dietary editor for the Guests tab
//
// Why this exists: per-guest meal entry was the slowest part of guest
// list setup. Tap a guest, scroll, type, save, repeat. This sheet
// flattens that into one screen — read all meal/dietary state at a
// glance, edit one or many guests at once.
//
// Schema:
//   - `Guest.meal: String?`           — free-text (web parity, untouched)
//   - `Guest.dietaryTags: [String]?`  — controlled vocab (DietaryTag.all)
//   - `Guest.dietary: String?`        — legacy free-text NOTE; this
//                                       sheet never touches it so any
//                                       existing notes survive bulk ops.
//
// Picker design:
//   - "Popular meals" chips are derived live from the plan's existing
//     meal strings (case-folded for dedup, sorted by descending count).
//     Means no schema change AND a kid's "chicken fingers" appears as a
//     count-1 chip after first use, vanishing if they're removed.
//   - "Custom..." text field handles one-offs and renames.
//   - Dietary chips come from the canonical 8 DietaryTag presets so
//     iOS and web stay in lockstep on what an emoji-mapped tag means.

struct MealsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// Multi-select mode toggle. Off = tapping a row opens its
    /// per-guest picker. On = tapping a row toggles inclusion in the
    /// current selection set, and a bottom Apply bar appears.
    @State private var selectionMode = false
    @State private var selectedGuestIds: Set<String> = []

    /// Single-row picker presentation. When non-nil, a bottom sheet
    /// shows the picker preloaded with that guest's current state.
    @State private var pickerTargetGuestId: String?

    /// Bulk-apply picker presentation. When true, the bottom sheet is
    /// open in "no current state" mode — the user explicitly opts in
    /// to changing meal and/or dietary.
    @State private var bulkPickerOpen = false

    private var plan: SeatingPlan? { appState.activePlan }
    private var guests: [Guest] { plan?.guests ?? [] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SBSpacing.sectionGap) {
                    countsSummary
                    selectionToolbar
                    guestList
                    Spacer(minLength: 80)
                }
                .padding(.horizontal, SBSpacing.screenMargin)
                .padding(.top, SBSpacing.screenMargin)
            }
            .background(Color.sbIvory)
            .navigationTitle("Meals & Dietary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.sbGoldDk)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(selectionMode ? "Cancel" : "Select") {
                        withAnimation(.seatbee) {
                            selectionMode.toggle()
                            if !selectionMode { selectedGuestIds.removeAll() }
                        }
                    }
                    .foregroundStyle(Color.sbCharcoal)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if selectionMode && !selectedGuestIds.isEmpty {
                    bulkActionBar
                }
            }
            .sheet(item: Binding(
                get: { pickerTargetGuestId.map { GuestIdWrapper(id: $0) } },
                set: { pickerTargetGuestId = $0?.id }
            )) { wrapper in
                if let g = guests.first(where: { $0.id == wrapper.id }) {
                    MealPickerSheet(
                        title: g.displayName,
                        initialMeal: g.meal,
                        initialDietaryTags: Set(g.dietaryTags ?? []),
                        popularMeals: popularMeals,
                        mode: .single
                    ) { result in
                        applyToGuest(g.id, result: result)
                        pickerTargetGuestId = nil
                    }
                    .presentationDetents([.medium, .large])
                }
            }
            .sheet(isPresented: $bulkPickerOpen) {
                MealPickerSheet(
                    title: "\(selectedGuestIds.count) selected",
                    initialMeal: nil,
                    initialDietaryTags: [],
                    popularMeals: popularMeals,
                    mode: .bulk
                ) { result in
                    applyBulk(result: result)
                    bulkPickerOpen = false
                    selectionMode = false
                    selectedGuestIds.removeAll()
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Counts summary

    /// Top of the sheet: meal counts on the left, dietary counts on the
    /// right. Read-only "what does my catering look like right now"
    /// glance. Skips meals/diets with zero guests.
    private var countsSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(guests.count) GUESTS")
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbGoldDk)
                    .letterSpacing(1.5)
                Spacer()
                Text("\(unsetCount) without meal")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
            }

            if !mealBreakdown.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MEALS")
                        .font(SBFont.capsLabel)
                        .foregroundStyle(Color.sbWarm)
                        .letterSpacing(1.5)
                    FlowLayout(spacing: 6) {
                        ForEach(mealBreakdown, id: \.label) { item in
                            countChip(label: item.label,
                                      count: item.count,
                                      color: .sbCharcoal)
                        }
                    }
                }
            }

            if !dietaryBreakdown.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DIETARY")
                        .font(SBFont.capsLabel)
                        .foregroundStyle(Color.sbWarm)
                        .letterSpacing(1.5)
                    FlowLayout(spacing: 6) {
                        ForEach(dietaryBreakdown, id: \.id) { item in
                            countChip(label: "\(item.emoji) \(item.label)",
                                      count: item.count,
                                      color: .sbSage)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color.sbIvory2)
        .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
    }

    private func countChip(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(SBFont.caption)
                .foregroundStyle(Color.sbCharcoal)
            Text("\(count)")
                .font(SBFont.bodySmallBold)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white)
        .overlay(
            Capsule().strokeBorder(Color.sbLine, lineWidth: 0.5)
        )
        .clipShape(Capsule())
    }

    // MARK: - Selection toolbar

    @ViewBuilder
    private var selectionToolbar: some View {
        if selectionMode {
            HStack(spacing: 8) {
                Button {
                    if selectedGuestIds.count == guests.count {
                        selectedGuestIds.removeAll()
                    } else {
                        selectedGuestIds = Set(guests.map { $0.id })
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selectedGuestIds.count == guests.count
                              ? "checkmark.square.fill" : "square")
                            .font(.system(size: 14))
                        Text(selectedGuestIds.count == guests.count ? "Deselect all" : "Select all")
                            .font(SBFont.caption)
                    }
                    .foregroundStyle(Color.sbGoldDk)
                }
                Spacer()
                Text("\(selectedGuestIds.count) selected")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Guest list

    private var guestList: some View {
        VStack(spacing: 6) {
            ForEach(guests) { g in
                guestRow(g)
            }
        }
    }

    private func guestRow(_ g: Guest) -> some View {
        let isSelected = selectedGuestIds.contains(g.id)
        return Button {
            if selectionMode {
                if isSelected { selectedGuestIds.remove(g.id) }
                else { selectedGuestIds.insert(g.id) }
                HapticEngine.selection()
            } else {
                pickerTargetGuestId = g.id
            }
        } label: {
            HStack(spacing: 12) {
                if selectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.sbGoldDk : Color.sbWarm2)
                        .font(.system(size: 20))
                }
                SBAvatar(name: g.displayName, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(g.displayName)
                        .font(SBFont.bodySmallBold)
                        .foregroundStyle(Color.sbCharcoal)
                    HStack(spacing: 6) {
                        if let meal = g.meal, !meal.isEmpty {
                            mealPill(meal)
                        } else {
                            Text("No meal")
                                .font(SBFont.caption)
                                .foregroundStyle(Color.sbWarm2)
                        }
                        ForEach(g.dietaryTags ?? [], id: \.self) { tag in
                            if let emoji = DietaryTag.emoji(for: tag) {
                                Text(emoji).font(.system(size: 12))
                            }
                        }
                    }
                }
                Spacer()
                if !selectionMode {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sbWarm2)
                }
            }
            .padding(10)
            .background(isSelected ? Color.sbChampagne.opacity(0.5) : Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: SBRadius.button)
                    .strokeBorder(isSelected ? Color.sbGoldDk : Color.sbLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
        }
        .buttonStyle(.plain)
    }

    private func mealPill(_ meal: String) -> some View {
        Text(meal)
            .font(SBFont.caption)
            .foregroundStyle(Color.sbCharcoal)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.sbChampagne.opacity(0.6))
            .clipShape(Capsule())
    }

    // MARK: - Bulk action bar

    private var bulkActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                SBButton(title: "Edit \(selectedGuestIds.count)", icon: "fork.knife",
                         variant: .gold, fullWidth: true) {
                    bulkPickerOpen = true
                }
            }
            .padding(.horizontal, SBSpacing.screenMargin)
            .padding(.vertical, 12)
            .background(Color.sbIvory)
        }
    }

    // MARK: - Derived data

    /// Distinct meals already used in the plan, deduped case-insensitively
    /// (so "Beef" / "beef" surface as one chip, with display casing of
    /// the first occurrence). Sorted by descending guest count so the
    /// most-used options sit at the top of the picker.
    private var popularMeals: [PopularMeal] {
        var bag: [String: (display: String, count: Int)] = [:]
        for g in guests {
            guard let raw = g.meal?.trimmingCharacters(in: .whitespaces),
                  !raw.isEmpty else { continue }
            let key = raw.lowercased()
            if var existing = bag[key] {
                existing.count += 1
                bag[key] = existing
            } else {
                bag[key] = (display: raw, count: 1)
            }
        }
        return bag
            .map { PopularMeal(label: $0.value.display, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    private var mealBreakdown: [(label: String, count: Int)] {
        popularMeals.map { ($0.label, $0.count) }
    }

    private var dietaryBreakdown: [(id: String, label: String, emoji: String, count: Int)] {
        var counts: [String: Int] = [:]
        for g in guests {
            for t in g.dietaryTags ?? [] {
                counts[t, default: 0] += 1
            }
        }
        return DietaryTag.all
            .compactMap { entry in
                guard let n = counts[entry.id], n > 0 else { return nil }
                return (id: entry.id, label: entry.label, emoji: entry.emoji, count: n)
            }
            .sorted { $0.count > $1.count }
    }

    private var unsetCount: Int {
        guests.filter { ($0.meal?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) }.count
    }

    // MARK: - Mutations

    private func applyToGuest(_ id: String, result: MealPickerResult) {
        guard var p = plan else { return }
        guard let idx = p.guests.firstIndex(where: { $0.id == id }) else { return }
        if let meal = result.meal {
            p.guests[idx].meal = meal.isEmpty ? nil : meal
        }
        if let tags = result.dietaryTags {
            p.guests[idx].dietaryTags = tags.isEmpty ? nil : Array(tags)
        }
        appState.activePlan = p
        let snap = p
        Task { try? await appState.database.savePlanData(plan: snap) }
        HapticEngine.success()
    }

    private func applyBulk(result: MealPickerResult) {
        guard var p = plan else { return }
        for id in selectedGuestIds {
            guard let idx = p.guests.firstIndex(where: { $0.id == id }) else { continue }
            if let meal = result.meal {
                p.guests[idx].meal = meal.isEmpty ? nil : meal
            }
            if let tags = result.dietaryTags {
                p.guests[idx].dietaryTags = tags.isEmpty ? nil : Array(tags)
            }
        }
        appState.activePlan = p
        let snap = p
        Task { try? await appState.database.savePlanData(plan: snap) }
        HapticEngine.success()
    }
}

// MARK: - Picker bottom sheet

private struct GuestIdWrapper: Identifiable {
    let id: String
}

struct PopularMeal: Equatable {
    let label: String
    let count: Int
}

/// Result of a picker session. `nil` means "leave this field alone"
/// (only relevant in bulk mode where the user might choose to update
/// only meals OR only dietary tags). Empty values mean "clear".
struct MealPickerResult {
    var meal: String?
    var dietaryTags: Set<String>?
}

private struct MealPickerSheet: View {
    enum Mode { case single, bulk }

    let title: String
    let initialMeal: String?
    let initialDietaryTags: Set<String>
    let popularMeals: [PopularMeal]
    let mode: Mode
    let onApply: (MealPickerResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedMeal: String   // "" = none / clear
    @State private var customMealText: String
    @State private var selectedTags: Set<String>
    @State private var mealEdited: Bool       // bulk: did user touch meal section?
    @State private var dietaryEdited: Bool    // bulk: did user touch dietary section?

    init(title: String,
         initialMeal: String?,
         initialDietaryTags: Set<String>,
         popularMeals: [PopularMeal],
         mode: Mode,
         onApply: @escaping (MealPickerResult) -> Void) {
        self.title = title
        self.initialMeal = initialMeal
        self.initialDietaryTags = initialDietaryTags
        self.popularMeals = popularMeals
        self.mode = mode
        self.onApply = onApply
        _selectedMeal = State(initialValue: initialMeal ?? "")
        _customMealText = State(initialValue: "")
        _selectedTags = State(initialValue: initialDietaryTags)
        _mealEdited = State(initialValue: false)
        _dietaryEdited = State(initialValue: false)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    mealSection
                    dietarySection
                }
                .padding(.horizontal, SBSpacing.screenMargin)
                .padding(.top, 16)
                .padding(.bottom, 80)
            }
            .background(Color.sbIvory)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sbWarm)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Apply") { commit() }
                        .foregroundStyle(Color.sbGoldDk)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Meal section

    private var mealSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MEAL")
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)

            if mode == .bulk {
                bulkSectionToggle(label: "Update meal for selected guests",
                                  isOn: $mealEdited)
            }

            if mode == .single || mealEdited {
                if !popularMeals.isEmpty {
                    FlowLayout(spacing: 8) {
                        // "None" — explicit clear option. Skipped in
                        // bulk because the toggle handles "leave alone";
                        // here in single mode it reads more naturally
                        // than typing an empty custom field.
                        if mode == .single {
                            mealChip(label: "None", value: "",
                                     count: nil,
                                     selected: selectedMeal.isEmpty && customMealText.isEmpty)
                        }
                        ForEach(popularMeals, id: \.label) { p in
                            mealChip(label: p.label, value: p.label,
                                     count: p.count,
                                     selected: selectedMeal.caseInsensitiveCompare(p.label) == .orderedSame)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "pencil.line")
                        .foregroundStyle(Color.sbGoldDk)
                        .font(.system(size: 14))
                    TextField("Custom meal (e.g. \"Chicken fingers\")",
                              text: $customMealText)
                        .textFieldStyle(.plain)
                        .font(SBFont.body)
                        .onChange(of: customMealText) { _, newValue in
                            if !newValue.isEmpty {
                                selectedMeal = ""    // chips deselect
                            }
                            if mode == .bulk { mealEdited = true }
                        }
                    if !customMealText.isEmpty {
                        Button {
                            customMealText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.sbWarm2)
                        }
                    }
                }
                .padding(10)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: SBRadius.small)
                        .strokeBorder(Color.sbLine, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
            }
        }
    }

    private func mealChip(label: String, value: String, count: Int?, selected: Bool) -> some View {
        Button {
            selectedMeal = value
            customMealText = ""
            if mode == .bulk { mealEdited = true }
            HapticEngine.selection()
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(SBFont.caption)
                if let count {
                    Text("\(count)")
                        .font(SBFont.caption)
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.sbWarm)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? Color.white : Color.sbCharcoal)
            .background(selected ? Color.sbGoldDk : Color.white)
            .overlay(
                Capsule().strokeBorder(selected ? Color.sbGoldDk : Color.sbLine,
                                       lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Dietary section

    private var dietarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DIETARY")
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)

            if mode == .bulk {
                bulkSectionToggle(label: "Update dietary for selected guests",
                                  isOn: $dietaryEdited)
            }

            if mode == .single || dietaryEdited {
                FlowLayout(spacing: 8) {
                    ForEach(DietaryTag.all, id: \.id) { tag in
                        let on = selectedTags.contains(tag.id)
                        Button {
                            if on { selectedTags.remove(tag.id) }
                            else { selectedTags.insert(tag.id) }
                            if mode == .bulk { dietaryEdited = true }
                            HapticEngine.selection()
                        } label: {
                            HStack(spacing: 4) {
                                Text(tag.emoji).font(.system(size: 12))
                                Text(tag.label)
                                    .font(SBFont.caption)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundStyle(on ? Color.white : Color.sbCharcoal)
                            .background(on ? Color.sbSage : Color.white)
                            .overlay(
                                Capsule().strokeBorder(on ? Color.sbSage : Color.sbLine,
                                                       lineWidth: 1)
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if mode == .bulk {
                    Text("Selected tags REPLACE the current dietary tags on each guest.")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                }
            }
        }
    }

    // MARK: - Bulk section toggle

    /// In bulk mode, each section is opt-in. Default is "leave this
    /// field alone for every selected guest" so users can update meals
    /// without accidentally wiping dietary, or vice versa.
    private func bulkSectionToggle(label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .font(SBFont.caption)
                .foregroundStyle(Color.sbCharcoal)
        }
        .tint(Color.sbGoldDk)
    }

    // MARK: - Commit

    private func commit() {
        var result = MealPickerResult()
        switch mode {
        case .single:
            // Custom takes precedence over chip. Empty custom + empty
            // chip = "None" / clear.
            let trimmed = customMealText.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                result.meal = trimmed
            } else {
                result.meal = selectedMeal
            }
            result.dietaryTags = selectedTags
        case .bulk:
            if mealEdited {
                let trimmed = customMealText.trimmingCharacters(in: .whitespaces)
                result.meal = trimmed.isEmpty ? selectedMeal : trimmed
            }
            if dietaryEdited {
                result.dietaryTags = selectedTags
            }
        }
        onApply(result)
    }
}

#Preview {
    MealsSheet()
        .environment(AppState())
}
