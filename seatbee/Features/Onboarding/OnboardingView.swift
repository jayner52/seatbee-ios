import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import PDFKit

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
    /// Single source of truth for the iOS document picker. Two
/// `.fileImporter` modifiers in the same view tree silently conflict —
/// only the outer one would present, so the floor-plan Files button
/// stayed dead. We dispatch on this enum so one importer handles both.
    @State private var activeFileImport: FileImportMode? = nil
    @State private var csvImportError: String?
    /// Pre-headed CSV template generated for the current event type so
    /// users without an export from Joy/Zola/etc. can download a starter
    /// file, fill in their guests, and upload. Regenerated when
    /// eventType flips.
    @State private var csvTemplateURL: URL?

    // MARK: - Step 3
    @State private var useMetric = false
    @State private var roomPreset: RoomPreset? = .medium    // nil when user types custom dims
    @State private var roomShape: RoomShapeOption = .rect
    @State private var roomWidthFt: Double = 80
    @State private var roomHeightFt: Double = 60
    @State private var roomFlipH = false
    @State private var roomFlipV = false
    @State private var floorPlanImage: UIImage? = nil
    @State private var showFloorPlanPhotoPicker = false
    @State private var floorPlanPickerItem: PhotosPickerItem? = nil
    /// Polygon traced over the floor plan. Empty until the user
    /// applies a trace; then writes to plan.customRoomPoints +
    /// roomShape = "custom" on finalize.
    @State private var tracedPoints: [RoomPoint] = []
    @State private var showTraceSheet = false

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

    enum FileImportMode: Equatable { case csv, floorPlan }

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
        /// Same dims expressed in feet (15 px = 1 ft). Used by the
        /// preset cards and to seed roomWidthFt/roomHeightFt.
        var dimensionsFt: (w: Double, h: Double) {
            let dim = dimensionsPx
            return (dim.width / 15, dim.height / 15)
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

    /// 8 shape options — matches RoomSetupSheet's `shapes` array exactly
    /// so onboarding and the canvas room editor pick from the same set.
    /// "custom" stores the choice; the actual polygon trace happens in
    /// the canvas RoomSetupSheet after creation.
    enum RoomShapeOption: String, CaseIterable {
        case rect, l, lRev = "l_rev", t, u, oval, circle, custom
        var displayName: String {
            switch self {
            case .rect:   return "Rectangle"
            case .l:      return "L-Shape"
            case .lRev:   return "L-Reversed"
            case .t:      return "T-Shape"
            case .u:      return "U-Shape"
            case .oval:   return "Oval"
            case .circle: return "Circle"
            case .custom: return "Custom"
            }
        }
        var iconName: String {
            switch self {
            case .rect:   return "rectangle"
            case .l, .lRev: return "l.rectangle.roundedbottom"
            case .t:      return "t.square"
            case .u:      return "u.square"
            case .oval:   return "oval"
            case .circle: return "circle"
            case .custom: return "scribble.variable"
            }
        }
        var iconShouldMirror: Bool { self == .lRev }
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

    /// User's room dims converted to canvas px. 15 px/ft is the web's
/// standard scale; metric converts via 3.28084 ft per metre first.
    private var currentRoomPx: (width: Double, height: Double) {
        let pxPerUnit: Double = useMetric ? (15.0 * 3.28084) : 15.0
        return (max(roomWidthFt, 1) * pxPerUnit, max(roomHeightFt, 1) * pxPerUnit)
    }

    /// Pre-fill the dimension fields from a freshly-traced polygon's
    /// bounding box, but ONLY when the user is still on the default
    /// preset values (80×60). Manual edits to W or H stay sticky —
    /// we never silently overwrite typed input.
    private func autoFillDimensionsFromTrace(_ points: [RoomPoint]) {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return }
        let widthPx  = max(1.0, maxX - minX)
        let heightPx = max(1.0, maxY - minY)
        let pxPerUnit: Double = useMetric ? (15.0 * 3.28084) : 15.0
        let widthUnit = (widthPx / pxPerUnit).rounded()
        let heightUnit = (heightPx / pxPerUnit).rounded()
        // 80 / 60 are the seed defaults set in the View. If the user
        // already changed them, treat that as intent and bail.
        if abs(roomWidthFt - 80) < 0.01 {
            roomWidthFt = max(1, widthUnit)
        }
        if abs(roomHeightFt - 60) < 0.01 {
            roomHeightFt = max(1, heightUnit)
        }
    }

    private var roomSummaryLabel: String {
        let unit = useMetric ? "m" : "ft"
        let w = Int(roomWidthFt.rounded())
        let h = Int(roomHeightFt.rounded())
        let dims = "\(w)×\(h)\(unit)"
        if let preset = roomPreset {
            return "\(preset.displayName) · \(roomShape.displayName) · \(dims)"
        }
        return "\(roomShape.displayName) · \(dims)"
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
                        Button { advance(to: step - 1) } label: {
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
                isPresented: Binding(
                    get: { activeFileImport != nil },
                    set: { if !$0 { activeFileImport = nil } }
                ),
                allowedContentTypes: activeFileImport == .floorPlan
                    ? [.image, .pdf]
                    : [.commaSeparatedText, .plainText, .data]
            ) { result in
                let mode = activeFileImport
                activeFileImport = nil
                switch result {
                case .success(let url):
                    if mode == .floorPlan {
                        loadFloorPlanFromURL(url)
                    } else {
                        importCSVFromURL(url)
                    }
                case .failure(let error):
                    if mode != .floorPlan {
                        csvImportError = error.localizedDescription
                    }
                }
            }
        }
        .onChange(of: defaultedEventName) { _, newValue in
            // Only push the auto-fill into the field while the user
            // hasn't explicitly edited. Once they type, defaultedEventName
            // already returns their value so this is a no-op.
            if !eventNameEdited { eventName = newValue }
        }
        // Onboarding lives inside AppRouter's fullScreenCover, which
        // visually covers the upgrade sheet attached on AppRouter. Bind
        // the same flag locally so tapping a tile's Buy button actually
        // presents UpgradeView (StoreKit IAP) — Apple flagged this as a
        // non-functioning Buy button in App Review (Guideline 2.1(b)).
        .sheet(
            isPresented: Binding(
                get: { appState.showUpgrade },
                set: { appState.showUpgrade = $0 }
            )
        ) {
            UpgradeView().environment(appState)
        }
        .onChange(of: appState.showUpgrade) { _, _ in }
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

            // Optional pass-application section. Mirrors web's step-1
            // pass picker (App.jsx OnboardingWizard ~line 20272). User
            // can pick a pass they already own, or tap a Buy tile to
            // bounce to web pricing. Skipping is implicit — they
            // continue without selecting and ship a free plan.
            passApplicationSection

            Spacer(minLength: 40)
        }
    }

    // MARK: - Pass picker (Step 1)
    //
    // Three tier tiles. For tiers the user owns at least one of, the
    // tile is selectable (tap to set pendingPassId); for tiers with
    // no inventory, the tile shows a "Buy" action that opens web
    // pricing (Phase 2 / Apple IAP replaces this later — Shayan).
    // Selection is stored as a pass ID; we re-derive the displayed
    // tier from `userPasses` whenever rendering. Tapping the
    // currently-selected pass clears the selection.

    private var passApplicationSection: some View {
        // Event passes are retired — onboarding no longer offers pass
        // application. The model is simply Free vs Seatbee Pro; the
        // large-room nudge below handles the upsell.
        EmptyView()
    }

    @ViewBuilder
    private func passTierTile(_ tier: PlanTier, available: [EventPass]) -> some View {
        // Legacy — event passes are retired. This view is dead code kept
        // to avoid breaking the passApplicationSection (which renders EmptyView).
        EmptyView()
    }

    // MARK: - Large-room contextual nudge (Step 3)

    @ViewBuilder
    private var largeRoomPassNudge: some View {
        let isLargeRoom = roomPreset == .large
            || roomPreset == .ballroom
            || roomPreset == .grand

        if isLargeRoom {
            HStack(alignment: .top, spacing: 10) {
                Image("SeatbeeLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(largeRoomPromptTitle)
                        .font(SBFont.bodySmallBold)
                        .foregroundStyle(Color.sbCharcoal)
                    Text(largeRoomPromptBody)
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbCharcoal2)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Upgrade to Seatbee Pro") {
                        appState.showUpgrade = true
                    }
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(Color.sbGoldDk)
                    .padding(.top, 2)
                }
                Spacer()
            }
            .padding(12)
            .background(Color.sbGold.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var largeRoomPromptTitle: String {
        switch roomPreset {
        case .ballroom, .grand: return "Hosting a big crowd?"
        default:                return "Seating more than 50 guests?"
        }
    }

    private var largeRoomPromptBody: String {
        // Free plans cap at 50 seated guests; Seatbee Pro ($9.99/mo) seats
        // up to 1,000 and unlocks AI seating. Big-room presets warrant a
        // stronger nudge.
        switch roomPreset {
        case .grand, .ballroom:
            return "Seatbee Pro seats up to 1,000 with AI seating. Free plans cap at 50 seated guests."
        default:
            return "Seatbee Pro seats up to 1,000 with AI seating, for $9.99/mo. Free plans cap at 50 seated guests."
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
                activeFileImport = .csv
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

            // Template download — for users without an existing export.
            // Pre-filled with all the columns GuestCSVParser recognises
            // and 2 sample rows so they know the shape.
            if let csvTemplateURL {
                ShareLink(item: csvTemplateURL) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Download CSV template")
                            .font(SBFont.caption)
                    }
                    .foregroundStyle(Color.sbGoldDk)
                }
            }

            // Paste fallback
            HStack {
                Rectangle().fill(Color.sbLine2).frame(height: 1)
                Text("OR PASTE").font(SBFont.capsLabel).foregroundStyle(Color.sbWarm)
                Rectangle().fill(Color.sbLine2).frame(height: 1)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $guestListText)
                    .font(SBFont.body).scrollContentBackground(.hidden).padding(8)
                    .onChange(of: guestListText) { _, _ in parsePastedGuests() }
                if guestListText.isEmpty {
                    // Two-line example: a vanilla name and a name + dietary
                    // note. The "+1" example was removed because Seatbee
                    // treats every guest as a real entry — plus-ones are
                    // their own row, not a flag.
                    Text("Sarah Chen, vegetarian\nJon Park\nAmir Patel, gluten-free\n…")
                        .font(SBFont.body).foregroundStyle(Color.sbWarm2)
                        .padding(.horizontal, 14).padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 140)
            .background(Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))

            // Inline syntax hint — discoverability for the dietary-after-
            // comma feature. Meals / VIP / child / party stay in the
            // post-paste editor (too many inline fields = parse ambiguity).
            HStack(spacing: 4) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.sbGoldDk)
                Text("Tip: add a comma + dietary note (e.g. \"Sarah Chen, vegetarian\" or \"Sarah Chen, GF\"). Add meals and parties after.")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !detectedGuests.isEmpty {
                detectedSummary
            }

            Spacer(minLength: 40)
        }
        .task(id: eventType) { regenerateCSVTemplate() }
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
            // Quick stats — only show tiles with non-zero counts so the
            // paste path doesn't display "0 RSVPs / 0 Parties / 0 …" when
            // those fields just weren't in the input.
            let stats: [(value: Int, label: String)] = [
                (detectedGuests.filter { $0.rsvp == .yes }.count,            "RSVP'd Yes"),
                (detectedPartiesCount,                                        "Parties"),
                (detectedGuests.filter { ($0.dietaryTags ?? []).count > 0
                                        || ($0.dietary ?? "").count > 0 }.count, "Dietary"),
                (detectedGuests.filter { $0.vip }.count,                      "VIPs"),
            ].filter { $0.value > 0 }
            if !stats.isEmpty {
                HStack(spacing: 12) {
                    ForEach(stats, id: \.label) { stat in
                        detectedStat(value: "\(stat.value)", label: stat.label)
                    }
                }
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

    /// Step 3 mirrors the canvas `RoomSetupSheet` design: quick presets,
    /// 8-shape grid, flip H/V, dimensions inputs, photo + file pickers
    /// for floor-plan upload. Custom polygon tracing happens in the
    /// canvas RoomSetupSheet after the plan is created.
    private var roomSetupStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(spacing: 8) {
                Image(systemName: "square.dashed").font(.system(size: 28)).foregroundStyle(Color.sbGoldDk)
                Text("Your room").font(SBFont.displayMedium).foregroundStyle(Color.sbCharcoal)
                Text("Pick a starting size + shape, or upload a floor plan to trace later in the canvas.")
                    .font(SBFont.body).foregroundStyle(Color.sbWarm).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            sectionLabel("QUICK PRESETS")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(RoomPreset.allCases, id: \.self) { preset in
                    roomPresetCard(preset)
                }
            }

            // Soft contextual upsell — fires when the user picks a
            // large/grand room AND hasn't already selected a pass on
            // step 1. Mirrors web's same-step nudge (App.jsx ~line
            // 20757-20792) and is intentionally a suggestion, not a
            // gate. The "Apply a pass" button bumps them back to
            // step 1 if they own one; otherwise routes to web pricing.
            largeRoomPassNudge

            sectionLabel("ROOM SHAPE")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(RoomShapeOption.allCases, id: \.self) { shape in
                    roomShapeButton(shape)
                }
            }

            if roomShape == .custom {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(Color.sbGoldDk)
                    Text("Trace your custom shape from the canvas after creation. We'll start with a rectangle.")
                        .font(SBFont.caption).foregroundStyle(Color.sbCharcoal2)
                }
                .padding(12)
                .background(Color.sbGold.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            sectionLabel("ORIENTATION")
            HStack(spacing: 8) {
                flipButton("Flip H", icon: "arrow.left.and.right", isOn: $roomFlipH)
                flipButton("Flip V", icon: "arrow.up.and.down", isOn: $roomFlipV)
            }

            sectionLabel("DIMENSIONS")
            HStack(spacing: 8) {
                dimensionField(label: "W", value: $roomWidthFt)
                Text("×").font(SBFont.bodySemibold).foregroundStyle(Color.sbWarm)
                dimensionField(label: "H", value: $roomHeightFt)
            }
            HStack {
                Text("Use metric (meters)")
                    .font(SBFont.bodySmall).foregroundStyle(Color.sbCharcoal)
                Spacer()
                Toggle("", isOn: $useMetric).labelsHidden().tint(Color.sbGold)
            }

            sectionLabel("FLOOR PLAN (OPTIONAL)")
            HStack(spacing: 8) {
                Button {
                    showFloorPlanPhotoPicker = true
                } label: {
                    floorPlanPickerLabel(icon: "photo.on.rectangle", text: "Photos")
                }
                .buttonStyle(.plain)
                Button {
                    activeFileImport = .floorPlan
                } label: {
                    floorPlanPickerLabel(icon: "doc.badge.plus", text: "Files / PDF")
                }
                .buttonStyle(.plain)
            }
            Text("Pick a floor plan from your photo library or a PDF / image from Files. You can trace its outline from the canvas after creation.")
                .font(SBFont.caption).foregroundStyle(Color.sbWarm)

            if let img = floorPlanImage {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: img).resizable().scaledToFit()
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
                    Button {
                        floorPlanImage = nil
                        floorPlanPickerItem = nil
                        tracedPoints = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.white)
                            .background(Circle().fill(Color.sbCharcoal.opacity(0.6)))
                    }
                    .padding(8)
                }
            }

            // Trace CTA — visible when there's something to trace against
            // (uploaded plan) OR the user picked the Custom shape.
            if floorPlanImage != nil || roomShape == .custom {
                Button {
                    showTraceSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "scribble.variable")
                        Text(tracedPoints.isEmpty ? "Trace floor plan" : "Edit traced shape (\(tracedPoints.count) corners)")
                            .font(SBFont.bodySemibold)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color.sbGoldDk)
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(Color.sbChampagne.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
                }
                .buttonStyle(.plain)
                if !tracedPoints.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.sbSage)
                        Text("Custom shape saved — finalise on the next steps.")
                            .font(SBFont.caption).foregroundStyle(Color.sbCharcoal2)
                    }
                }
            }

            Spacer(minLength: 40)
        }
        .sheet(isPresented: $showTraceSheet) {
            let dim = currentRoomPx
            let seedPoints: [RoomPoint] = tracedPoints.isEmpty
                ? RoomShapePresets.defaultPoints(
                    shape: roomShape == .custom ? "rect" : roomShape.rawValue,
                    width: dim.width, height: dim.height)
                : tracedPoints
            TraceShapeSheet(
                initialPoints: seedPoints,
                initialFlipH: roomFlipH,
                initialFlipV: roomFlipV,
                currentShape: roomShape == .custom ? "CUSTOM" : roomShape.displayName.uppercased(),
                roomWidth: dim.width,
                roomHeight: dim.height,
                measurementUnit: useMetric ? "metric" : "imperial",
                floorPlanImage: floorPlanImage
            ) { newPoints, newFlipH, newFlipV in
                tracedPoints = newPoints
                roomFlipH = newFlipH
                roomFlipV = newFlipV
                roomShape = .custom
                // Auto-fill dimensions from the traced polygon's
                // bounding box, but only if the user hasn't already
                // typed values — never overwrite manual input. Web
                // does the same after upload + trace.
                if newPoints.count >= 3 {
                    autoFillDimensionsFromTrace(newPoints)
                }
                HapticEngine.success()
            }
        }
        .photosPicker(isPresented: $showFloorPlanPhotoPicker, selection: $floorPlanPickerItem, matching: .images)
        .onChange(of: floorPlanPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run { floorPlanImage = img }
                }
            }
        }
    }

    private func roomPresetCard(_ preset: RoomPreset) -> some View {
        let active = roomPreset == preset
        let dim = preset.dimensionsFt
        let unitSuffix = useMetric ? "m" : "ft"
        let displayW = useMetric ? Int((dim.w / 3.28084).rounded()) : Int(dim.w)
        let displayH = useMetric ? Int((dim.h / 3.28084).rounded()) : Int(dim.h)
        return Button {
            roomPreset = preset
            roomShape = .rect      // presets imply rectangle
            roomWidthFt = dim.w
            roomHeightFt = dim.h
            HapticEngine.selection()
        } label: {
            VStack(spacing: 4) {
                Text(preset.displayName).font(SBFont.bodySmallBold).foregroundStyle(Color.sbCharcoal)
                Text("\(displayW)×\(displayH)\(unitSuffix)")
                    .font(SBFont.caption).foregroundStyle(Color.sbWarm)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
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
                Image(systemName: shape.iconName)
                    .font(.system(size: 22))
                    .foregroundStyle(active ? Color.sbGoldDk : Color.sbCharcoal)
                    .scaleEffect(x: shape.iconShouldMirror ? -1 : 1, y: 1)
                Text(shape.displayName)
                    .font(SBFont.small)
                    .foregroundStyle(Color.sbCharcoal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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

    private func flipButton(_ label: String, icon: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            HapticEngine.selection()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(label).font(SBFont.bodySemibold)
            }
            .foregroundStyle(isOn.wrappedValue ? Color.sbGoldDk : Color.sbCharcoal)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isOn.wrappedValue ? Color.sbChampagne.opacity(0.7) : Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
        }
        .buttonStyle(.plain)
    }

    private func dimensionField(label: String, value: Binding<Double>) -> some View {
        let unitSuffix = useMetric ? "m" : "ft"
        return HStack(spacing: 6) {
            Text(label).font(SBFont.capsLabel).foregroundStyle(Color.sbWarm)
            TextField("0", value: value, format: .number.precision(.fractionLength(0)))
                .keyboardType(.numberPad)
                .font(SBFont.bodySemibold)
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color.sbIvory2)
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
                .onChange(of: value.wrappedValue) { _, _ in
                    // User typing a custom value clears the active preset
                    roomPreset = nil
                }
            Text(unitSuffix).font(SBFont.caption).foregroundStyle(Color.sbWarm)
        }
    }

    private func floorPlanPickerLabel(icon: String, text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(Color.sbGoldDk)
            Text(text).font(SBFont.bodySemibold).foregroundStyle(Color.sbCharcoal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .overlay(
            RoundedRectangle(cornerRadius: SBRadius.button)
                .strokeBorder(Color.sbWarm2, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        )
    }

    private func loadFloorPlanFromURL(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        if let data = try? Data(contentsOf: url) {
            // Image first; fall back to PDF first-page render.
            if let img = UIImage(data: data) {
                floorPlanImage = img
                return
            }
            if let pdf = PDFDocument(data: data), let page = pdf.page(at: 0) {
                let bounds = page.bounds(for: .mediaBox)
                let renderer = UIGraphicsImageRenderer(size: bounds.size)
                let img = renderer.image { ctx in
                    UIColor.white.setFill()
                    ctx.fill(bounds)
                    ctx.cgContext.translateBy(x: 0, y: bounds.size.height)
                    ctx.cgContext.scaleBy(x: 1, y: -1)
                    page.draw(with: .mediaBox, to: ctx.cgContext)
                }
                floorPlanImage = img
            }
        }
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
                summaryRow("Room", value: roomSummaryLabel)
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
                    advance(to: 2)
                }
                .disabled(!step1Valid).opacity(step1Valid ? 1 : 0.5)
            case 2:
                let title = detectedGuests.isEmpty
                    ? "Skip — add guests later"
                    : "Continue with \(detectedGuests.count) guest\(detectedGuests.count == 1 ? "" : "s")"
                SBButton(title: title, icon: "arrow.right", variant: .gold, fullWidth: true) {
                    advance(to: 3)
                }
            case 3:
                SBButton(title: "Continue", icon: "arrow.right", variant: .gold, fullWidth: true) {
                    advance(to: 4)
                }
            case 4:
                SBButton(title: "Continue", icon: "arrow.right", variant: .gold, fullWidth: true) {
                    advance(to: 5)
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

    /// Step transition with stale-error cleanup so messages from a
    /// previous step (like "Couldn't read CSV") don't bleed across.
    private func advance(to next: Int) {
        errorMessage = nil
        csvImportError = nil
        withAnimation(.seatbee) { step = next }
    }

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

    /// Parse pasted guest text. Delegates to
    /// `GuestCSVParser.parseFlexible` so the same paste experience
    /// works on the standalone Import sheet too — header-row CSV →
    /// full parser; plain "Name, dietary" lines → one guest per line.
    /// Runs synchronously on every text change.
    private func parsePastedGuests() {
        let result = GuestCSVParser.parseFlexible(guestListText)
        detectedGuests = result.guests
        detectedPartiesCount = countParties(in: result.guests)
        detectedPlatform = result.guests.isEmpty ? nil : result.detectedPlatform
    }

    /// Web parity (App.jsx:3100 CSV_TEMPLATES). Wedding mirrors web's
    /// Writes the current event type's template to the temp dir and
    /// caches the URL for ShareLink. Body + filename live on
    /// `GuestCSVParser` so the standalone Import sheet can reuse the
    /// same templates.
    private func regenerateCSVTemplate() {
        let templateType: GuestCSVParser.TemplateType =
            eventType == .wedding ? .wedding : .general
        csvTemplateURL = GuestCSVParser.writeCSVTemplate(for: templateType)
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

                let dim = currentRoomPx
                plan.roomWidth = dim.width
                plan.roomHeight = dim.height
                plan.roomShape = roomShape.rawValue
                plan.roomFlipH = roomFlipH
                plan.roomFlipV = roomFlipV
                plan.measurementUnit = useMetric ? "metric" : "imperial"
                plan.coupleType = eventType == .wedding ? coupleType : nil
                plan.hasSweetheartTable = eventType == .wedding && includeSweetheartTable
                plan.rules = buildInitialRules(coupleAutoGuests: coupleAutoGuests)
                plan.rawCategories = defaultCategoriesAsRaw(for: eventType)
                if let img = floorPlanImage,
                   let png = img.pngData() {
                    let b64 = png.base64EncodedString()
                    plan.rawFloorPlanImage = AnyCodable("data:image/png;base64,\(b64)")
                }
                if tracedPoints.count >= 3 {
                    plan.customRoomPoints = tracedPoints
                    plan.roomShape = "custom"
                }
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
        // Couples get exactly one seating-directive category, mirroring
        // web (App.jsx:19816). Sweetheart wins when the user opted in
        // for a sweetheart table — that's where the couple sits. Head
        // Table is the fallback for couples who'd rather sit with the
        // wider VIP set. Tagging both was producing a redundant chart
        // row on the SEATING SNAPSHOT and (until cddb38c on web)
        // letting the head-table phase swallow the couple before
        // the sweetheart phase ran.
        let seatTag: String
        if includeSweetheartTable {
            seatTag = "sweetheart_table"
        } else if includeHeadTable {
            seatTag = "head_table"
        } else {
            seatTag = ""
        }
        var categories = [cat]
        if !seatTag.isEmpty { categories.append(seatTag) }
        // Split the entered name so web's firstName / lastName columns
        // are populated from the start. Without this the couple is
        // born with name="Adam Williams" but firstName/lastName=nil,
        // which web's contact-card UI treats as an unstructured name.
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: " ", maxSplits: 1)
        let first: String? = parts.first.map(String.init)
        let last: String? = parts.count > 1 ? String(parts.last ?? "") : nil
        return Guest(
            id: "guest_\(cat)_\(UUID().uuidString.prefix(8))",
            name: trimmed, firstName: first, lastName: last, email: nil,
            categories: categories,
            dietary: nil, notes: nil, rsvp: .yes,
            side: role == .bride ? .bride : .groom,
            vip: true, accessibility: nil, plusOne: nil, party: nil, display: trimmed,
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
        let dim = currentRoomPx
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

        // Web parity (App.jsx atmospheric redesign ad49273): all seeded
        // tables default to gold so the canvas reads as a unified atmospheric
        // layout. Users can re-tint individual tables from the drawer.
        let colors = ["#C9A961"]

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
                color: pos.color, category: nil, icon: item?.icon, isObstacle: false, locked: nil
            ))
        }

        return (tables, objects)
    }
}

#Preview {
    OnboardingView()
        .environment(AppState())
}
