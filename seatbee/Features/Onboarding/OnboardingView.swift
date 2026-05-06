import SwiftUI

// Onboarding flow — 3-step event creation wizard.
//
// Web parity (App.jsx OnboardingWizard, ~line 19180): web has a 7–9 step
// flow with branching by event type, full corporate support, floor plan
// upload, and CSV column mapping. iOS keeps it mobile-friendly with
// just three steps and defers corporate / floor plan / CSV mapping to
// Phase 2 (see PARITY.md "Outstanding" table).
//
// Step 1 — Event setup: type picker, partner inputs (with optional role
//   markers for inclusivity — Shayan's intentional default), date,
//   venue, expected guests, measurement unit.
// Step 2 — Guest list: paste or AI-detect (existing).
// Step 3 — Review: summary + Create button. Shows a loading overlay
//   when finalising. Room layout customisation happens in the canvas
//   after creation, not during onboarding.
//
// On finish, iOS seeds matching defaults web seeds:
//   - DEFAULT_CATS[eventType] categories (mirrors App.jsx:3042-3075)
//   - Couple `seat_adjacent` rule + bride/groom guest auto-add (wedding)
//   - Default round-table layout sized to expected guests
//   - coupleType derived from per-partner role markers

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var step = 1

    // Step 1 — Event setup
    @State private var eventType: EventTypeOption = .wedding
    @State private var customEventName = ""
    @State private var partner1Name = ""
    @State private var partner2Name = ""
    @State private var partner1Role: PartnerRole = .unspecified
    @State private var partner2Role: PartnerRole = .unspecified
    @State private var eventDate = Date()
    @State private var hasSetDate = false
    @State private var venueName = ""
    @State private var expectedGuests: Int = 100
    @State private var customGuestCount = ""
    @State private var useMetric = false

    // Step 2 — Guest list
    @State private var guestListText = ""
    @State private var detectedGuests: [Guest] = []
    @State private var isProcessing = false

    // Step 3 — Review / creating
    @State private var isCreating = false
    @State private var errorMessage: String?

    // MARK: - Local enums

    enum EventTypeOption: String {
        case wedding, celebration

        var displayName: String {
            switch self {
            case .wedding:     return "Wedding"
            case .celebration: return "Celebration"
            }
        }
        var iconName: String {
            switch self {
            case .wedding:     return "heart"
            case .celebration: return "sparkles"
            }
        }
        var subtitle: String {
            switch self {
            case .wedding:     return "Couples, family, parties"
            case .celebration: return "Birthday, anniversary, party"
            }
        }
    }

    enum PartnerRole: String {
        case bride, groom, unspecified
    }

    // MARK: - Computed

    private var planName: String {
        if !customEventName.trimmingCharacters(in: .whitespaces).isEmpty {
            return customEventName.trimmingCharacters(in: .whitespaces)
        }
        switch eventType {
        case .wedding:
            if !partner1Name.isEmpty && !partner2Name.isEmpty {
                return "\(partner1Name) & \(partner2Name)'s Wedding"
            } else if !partner1Name.isEmpty {
                return "\(partner1Name)'s Wedding"
            }
            return "My Wedding"
        case .celebration:
            return "My Event"
        }
    }

    private var coupleType: String {
        switch (partner1Role, partner2Role) {
        case (.bride, .bride):  return "bride_bride"
        case (.groom, .groom):  return "groom_groom"
        default:                return "bride_groom"
        }
    }

    private var step1Valid: Bool {
        switch eventType {
        case .wedding:
            return !partner1Name.isEmpty || !partner2Name.isEmpty || !customEventName.trimmingCharacters(in: .whitespaces).isEmpty
        case .celebration:
            return !customEventName.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var estimatedTableCount: Int {
        let regular = max(1, Int(ceil(Double(expectedGuests) / 8.0)))
        let extras = eventType == .wedding ? 2 : 0   // head + sweetheart
        return regular + extras
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressDots.padding(.top, 16)
                ScrollView {
                    VStack(spacing: 0) {
                        switch step {
                        case 1: eventSetupStep
                        case 2: guestListStep
                        case 3: isCreating ? AnyView(creatingStep) : AnyView(reviewStep)
                        default: EmptyView()
                        }
                    }
                    .padding(.horizontal, SBSpacing.screenMargin)
                    .padding(.top, 24)
                }
                if !isCreating {
                    bottomCTA.padding(.horizontal, SBSpacing.screenMargin).padding(.bottom, 32)
                }
            }
            .background(Color.sbIvory)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step > 1 && !isCreating {
                        Button {
                            withAnimation(.seatbee) { step -= 1 }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .font(SBFont.bodySmall)
                            .foregroundStyle(Color.sbGoldDk)
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !isCreating {
                        Button("Cancel") { dismiss() }
                            .font(SBFont.bodySmall)
                            .foregroundStyle(Color.sbWarm)
                    }
                }
            }
        }
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(1...3, id: \.self) { i in
                Circle()
                    .fill(i <= step ? Color.sbGold : Color.sbWarm2)
                    .frame(width: i == step ? 10 : 8, height: i == step ? 10 : 8)
                    .animation(.seatbee, value: step)
            }
        }
    }

    // MARK: - Step 1: Event setup

    private var eventSetupStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 8) {
                Image("SeatbeeLogo").resizable().aspectRatio(contentMode: .fit).frame(width: 56, height: 56)
                Text(eventType == .wedding ? "Plan your wedding" : "Plan your event")
                    .font(SBFont.displayLarge)
                    .foregroundStyle(Color.sbCharcoal)
                Text("Tell us a few details and we'll set everything up.")
                    .font(SBFont.body)
                    .foregroundStyle(Color.sbWarm)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            // Event type picker
            sectionHeader("EVENT TYPE")
            HStack(spacing: 10) {
                eventTypeButton(.wedding)
                eventTypeButton(.celebration)
            }

            // Partner block (wedding) OR event name (celebration)
            if eventType == .wedding {
                sectionHeader("WHO'S GETTING MARRIED?")
                Text("Names are optional, but they help us auto-fill your event name and add a couple-adjacent seating rule.")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
                partnerRow(name: $partner1Name, role: $partner1Role, placeholder: "Partner 1")
                partnerRow(name: $partner2Name, role: $partner2Role, placeholder: "Partner 2")

                if !partner1Name.isEmpty || !partner2Name.isEmpty {
                    Text("\"\(planName)\"")
                        .font(SBFont.fraunces(18, weight: .medium))
                        .foregroundStyle(Color.sbGoldDk)
                        .italic()
                        .frame(maxWidth: .infinity)
                }

                // Custom event name override (collapsed unless typed in)
                sectionHeader("OR PICK A CUSTOM EVENT NAME (OPTIONAL)")
                TextField("e.g. Sarah & Tom's Wedding", text: $customEventName)
                    .font(SBFont.body)
                    .padding(14)
                    .background(Color.sbIvory2)
                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
            } else {
                sectionHeader("EVENT NAME")
                TextField("e.g. Dad's 60th Birthday", text: $customEventName)
                    .font(SBFont.body)
                    .padding(14)
                    .background(Color.sbIvory2)
                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
            }

            // Date
            sectionHeader(eventType == .wedding ? "WHEN'S THE BIG DAY?" : "WHEN?")
            DatePicker("Date", selection: $eventDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .font(SBFont.body)
                .tint(Color.sbGold)
                .onChange(of: eventDate) { _, _ in hasSetDate = true }

            // Venue
            sectionHeader("WHERE? (OPTIONAL)")
            SBVenueSearch(venueName: $venueName)

            // Expected guests
            sectionHeader("EXPECTED GUESTS")
            guestCountPicker

            // Measurement unit
            sectionHeader("MEASUREMENTS")
            Picker("Unit", selection: $useMetric) {
                Text("Feet").tag(false)
                Text("Meters").tag(true)
            }
            .pickerStyle(.segmented)
            .tint(Color.sbGold)

            Spacer(minLength: 40)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(SBFont.capsLabel)
            .foregroundStyle(Color.sbWarm)
            .letterSpacing(1.5)
            .padding(.top, 8)
    }

    private func eventTypeButton(_ type: EventTypeOption) -> some View {
        let active = eventType == type
        return Button {
            withAnimation(.seatbee) { eventType = type }
            HapticEngine.selection()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: type.iconName).font(.system(size: 22))
                Text(type.displayName).font(SBFont.bodySemibold)
                Text(type.subtitle).font(SBFont.caption).foregroundStyle(Color.sbWarm).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(active ? Color.sbChampagne.opacity(0.7) : Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
            .overlay(
                RoundedRectangle(cornerRadius: SBRadius.button)
                    .strokeBorder(active ? Color.sbGold : Color.sbLine2, lineWidth: active ? 2 : 1)
            )
            .foregroundStyle(active ? Color.sbGoldDk : Color.sbCharcoal)
        }
        .buttonStyle(.plain)
    }

    private func partnerRow(name: Binding<String>, role: Binding<PartnerRole>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(placeholder, text: name)
                .font(SBFont.body)
                .padding(14)
                .background(Color.sbIvory2)
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
            HStack(spacing: 6) {
                roleChip("Bride", role: .bride, binding: role)
                roleChip("Groom", role: .groom, binding: role)
                Spacer()
            }
        }
    }

    private func roleChip(_ label: String, role: PartnerRole, binding: Binding<PartnerRole>) -> some View {
        let active = binding.wrappedValue == role
        return Button {
            // Tap toggles — second tap unmarks. "Unspecified" stays the
            // default for users who don't want to commit to either role.
            binding.wrappedValue = active ? .unspecified : role
            HapticEngine.selection()
        } label: {
            Text(label)
                .font(SBFont.caption)
                .foregroundStyle(active ? Color.white : Color.sbCharcoal2)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(active ? Color.sbGold : Color.sbIvory2)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var guestCountPicker: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach([50, 100, 250, 500], id: \.self) { count in
                    let active = expectedGuests == count
                    Button {
                        expectedGuests = count
                        customGuestCount = ""
                        HapticEngine.selection()
                    } label: {
                        Text("\(count)")
                            .font(SBFont.bodySemibold)
                            .foregroundStyle(active ? Color.white : Color.sbCharcoal)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(active ? Color.sbGold : Color.sbIvory2)
                            .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                Text("Custom")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
                TextField("e.g. 175", text: $customGuestCount)
                    .keyboardType(.numberPad)
                    .font(SBFont.body)
                    .padding(8)
                    .background(Color.sbIvory2)
                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
                    .onChange(of: customGuestCount) { _, newValue in
                        if let n = Int(newValue), n > 0 { expectedGuests = n }
                    }
            }
        }
    }

    // MARK: - Step 2: Guest list

    private var guestListStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.sbGoldDk)
                Text("Add your guests")
                    .font(SBFont.displayMedium)
                    .foregroundStyle(Color.sbCharcoal)
                Text("Paste a list and we'll detect names. You can always add or import more later.")
                    .font(SBFont.body)
                    .foregroundStyle(Color.sbWarm)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                Text("PASTE NAMES")
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbWarm)
                    .letterSpacing(1.5)

                ZStack(alignment: .topLeading) {
                    if guestListText.isEmpty {
                        Text("Sarah Chen, vegetarian\nJon Park\nMia Khalid, +1\n...")
                            .font(SBFont.body)
                            .foregroundStyle(Color.sbWarm2)
                            .padding(14)
                    }
                    TextEditor(text: $guestListText)
                        .font(SBFont.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                }
                .frame(height: 180)
                .background(Color.sbIvory2)
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
            }

            if !detectedGuests.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(detectedGuests.count) DETECTED")
                        .font(SBFont.capsLabel)
                        .foregroundStyle(Color.sbGoldDk)
                        .letterSpacing(1.5)
                    FlowLayout(spacing: 6) {
                        ForEach(detectedGuests.prefix(20), id: \.id) { g in
                            Text(g.displayName)
                                .font(SBFont.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.sbChampagne.opacity(0.6))
                                .clipShape(Capsule())
                        }
                        if detectedGuests.count > 20 {
                            Text("+\(detectedGuests.count - 20) more")
                                .font(SBFont.caption)
                                .foregroundStyle(Color.sbWarm)
                        }
                    }
                }
            }

            Spacer(minLength: 40)
        }
    }

    // MARK: - Step 3: Review

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.sbSage)
                Text("Almost there")
                    .font(SBFont.displayMedium)
                    .foregroundStyle(Color.sbCharcoal)
                Text("Review your plan and tap Create. You can customise the room layout in the canvas after.")
                    .font(SBFont.body)
                    .foregroundStyle(Color.sbWarm)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 0) {
                summaryRow(label: "Type", value: eventType.displayName)
                summaryRow(label: "Name", value: planName)
                if eventType == .wedding && (partner1Role != .unspecified || partner2Role != .unspecified) {
                    summaryRow(label: "Couple", value: friendlyCoupleType)
                }
                if hasSetDate {
                    summaryRow(label: "Date", value: eventDate.formatted(date: .abbreviated, time: .omitted))
                }
                if !venueName.isEmpty {
                    summaryRow(label: "Venue", value: venueName)
                }
                summaryRow(label: "Expected guests", value: "\(expectedGuests)")
                summaryRow(label: "Estimated tables", value: "\(estimatedTableCount)")
                summaryRow(label: "Measurements", value: useMetric ? "Meters" : "Feet")
                if !detectedGuests.isEmpty {
                    summaryRow(label: "Guests detected", value: "\(detectedGuests.count)", isLast: true)
                } else {
                    summaryRow(label: "Guests", value: "Add later", isLast: true)
                }
            }
            .background(Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))

            Text("After we create your plan, you can customise the room layout (shape, dimensions, floor plan) from the canvas.")
                .font(SBFont.caption)
                .foregroundStyle(Color.sbWarm)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Spacer(minLength: 40)
        }
    }

    private func summaryRow(label: String, value: String, isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(SBFont.bodySmall)
                    .foregroundStyle(Color.sbWarm)
                Spacer()
                Text(value)
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(Color.sbCharcoal)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            if !isLast {
                Divider().background(Color.sbLine).padding(.horizontal, 14)
            }
        }
    }

    private var friendlyCoupleType: String {
        switch coupleType {
        case "bride_bride": return "Bride & Bride"
        case "groom_groom": return "Groom & Groom"
        default:            return "Bride & Groom"
        }
    }

    // MARK: - Creating

    private var creatingStep: some View {
        VStack(spacing: 24) {
            Spacer()
            HoneycombLoader().frame(width: 180, height: 180)
            Text("Setting up your plan…")
                .font(SBFont.bodySemibold)
                .foregroundStyle(Color.sbCharcoal)
            Text("Categories, rules, table layout — preparing everything")
                .font(SBFont.caption)
                .foregroundStyle(Color.sbWarm)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Bottom CTA

    private var bottomCTA: some View {
        VStack(spacing: 12) {
            if let errorMessage {
                Text(errorMessage)
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbError)
            }

            switch step {
            case 1:
                SBButton(title: "Continue", icon: "arrow.right", variant: .gold, fullWidth: true) {
                    withAnimation(.seatbee) { step = 2 }
                }
                .disabled(!step1Valid)
                .opacity(step1Valid ? 1 : 0.5)

            case 2:
                if guestListText.isEmpty && detectedGuests.isEmpty {
                    SBButton(title: "Skip — add guests later", icon: "arrow.right", variant: .gold, fullWidth: true) {
                        withAnimation(.seatbee) { step = 3 }
                    }
                } else if detectedGuests.isEmpty {
                    SBButton(title: "Detect guests", icon: "sparkles", variant: .gold, fullWidth: true) {
                        detectGuests()
                    }
                    .disabled(isProcessing)
                } else {
                    SBButton(title: "Continue with \(detectedGuests.count) guests", icon: "arrow.right", variant: .gold, fullWidth: true) {
                        withAnimation(.seatbee) { step = 3 }
                    }
                }

            case 3:
                SBButton(title: "Create plan", icon: "sparkles", variant: .gold, fullWidth: true) {
                    finalizePlan()
                }

            default:
                EmptyView()
            }
        }
    }

    // MARK: - Actions

    private func detectGuests() {
        isProcessing = true
        errorMessage = nil
        Task {
            do {
                detectedGuests = try await appState.ai.parseGuestList(text: guestListText)
                HapticEngine.success()
            } catch {
                errorMessage = "Couldn't detect guests. You can still create the plan."
                HapticEngine.error()
            }
            isProcessing = false
        }
    }

    private func finalizePlan() {
        isCreating = true
        errorMessage = nil

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        Task {
            do {
                // Build guests: detected + auto-add bride/groom if marked.
                let coupleAutoGuests = buildCoupleGuests()
                let allGuests = coupleAutoGuests + detectedGuests
                let guestDTOs: [GuestDTO]? = allGuests.isEmpty ? nil : allGuests.map { g in
                    GuestDTO(
                        id: g.id, name: g.name, firstName: g.firstName,
                        lastName: g.lastName, email: g.email,
                        categories: g.categories, dietary: g.dietary,
                        notes: g.notes, rsvp: g.rsvp.rawValue,
                        side: g.side.rawValue, vip: g.vip,
                        accessibility: g.accessibility, plusOne: g.plusOne,
                        party: g.party, display: g.displayName,
                        dietaryTags: g.dietaryTags, highChair: g.highChair,
                        isChild: g.isChild, groupIds: g.groupIds,
                        isBride: g.isBride, isGroom: g.isGroom,
                        meal: g.meal.map { MealField($0) }, createdAt: g.guestCreatedAt
                    )
                }

                // Initial table layout: rounds of 8 + head + sweetheart for wedding.
                let tableDTOs = buildInitialTableDTOs()

                // Create the plan
                var plan = try await appState.database.createPlan(
                    name: planName,
                    eventType: eventType.rawValue,
                    eventDate: hasSetDate ? dateFormatter.string(from: eventDate) : nil,
                    venue: venueName.isEmpty ? nil : venueName,
                    guests: guestDTOs,
                    tables: tableDTOs.isEmpty ? nil : tableDTOs
                )

                // Seed: categories + couple rule + room defaults + couple type
                plan.measurementUnit = useMetric ? "metric" : "imperial"
                plan.coupleType = eventType == .wedding ? coupleType : nil
                plan.hasSweetheartTable = eventType == .wedding
                plan.rules = buildInitialRules(coupleAutoGuests: coupleAutoGuests)
                plan.rawCategories = defaultCategoriesAsRaw(for: eventType)

                try await appState.database.savePlanData(plan: plan)

                appState.activePlan = plan
                HapticEngine.success()
                try? await Task.sleep(for: .seconds(0.6))
                dismiss()
                appState.selectedTab = .edit
            } catch {
                errorMessage = "Failed to create plan: \(error.localizedDescription)"
                isCreating = false
                HapticEngine.error()
                print("[Onboarding] Error creating plan: \(error)")
            }
        }
    }

    // MARK: - Seed helpers

    /// Web parity: DEFAULT_CATS at App.jsx:3042-3075. iOS uses a subset
    /// (12 wedding / 6 celebration). Only essentials — users can add
    /// custom categories from the Categories sheet later.
    private func defaultCategoriesAsRaw(for type: EventTypeOption) -> [[String: AnyCodable]] {
        let raw: [(id: String, name: String, color: String, isSystem: Bool, weight: Int)]
        switch type {
        case .wedding:
            raw = [
                ("head_table",       "Head Table",       "#C9A961", true,  95),
                ("sweetheart_table", "Sweetheart Table", "#D4A5A5", true,  95),
                ("bride",            "Bride",            "#D4A5A5", true,  85),
                ("groom",            "Groom",            "#9CAF88", true,  85),
                ("wedding_party",    "Wedding Party",    "#C9A961", false, 95),
                ("parents",          "Parents",          "#A88843", false, 85),
                ("grandparents",     "Grandparents",     "#8B8680", false, 85),
                ("family",           "Family",           "#9CAF88", false, 75),
                ("friends",          "Friends",          "#C9A961", false, 65),
                ("work",             "Work",             "#8B8680", false, 65),
                ("kids",             "Kids",             "#D4A5A5", false, 65),
            ]
        case .celebration:
            raw = [
                ("head_table",  "Head Table", "#C9A961", true,  95),
                ("family",      "Family",     "#9CAF88", false, 75),
                ("friends",     "Friends",    "#C9A961", false, 65),
                ("neighbors",   "Neighbors",  "#8B8680", false, 65),
                ("work",        "Work",       "#8B8680", false, 65),
                ("vip",         "VIP",        "#A88843", false, 40),
            ]
        }
        return raw.map { c in
            [
                "id":              AnyCodable(c.id),
                "name":            AnyCodable(c.name),
                "color":           AnyCodable(c.color),
                "isSystem":        AnyCodable(c.isSystem),
                "affinityWeight":  AnyCodable(c.weight),
            ]
        }
    }

    /// Auto-create bride/groom guests from partner roles (wedding only).
    /// Only creates a Guest if the partner has BOTH a name AND a marked
    /// role — partial markings stay on the plan as data but don't get
    /// turned into guests.
    private func buildCoupleGuests() -> [Guest] {
        guard eventType == .wedding else { return [] }
        var out: [Guest] = []

        if !partner1Name.isEmpty, partner1Role != .unspecified {
            out.append(coupleGuest(name: partner1Name, role: partner1Role))
        }
        if !partner2Name.isEmpty, partner2Role != .unspecified {
            out.append(coupleGuest(name: partner2Name, role: partner2Role))
        }
        return out
    }

    private func coupleGuest(name: String, role: PartnerRole) -> Guest {
        let cat = role == .bride ? "bride" : "groom"
        return Guest(
            id: "guest_\(cat)_\(UUID().uuidString.prefix(8))",
            name: name,
            firstName: nil, lastName: nil, email: nil,
            categories: [cat, "head_table", "sweetheart_table"],
            dietary: nil, notes: nil,
            rsvp: .yes,
            side: role == .bride ? .bride : .groom,
            vip: true,
            accessibility: nil, plusOne: nil, party: nil, display: name,
            dietaryTags: nil, highChair: nil, isChild: nil, groupIds: nil,
            isBride: role == .bride ? true : nil,
            isGroom: role == .groom ? true : nil,
            meal: nil, guestCreatedAt: nil
        )
    }

    /// Couple-adjacent rule for wedding plans where both partners were
    /// added as guests. Mirrors web's auto-rule at App.jsx:19743.
    private func buildInitialRules(coupleAutoGuests: [Guest]) -> [SeatingRule] {
        guard eventType == .wedding, coupleAutoGuests.count == 2 else { return [] }
        return [
            SeatingRule(
                id: "rule_couple_\(UUID().uuidString.prefix(8))",
                type: .seatAdjacent,
                guests: coupleAutoGuests.map(\.id),
                tableId: nil,
                weight: 100,
                hard: true,
                enabled: true,
                desc: "Couple seated adjacent",
                source: "onboarding"
            )
        ]
    }

    /// Generates a starter table layout: rounds of 8, plus a head + an
    /// optional sweetheart for wedding. Positions tables in a simple
    /// grid centred in the default room. Users can rearrange in canvas.
    private func buildInitialTableDTOs() -> [TableDTO] {
        var out: [TableDTO] = []
        let scale: Double = useMetric ? 49.21 : 15  // px per unit
        let regularCount = max(1, Int(ceil(Double(expectedGuests) / 8.0)))
        let cellSize: Double = scale * 9   // ~9 ft of room per table cell
        let cols = max(1, Int(ceil(sqrt(Double(regularCount)))))
        let startX: Double = 200
        let startY: Double = 250

        for i in 0..<regularCount {
            let col = i % cols
            let row = i / cols
            out.append(TableDTO(
                id: "tbl_round_\(UUID().uuidString.prefix(6))",
                name: "Table \(i + 1)",
                type: "round", seats: 8,
                x: startX + Double(col) * cellSize,
                y: startY + Double(row) * cellSize,
                rotation: 0,
                locked: false, color: "#9CAF88",
                width: nil, height: nil, diameter: 90,
                sweetShape: nil, oneSide: nil,
                notes: nil
            ))
        }

        if eventType == .wedding {
            out.append(TableDTO(
                id: "tbl_head_\(UUID().uuidString.prefix(6))",
                name: "Head Table",
                type: "head", seats: 8,
                x: 350, y: 80, rotation: 0,
                locked: false, color: "#C9A961",
                width: 280, height: 50, diameter: nil,
                sweetShape: nil, oneSide: true,
                notes: nil
            ))
            out.append(TableDTO(
                id: "tbl_sweet_\(UUID().uuidString.prefix(6))",
                name: "Sweetheart",
                type: "sweetheart", seats: 2,
                x: 400, y: 160, rotation: 0,
                locked: false, color: "#D4A5A5",
                width: 100, height: 60, diameter: nil,
                sweetShape: "heart", oneSide: nil,
                notes: nil
            ))
        }

        return out
    }
}

#Preview {
    OnboardingView()
        .environment(AppState())
}
