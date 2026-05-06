import SwiftUI
import UniformTypeIdentifiers

// 5-step onboarding wizard. Mirrors the essentials of web's
// OnboardingWizard (App.jsx:19180) while staying mobile-friendly.
//
//   Step 1 — Event basics      (type, editable name, partners, date, venue)
//   Step 2 — Guest list        (count + paste/CSV/AI detect/skip)
//   Step 3 — Room setup        (measurement unit, room size preset, room shape)
//   Step 4 — Tables & venue    (style, seats/table, head + sweetheart, items)
//   Step 5 — Review & create   (summary + Create)
//
// Defers to Phase 2 (documented in PARITY.md "Outstanding"):
//   - Floor plan upload + 3-phase trace inside onboarding (RoomSetupSheet
//     handles this in canvas after creation).
//   - Crowdsourcing room-details form for venue inventory.
//   - Corporate flow + corporate review step.
//   - Full 60+ venue-object catalogue (curated 8 in onboarding).

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var step = 1

    // MARK: - Step 1
    @State private var eventType: EventTypeOption = .wedding
    @State private var eventName = ""
    @State private var eventNameEdited = false  // tracks if user manually changed it
    @State private var partner1Name = ""
    @State private var partner2Name = ""
    @State private var partner1Role: PartnerRole = .unspecified
    @State private var partner2Role: PartnerRole = .unspecified
    @State private var eventDate = Date()
    @State private var hasSetDate = false
    @State private var venueName = ""

    // MARK: - Step 2
    @State private var expectedGuests: Int = 100
    @State private var customGuestCount = ""
    @State private var guestListText = ""
    @State private var detectedGuests: [Guest] = []
    @State private var detectedPartiesCount = 0
    @State private var detectedPlatform: String?
    @State private var isProcessing = false
    @State private var showFilePicker = false
    @State private var csvImportError: String?

    // MARK: - Step 3
    @State private var useMetric = false
    @State private var roomPreset: RoomPreset = .medium
    @State private var roomShape: RoomShapeOption = .rect

    // MARK: - Step 4
    @State private var tableStyle: TableStyle = .round
    @State private var seatsPerTable: Int = 8
    @State private var includeHeadTable = true
    @State private var includeSweetheartTable = true
    @State private var venueItems: Set<String> = []  // type strings

    // MARK: - Step 5 / creating
    @State private var isCreating = false
    @State private var errorMessage: String?

    // MARK: - Local enums

    enum EventTypeOption: String {
        case wedding, celebration
        var displayName: String { self == .wedding ? "Wedding" : "Celebration" }
        var iconName: String   { self == .wedding ? "heart" : "sparkles" }
        var subtitle: String   { self == .wedding ? "Couples, family, parties" : "Birthday, anniversary, party" }
    }
    enum PartnerRole: String { case bride, groom, unspecified }
    enum TableStyle: String, CaseIterable {
        case round, long, mix
        var displayName: String { rawValue.capitalized }
        var subtitle: String {
            switch self {
            case .round: return "Great for conversation"
            case .long:  return "Formal, maximises space"
            case .mix:   return "Flexibility for groups"
            }
        }
    }

    /// Web parity (App.jsx:19340-19347). 6 presets — feet × feet, with
    /// recommended guest range. iOS picks the matching px dims.
    enum RoomPreset: String, CaseIterable {
        case small, medium, large, ballroom, grand, convention

        var displayName: String {
            switch self {
            case .small: return "Small"
            case .medium: return "Medium"
            case .large: return "Large"
            case .ballroom: return "Ballroom"
            case .grand: return "Grand"
            case .convention: return "Convention"
            }
        }
        /// Returns (widthPx, heightPx) — px-per-foot scale = 15. Mirrors
        /// roomSizes at App.jsx:19340.
        var dimensionsPx: (width: Double, height: Double) {
            switch self {
            case .small:      return (750, 525)
            case .medium:     return (1200, 900)
            case .large:      return (1650, 1200)
            case .ballroom:   return (2250, 1500)
            case .grand:      return (3000, 2250)
            case .convention: return (4500, 3000)
            }
        }
        var guestRange: String {
            switch self {
            case .small:      return "up to 50 guests"
            case .medium:     return "50–120 guests"
            case .large:      return "120–250 guests"
            case .ballroom:   return "250–400 guests"
            case .grand:      return "400–700 guests"
            case .convention: return "700+ guests"
            }
        }
    }

    /// 6 shape options (Web's SHAPES enum trimmed to common ones).
    /// "custom" defers to the canvas RoomSetupSheet for tracing.
    enum RoomShapeOption: String, CaseIterable {
        case rect, l, t, u, oval, circle
        var displayName: String {
            switch self {
            case .rect:   return "Rectangle"
            case .l:      return "L-Shape"
            case .t:      return "T-Shape"
            case .u:      return "U-Shape"
            case .oval:   return "Oval"
            case .circle: return "Circle"
            }
        }
        var iconName: String {
            switch self {
            case .rect:   return "rectangle"
            case .l:      return "l.rectangle.roundedbottom"
            case .t:      return "t.square"
            case .u:      return "u.square"
            case .oval:   return "oval"
            case .circle: return "circle"
            }
        }
    }

    /// 8 curated venue items (web has 60+ across 8 categories — this is
    /// the most-used subset for onboarding speed). Full catalogue stays
    /// accessible from canvas via `VenueObjectsSheet`.
    private static let venueItemCatalog: [(type: String, name: String, icon: String)] = [
        ("dance",      "Dance Floor",  "music.note"),
        ("bar",        "Bar",          "wineglass"),
        ("dj",         "DJ Booth",     "music.mic"),
        ("stage",      "Stage",        "tv"),
        ("cake",       "Cake Table",   "birthday.cake"),
        ("gift",       "Gift Table",   "gift"),
        ("photo",      "Photo Booth",  "camera"),
        ("entrance",   "Entrance",     "door.left.hand.open"),
    ]

    // MARK: - Computed

    /// Auto-fills from partner names when wedding & user hasn't manually
    /// edited the field. Once edited, locks to the user's input.
    private var defaultedEventName: String {
        if eventNameEdited { return eventName }
        switch eventType {
        case .wedding:
            if !partner1Name.isEmpty && !partner2Name.isEmpty {
                return "\(partner1Name) & \(partner2Name)'s Wedding"
            } else if !partner1Name.isEmpty {
                return "\(partner1Name)'s Wedding"
            }
            return ""
        case .celebration:
            return ""
        }
    }

    private var coupleType: String {
        switch (partner1Role, partner2Role) {
        case (.bride, .bride): return "bride_bride"
        case (.groom, .groom): return "groom_groom"
        default:               return "bride_groom"
        }
    }

    private var step1Valid: Bool {
        let trimmed = eventName.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty || !partner1Name.isEmpty || !partner2Name.isEmpty
    }

    private var resolvedEventName: String {
        let trimmed = eventName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        if !partner1Name.isEmpty && !partner2Name.isEmpty {
            return "\(partner1Name) & \(partner2Name)'s Wedding"
        } else if !partner1Name.isEmpty {
            return "\(partner1Name)'s Wedding"
        }
        return eventType == .wedding ? "My Wedding" : "My Event"
    }

    private var estimatedTableCount: Int {
        let regular = max(1, Int(ceil(Double(expectedGuests) / Double(seatsPerTable))))
        var extras = 0
        if eventType == .wedding {
            if includeHeadTable { extras += 1 }
            if includeSweetheartTable { extras += 1 }
        }
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
                        case 1: eventBasicsStep
                        case 2: guestsStep
                        case 3: roomSetupStep
                        case 4: tablesStep
                        case 5: isCreating ? AnyView(creatingStep) : AnyView(reviewStep)
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
                        Button { withAnimation(.seatbee) { step -= 1 } } label: {
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
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.commaSeparatedText, .plainText, .data]
            ) { result in
                switch result {
                case .success(let url):
                    importCSVFromURL(url)
                case .failure(let error):
                    csvImportError = error.localizedDescription
                }
            }
        }
        .onChange(of: defaultedEventName) { _, newValue in
            // Only push the auto-fill into the field while the user
            // hasn't explicitly edited. Once they type, defaultedEventName
            // already returns their value so this is a no-op.
            if !eventNameEdited { eventName = newValue }
        }
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { i in
                Circle()
                    .fill(i <= step ? Color.sbGold : Color.sbWarm2)
                    .frame(width: i == step ? 9 : 7, height: i == step ? 9 : 7)
                    .animation(.seatbee, value: step)
            }
        }
    }

    // MARK: - Step 1: Event basics

    private var eventBasicsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 8) {
                Image("SeatbeeLogo").resizable().aspectRatio(contentMode: .fit).frame(width: 56, height: 56)
                Text(eventType == .wedding ? "Plan your wedding" : "Plan your event")
                    .font(SBFont.displayLarge).foregroundStyle(Color.sbCharcoal)
                Text("Tell us a few details and we'll set everything up.")
                    .font(SBFont.body).foregroundStyle(Color.sbWarm).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            sectionLabel("EVENT TYPE")
            HStack(spacing: 10) {
                eventTypeButton(.wedding)
                eventTypeButton(.celebration)
            }

            if eventType == .wedding {
                sectionLabel("WHO'S GETTING MARRIED?")
                Text("Names are optional. Mark a Bride/Groom role to auto-tag their seat — leave blank to keep it neutral.")
                    .font(SBFont.caption).foregroundStyle(Color.sbWarm)
                partnerRow(name: $partner1Name, role: $partner1Role, placeholder: "Partner 1")
                partnerRow(name: $partner2Name, role: $partner2Role, placeholder: "Partner 2")
            }

            sectionLabel("EVENT NAME")
            TextField(eventType == .wedding ? "e.g. Sarah & Tom's Wedding" : "e.g. Dad's 60th Birthday",
                      text: $eventName)
                .font(SBFont.body)
                .padding(14)
                .background(Color.sbIvory2)
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
                .onChange(of: eventName) { old, new in
                    if new != defaultedEventName { eventNameEdited = true }
                    if new.isEmpty { eventNameEdited = false }
                }

            sectionLabel(eventType == .wedding ? "WHEN'S THE BIG DAY?" : "WHEN?")
            DatePicker("Date", selection: $eventDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .font(SBFont.body)
                .tint(Color.sbGold)
                .onChange(of: eventDate) { _, _ in hasSetDate = true }

            sectionLabel("WHERE? (OPTIONAL)")
            SBVenueSearch(venueName: $venueName)

            Spacer(minLength: 40)
        }
    }

    // MARK: - Step 2: Guests

    private var guestsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 8) {
                Image(systemName: "person.2.fill").font(.system(size: 28)).foregroundStyle(Color.sbGoldDk)
                Text("Your guests").font(SBFont.displayMedium).foregroundStyle(Color.sbCharcoal)
                Text("Tell us how many people, then add them in your favourite way.")
                    .font(SBFont.body).foregroundStyle(Color.sbWarm).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            sectionLabel("EXPECTED GUESTS")
            guestCountPicker

            sectionLabel("ADD GUESTS")

            // CSV upload — gold pill button
            Button {
                csvImportError = nil
                showFilePicker = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upload CSV or Excel")
                            .font(SBFont.bodySemibold)
                        Text("Joy, Zola, The Knot, Eventbrite, generic CSV")
                            .font(SBFont.caption)
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .padding(14)
                .background(LinearGradient(colors: [Color.sbGold, Color.sbGoldDk], startPoint: .top, endPoint: .bottom))
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
            }
            .buttonStyle(.plain)

            if let csvImportError {
                Text(csvImportError).font(SBFont.caption).foregroundStyle(Color.sbError)
            }

            // Paste fallback
            HStack {
                Rectangle().fill(Color.sbLine2).frame(height: 1)
                Text("OR PASTE").font(SBFont.capsLabel).foregroundStyle(Color.sbWarm)
                Rectangle().fill(Color.sbLine2).frame(height: 1)
            }

            ZStack(alignment: .topLeading) {
                if guestListText.isEmpty {
                    Text("Sarah Chen, vegetarian\nJon Park\nMia Khalid, +1\n…")
                        .font(SBFont.body).foregroundStyle(Color.sbWarm2).padding(14)
                }
                TextEditor(text: $guestListText)
                    .font(SBFont.body).scrollContentBackground(.hidden).padding(8)
            }
            .frame(height: 140)
            .background(Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))

            if !detectedGuests.isEmpty {
                detectedSummary
            }

            Spacer(minLength: 40)
        }
    }

    private var detectedSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(detectedGuests.count) DETECTED")
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbGoldDk)
                if let detectedPlatform {
                    Text("· \(detectedPlatform)")
                        .font(SBFont.caption).foregroundStyle(Color.sbWarm)
                }
                Spacer()
            }
            // Quick stats
            HStack(spacing: 12) {
                detectedStat(value: "\(detectedGuests.filter { $0.rsvp == .yes }.count)", label: "RSVP'd Yes")
                detectedStat(value: "\(detectedPartiesCount)", label: "Parties")
                detectedStat(value: "\(detectedGuests.filter { ($0.dietaryTags ?? []).count > 0 || ($0.dietary ?? "").count > 0 }.count)", label: "Dietary")
                detectedStat(value: "\(detectedGuests.filter { $0.vip }.count)", label: "VIPs")
            }
            FlowLayout(spacing: 6) {
                ForEach(detectedGuests.prefix(20), id: \.id) { g in
                    Text(g.displayName)
                        .font(SBFont.caption)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.sbChampagne.opacity(0.6))
                        .clipShape(Capsule())
                }
                if detectedGuests.count > 20 {
                    Text("+\(detectedGuests.count - 20) more")
                        .font(SBFont.caption).foregroundStyle(Color.sbWarm)
                }
            }
        }
    }

    private func detectedStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(SBFont.bodySmallBold).foregroundStyle(Color.sbCharcoal)
            Text(label).font(SBFont.small).foregroundStyle(Color.sbWarm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.sbIvory2)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Step 3: Room setup

    private var roomSetupStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 8) {
                Image(systemName: "square.dashed").font(.system(size: 28)).foregroundStyle(Color.sbGoldDk)
                Text("Your room").font(SBFont.displayMedium).foregroundStyle(Color.sbCharcoal)
                Text("Pick a starting size and shape — you can refine on the canvas later.")
                    .font(SBFont.body).foregroundStyle(Color.sbWarm).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            sectionLabel("MEASUREMENTS")
            Picker("Unit", selection: $useMetric) {
                Text("Feet").tag(false)
                Text("Meters").tag(true)
            }
            .pickerStyle(.segmented)
            .tint(Color.sbGold)

            sectionLabel("ROOM SIZE")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(RoomPreset.allCases, id: \.self) { preset in
                    roomPresetCard(preset)
                }
            }

            sectionLabel("ROOM SHAPE")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(RoomShapeOption.allCases, id: \.self) { shape in
                    roomShapeButton(shape)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.sbGoldDk)
                Text("Floor plan upload, custom polygon tracing, and labelled zones are available from the canvas after creation.")
                    .font(SBFont.caption).foregroundStyle(Color.sbCharcoal2)
            }
            .padding(12)
            .background(Color.sbGold.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Spacer(minLength: 40)
        }
    }

    private func roomPresetCard(_ preset: RoomPreset) -> some View {
        let active = roomPreset == preset
        return Button {
            roomPreset = preset
            HapticEngine.selection()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.displayName).font(SBFont.bodySemibold).foregroundStyle(Color.sbCharcoal)
                Text(preset.guestRange).font(SBFont.caption).foregroundStyle(Color.sbWarm)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(active ? Color.sbChampagne.opacity(0.7) : Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
            .overlay(
                RoundedRectangle(cornerRadius: SBRadius.small)
                    .strokeBorder(active ? Color.sbGold : Color.sbLine2, lineWidth: active ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func roomShapeButton(_ shape: RoomShapeOption) -> some View {
        let active = roomShape == shape
        return Button {
            roomShape = shape
            HapticEngine.selection()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: shape.iconName).font(.system(size: 22))
                    .foregroundStyle(active ? Color.sbGoldDk : Color.sbCharcoal)
                Text(shape.displayName).font(SBFont.caption).foregroundStyle(Color.sbCharcoal)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(active ? Color.sbChampagne.opacity(0.7) : Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
            .overlay(
                RoundedRectangle(cornerRadius: SBRadius.small)
                    .strokeBorder(active ? Color.sbGold : Color.sbLine2, lineWidth: active ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 4: Tables & venue

    private var tablesStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 8) {
                Image(systemName: "tablecells").font(.system(size: 28)).foregroundStyle(Color.sbGoldDk)
                Text("Tables & venue items").font(SBFont.displayMedium).foregroundStyle(Color.sbCharcoal)
                Text("We'll auto-generate \(estimatedTableCount) tables. Tweak the style and add venue extras now or later.")
                    .font(SBFont.body).foregroundStyle(Color.sbWarm).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            sectionLabel("TABLE STYLE")
            HStack(spacing: 8) {
                ForEach(TableStyle.allCases, id: \.self) { tableStyleButton($0) }
            }

            sectionLabel("SEATS PER TABLE")
            seatsPerTablePicker

            if eventType == .wedding {
                sectionLabel("SPECIAL TABLES")
                Toggle(isOn: $includeHeadTable) {
                    Label("Include a Head Table", systemImage: "crown")
                        .font(SBFont.body)
                        .foregroundStyle(Color.sbCharcoal)
                }
                .tint(Color.sbGold)
                Toggle(isOn: $includeSweetheartTable) {
                    Label("Include a Sweetheart Table", systemImage: "heart")
                        .font(SBFont.body)
                        .foregroundStyle(Color.sbCharcoal)
                }
                .tint(Color.sbGold)
            }

            sectionLabel("VENUE ITEMS")
            Text("Tap to include — placed automatically. The full catalogue is in the canvas editor.")
                .font(SBFont.caption).foregroundStyle(Color.sbWarm)
            FlowLayout(spacing: 8) {
                ForEach(Self.venueItemCatalog, id: \.type) { item in
                    venueItemChip(type: item.type, name: item.name, icon: item.icon)
                }
            }

            Spacer(minLength: 40)
        }
    }

    private func tableStyleButton(_ style: TableStyle) -> some View {
        let active = tableStyle == style
        return Button {
            tableStyle = style
            // Reset seats to a sensible default for the new style.
            seatsPerTable = (style == .long) ? 12 : 8
            HapticEngine.selection()
        } label: {
            VStack(spacing: 4) {
                Text(style.displayName).font(SBFont.bodySemibold).foregroundStyle(Color.sbCharcoal)
                Text(style.subtitle).font(SBFont.caption).foregroundStyle(Color.sbWarm).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12).padding(.horizontal, 6)
            .background(active ? Color.sbChampagne.opacity(0.7) : Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
            .overlay(
                RoundedRectangle(cornerRadius: SBRadius.small)
                    .strokeBorder(active ? Color.sbGold : Color.sbLine2, lineWidth: active ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var seatsPerTablePicker: some View {
        if tableStyle == .long {
            // Long tables: more seats, slider 6-30 in steps of 2.
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Slider(value: Binding(get: { Double(seatsPerTable) },
                                          set: { seatsPerTable = max(6, Int($0 / 2.0) * 2) }),
                           in: 6...30, step: 2)
                        .tint(Color.sbGold)
                    Text("\(seatsPerTable)").font(SBFont.bodySemibold)
                        .frame(width: 32, alignment: .trailing).monospacedDigit()
                }
                Text("\(seatsPerTable / 2) seats per side").font(SBFont.caption).foregroundStyle(Color.sbWarm)
            }
        } else {
            HStack(spacing: 6) {
                ForEach([6, 8, 10, 12], id: \.self) { count in
                    let active = seatsPerTable == count
                    Button {
                        seatsPerTable = count
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
        }
    }

    private func venueItemChip(type: String, name: String, icon: String) -> some View {
        let active = venueItems.contains(type)
        return Button {
            if active { venueItems.remove(type) } else { venueItems.insert(type) }
            HapticEngine.selection()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .medium))
                Text(name).font(SBFont.caption)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .foregroundStyle(active ? Color.white : Color.sbCharcoal)
            .background(active ? Color.sbGold : Color.sbIvory2)
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(active ? Color.sbGoldDk : Color.sbLine2, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 5: Review

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 28)).foregroundStyle(Color.sbSage)
                Text("Almost there").font(SBFont.displayMedium).foregroundStyle(Color.sbCharcoal)
                Text("Review and tap Create — we'll seed your categories, rules, and table layout.")
                    .font(SBFont.body).foregroundStyle(Color.sbWarm).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 0) {
                summaryRow("Type", value: eventType.displayName)
                summaryRow("Name", value: resolvedEventName)
                if eventType == .wedding && (partner1Role != .unspecified || partner2Role != .unspecified) {
                    summaryRow("Couple", value: friendlyCoupleType)
                }
                if hasSetDate {
                    summaryRow("Date", value: eventDate.formatted(date: .abbreviated, time: .omitted))
                }
                if !venueName.isEmpty {
                    summaryRow("Venue", value: venueName)
                }
                summaryRow("Expected guests", value: "\(expectedGuests)")
                summaryRow("Room", value: "\(roomPreset.displayName) · \(roomShape.displayName)")
                summaryRow("Tables", value: "~\(estimatedTableCount) (\(tableStyle.displayName), \(seatsPerTable) seats each)")
                if !venueItems.isEmpty {
                    let names = Self.venueItemCatalog.filter { venueItems.contains($0.type) }.map(\.name).joined(separator: ", ")
                    summaryRow("Venue items", value: names)
                }
                summaryRow("Measurements", value: useMetric ? "Meters" : "Feet")
                if !detectedGuests.isEmpty {
                    summaryRow("Guests detected", value: "\(detectedGuests.count)", isLast: true)
                } else {
                    summaryRow("Guests", value: "Add later", isLast: true)
                }
            }
            .background(Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))

            Text("Floor plan upload, polygon tracing, and the full venue-item catalogue are accessible from the canvas after creation.")
                .font(SBFont.caption).foregroundStyle(Color.sbWarm).multilineTextAlignment(.center).padding(.horizontal, 8)

            Spacer(minLength: 40)
        }
    }

    private func summaryRow(_ label: String, value: String, isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label).font(SBFont.bodySmall).foregroundStyle(Color.sbWarm)
                Spacer()
                Text(value).font(SBFont.bodySmallBold).foregroundStyle(Color.sbCharcoal)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            if !isLast { Divider().background(Color.sbLine).padding(.horizontal, 14) }
        }
    }

    private var friendlyCoupleType: String {
        switch coupleType {
        case "bride_bride": return "Bride & Bride"
        case "groom_groom": return "Groom & Groom"
        default:            return "Bride & Groom"
        }
    }

    private var creatingStep: some View {
        VStack(spacing: 24) {
            Spacer()
            HoneycombLoader().frame(width: 180, height: 180)
            Text("Setting up your plan…").font(SBFont.bodySemibold).foregroundStyle(Color.sbCharcoal)
            Text("Categories, rules, table layout, venue items — preparing everything")
                .font(SBFont.caption).foregroundStyle(Color.sbWarm).multilineTextAlignment(.center).padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Bottom CTA

    private var bottomCTA: some View {
        VStack(spacing: 12) {
            if let errorMessage {
                Text(errorMessage).font(SBFont.caption).foregroundStyle(Color.sbError)
            }
            switch step {
            case 1:
                SBButton(title: "Continue", icon: "arrow.right", variant: .gold, fullWidth: true) {
                    withAnimation(.seatbee) { step = 2 }
                }
                .disabled(!step1Valid).opacity(step1Valid ? 1 : 0.5)
            case 2:
                if guestListText.isEmpty && detectedGuests.isEmpty {
                    SBButton(title: "Skip — add guests later", icon: "arrow.right", variant: .gold, fullWidth: true) {
                        withAnimation(.seatbee) { step = 3 }
                    }
                } else if detectedGuests.isEmpty && !guestListText.isEmpty {
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
                SBButton(title: "Continue", icon: "arrow.right", variant: .gold, fullWidth: true) {
                    withAnimation(.seatbee) { step = 4 }
                }
            case 4:
                SBButton(title: "Continue", icon: "arrow.right", variant: .gold, fullWidth: true) {
                    withAnimation(.seatbee) { step = 5 }
                }
            case 5:
                SBButton(title: "Create plan", icon: "sparkles", variant: .gold, fullWidth: true) {
                    finalizePlan()
                }
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(SBFont.capsLabel).foregroundStyle(Color.sbWarm).letterSpacing(1.5).padding(.top, 6)
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
                Text(type.subtitle).font(SBFont.caption).foregroundStyle(Color.sbWarm)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16).padding(.horizontal, 8)
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
                .font(SBFont.body).padding(14).background(Color.sbIvory2)
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
            binding.wrappedValue = active ? .unspecified : role
            HapticEngine.selection()
        } label: {
            Text(label)
                .font(SBFont.caption)
                .foregroundStyle(active ? Color.white : Color.sbCharcoal2)
                .padding(.horizontal, 12).padding(.vertical, 6)
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
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(active ? Color.sbGold : Color.sbIvory2)
                            .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                Text("Custom").font(SBFont.caption).foregroundStyle(Color.sbWarm)
                TextField("e.g. 175", text: $customGuestCount)
                    .keyboardType(.numberPad)
                    .font(SBFont.body)
                    .padding(8).background(Color.sbIvory2)
                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
                    .onChange(of: customGuestCount) { _, newValue in
                        if let n = Int(newValue), n > 0 { expectedGuests = n }
                    }
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
                detectedPartiesCount = countParties(in: detectedGuests)
                detectedPlatform = "AI parsed"
                HapticEngine.success()
            } catch {
                errorMessage = "Couldn't detect guests. You can still create the plan."
                HapticEngine.error()
            }
            isProcessing = false
        }
    }

    private func importCSVFromURL(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            csvImportError = "Couldn't access file"
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let result = GuestCSVParser.parse(text)
            if let err = result.error {
                csvImportError = err
                return
            }
            detectedGuests = result.guests
            detectedPlatform = result.detectedPlatform
            detectedPartiesCount = countParties(in: result.guests)
            csvImportError = nil
            HapticEngine.success()
            // Auto-bump expectedGuests if user hadn't customised it.
            if customGuestCount.isEmpty {
                expectedGuests = max(expectedGuests, result.guests.count)
            }
        } catch {
            csvImportError = "Couldn't read file: \(error.localizedDescription)"
        }
    }

    private func countParties(in guests: [Guest]) -> Int {
        Set(guests.compactMap(\.party).filter { !$0.isEmpty }).count
    }

    private func finalizePlan() {
        isCreating = true
        errorMessage = nil
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        Task {
            do {
                let coupleAutoGuests = buildCoupleGuests()
                let allGuests = coupleAutoGuests + detectedGuests
                let guestDTOs: [GuestDTO]? = allGuests.isEmpty ? nil : allGuests.map { g in
                    GuestDTO(
                        id: g.id, name: g.name, firstName: g.firstName, lastName: g.lastName,
                        email: g.email, categories: g.categories, dietary: g.dietary,
                        notes: g.notes, rsvp: g.rsvp.rawValue, side: g.side.rawValue, vip: g.vip,
                        accessibility: g.accessibility, plusOne: g.plusOne, party: g.party,
                        display: g.displayName, dietaryTags: g.dietaryTags, highChair: g.highChair,
                        isChild: g.isChild, groupIds: g.groupIds, isBride: g.isBride, isGroom: g.isGroom,
                        meal: g.meal.map { MealField($0) }, createdAt: g.guestCreatedAt
                    )
                }

                // Generate the table layout up-front so the new plan
                // arrives at the editor with everything in place.
                let (tableDTOs, objectDTOs) = buildLayout()

                var plan = try await appState.database.createPlan(
                    name: resolvedEventName,
                    eventType: eventType.rawValue,
                    eventDate: hasSetDate ? dateFormatter.string(from: eventDate) : nil,
                    venue: venueName.isEmpty ? nil : venueName,
                    guests: guestDTOs,
                    tables: tableDTOs.isEmpty ? nil : tableDTOs
                )

                let dim = roomPreset.dimensionsPx
                plan.roomWidth = dim.width
                plan.roomHeight = dim.height
                plan.roomShape = roomShape.rawValue
                plan.measurementUnit = useMetric ? "metric" : "imperial"
                plan.coupleType = eventType == .wedding ? coupleType : nil
                plan.hasSweetheartTable = eventType == .wedding && includeSweetheartTable
                plan.rules = buildInitialRules(coupleAutoGuests: coupleAutoGuests)
                plan.rawCategories = defaultCategoriesAsRaw(for: eventType)
                // Objects go into rawCategories' sibling — there's no
                // typed `objects` on iOS Plan; mutate by re-encoding via
                // a small helper. Easier path: SeatingPlan model has
                // `objects: [RoomObject]`. Build them here.
                plan.objects = objectDTOs.compactMap { dto in
                    RoomObject(
                        id: dto.id, type: dto.type ?? "object",
                        name: dto.name ?? "", x: dto.x ?? 0, y: dto.y ?? 0,
                        width: dto.width ?? 0, height: dto.height ?? 0, rotation: dto.rotation,
                        color: dto.color, category: dto.category,
                        icon: dto.icon, isObstacle: dto.isObstacle
                    )
                }

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

    /// Default categories (web parity App.jsx:3042-3075). 11 wedding / 6
    /// celebration. Users add custom categories from Categories sheet.
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
            name: name, firstName: nil, lastName: nil, email: nil,
            categories: [cat, "head_table", "sweetheart_table"],
            dietary: nil, notes: nil, rsvp: .yes,
            side: role == .bride ? .bride : .groom,
            vip: true, accessibility: nil, plusOne: nil, party: nil, display: name,
            dietaryTags: nil, highChair: nil, isChild: nil, groupIds: nil,
            isBride: role == .bride ? true : nil,
            isGroom: role == .groom ? true : nil,
            meal: nil, guestCreatedAt: nil
        )
    }

    private func buildInitialRules(coupleAutoGuests: [Guest]) -> [SeatingRule] {
        guard eventType == .wedding, coupleAutoGuests.count == 2 else { return [] }
        return [
            SeatingRule(
                id: "rule_couple_\(UUID().uuidString.prefix(8))",
                type: .seatAdjacent,
                guests: coupleAutoGuests.map(\.id),
                tableId: nil, weight: 100, hard: true, enabled: true,
                desc: "Couple seated adjacent", source: "onboarding"
            )
        ]
    }

    /// Generates initial table layout + venue object placement based on
    /// the user's choices in Steps 3+4. Mirrors the spirit of web's
    /// `generatePresetLayout()` (App.jsx:16423) — simplified for iOS.
    private func buildLayout() -> (tables: [TableDTO], objects: [ObjectDTO]) {
        let dim = roomPreset.dimensionsPx
        let regularCount = max(1, Int(ceil(Double(expectedGuests) / Double(seatsPerTable))))
        var tables: [TableDTO] = []

        // Layout grid for regular tables — centred on room. Uses 9-ft
        // cells (135 px) for round, wider for long.
        let cellW: Double = tableStyle == .long ? 200 : 135
        let cellH: Double = 135
        let cols = max(1, Int(floor((dim.width - 200) / cellW)))
        let rows = Int(ceil(Double(regularCount) / Double(cols)))
        let gridStartX = (dim.width - Double(cols) * cellW) / 2
        let gridStartY = max(220, (dim.height - Double(rows) * cellH) / 2)

        let colors = ["#9CAF88", "#D4A5A5", "#C9A961", "#A88843", "#8B8680"]

        for i in 0..<regularCount {
            let col = i % cols
            let row = i / cols
            let cx = gridStartX + Double(col) * cellW + cellW / 2
            let cy = gridStartY + Double(row) * cellH + cellH / 2
            let typeStr: String
            let width: Double?
            let height: Double?
            let diameter: Double?

            switch tableStyle {
            case .round:
                typeStr = "round"
                diameter = 90
                width = nil
                height = nil
            case .long:
                typeStr = "rect"
                diameter = nil
                width = 22.5 * Double(seatsPerTable / 2)
                height = 50
            case .mix:
                if i % 3 == 0 {
                    typeStr = "rect"
                    diameter = nil
                    width = 22.5 * Double(seatsPerTable / 2)
                    height = 50
                } else {
                    typeStr = "round"
                    diameter = 90
                    width = nil
                    height = nil
                }
            }

            tables.append(TableDTO(
                id: "tbl_\(UUID().uuidString.prefix(8))",
                name: "Table \(i + 1)", type: typeStr, seats: seatsPerTable,
                x: cx, y: cy, rotation: 0, locked: false,
                color: colors[i % colors.count],
                width: width, height: height, diameter: diameter,
                sweetShape: nil, oneSide: nil, notes: nil
            ))
        }

        if eventType == .wedding {
            if includeHeadTable {
                tables.append(TableDTO(
                    id: "tbl_head_\(UUID().uuidString.prefix(6))",
                    name: "Head Table", type: "head", seats: 8,
                    x: dim.width / 2, y: 100, rotation: 0, locked: false,
                    color: "#C9A961",
                    width: 280, height: 50, diameter: nil,
                    sweetShape: nil, oneSide: true, notes: nil
                ))
            }
            if includeSweetheartTable {
                tables.append(TableDTO(
                    id: "tbl_sweet_\(UUID().uuidString.prefix(6))",
                    name: "Sweetheart", type: "sweetheart", seats: 2,
                    x: dim.width / 2, y: 180, rotation: 0, locked: false,
                    color: "#D4A5A5",
                    width: 100, height: 60, diameter: nil,
                    sweetShape: "heart", oneSide: nil, notes: nil
                ))
            }
        }

        // Default venue-object positions — cardinal layout around the
        // edges so they don't conflict with the table grid.
        var objects: [ObjectDTO] = []
        let objectPositions: [String: (x: Double, y: Double, w: Double, h: Double, color: String)] = [
            "entrance": (60,                   dim.height - 80,  80, 50, "#2D2D2D"),
            "bar":      (dim.width - 140,      120,              120, 40, "#8B8680"),
            "dj":       (140,                  120,              80, 60, "#A88843"),
            "stage":    (dim.width / 2 - 100,  dim.height - 100, 200, 60, "#A88843"),
            "dance":    (dim.width - 220,      dim.height / 2,   180, 180, "#F7E7CE"),
            "cake":     (60,                   dim.height / 2,   80, 60, "#D4A5A5"),
            "gift":     (dim.width - 100,      dim.height - 80,  60, 50, "#C9A961"),
            "photo":    (dim.width / 2 + 200,  120,              80, 80, "#9CAF88"),
        ]
        for type in venueItems {
            guard let pos = objectPositions[type] else { continue }
            let item = Self.venueItemCatalog.first { $0.type == type }
            objects.append(ObjectDTO(
                id: "obj_\(type)_\(UUID().uuidString.prefix(6))",
                type: type, name: item?.name ?? type.capitalized,
                x: pos.x, y: pos.y, width: pos.w, height: pos.h, rotation: 0,
                color: pos.color, category: nil, icon: item?.icon, isObstacle: false
            ))
        }

        return (tables, objects)
    }
}

#Preview {
    OnboardingView()
        .environment(AppState())
}
