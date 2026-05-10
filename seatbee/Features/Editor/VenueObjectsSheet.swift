import SwiftUI

// MARK: - Venue object catalog (web parity)
//
// Mirrors `VENUE_OBJECTS` in `src/App.jsx` line 2604. 93 entries across 8
// categories. Icon names are web-style (e.g. `"music"`, `"glass"`) so iOS
// and web persist the same string on `RoomObject.icon`. The SF Symbol
// equivalents are resolved at render time via `VenueIconMap`.
//
// Width/height/min/max are in the same px space as web (15 px = 1 ft
// imperial; metric conversion happens at render via `RoomScale`). When
// web's `VENUE_OBJECTS` array changes, copy fields verbatim — drift
// causes silent shape corruption on round-trip.

struct VenueObjectSize {
    let label: String
    let w: Double
    let h: Double
}

struct VenueObjectDef {
    let type: String
    let name: String
    let icon: String          // web-style name; resolved via VenueIconMap
    let color: String
    let category: VenueObjectCategory
    let width: Double         // default w on create
    let height: Double        // default h on create
    let minW: Double
    let maxW: Double
    let minH: Double
    let maxH: Double
    let sizes: [VenueObjectSize]?  // explicit presets when web defines them
    let isObstacle: Bool

    init(_ category: VenueObjectCategory, type: String, name: String, icon: String, color: String,
         width: Double, height: Double,
         minW: Double? = nil, maxW: Double? = nil, minH: Double? = nil, maxH: Double? = nil,
         sizes: [VenueObjectSize]? = nil, isObstacle: Bool = false) {
        self.type = type; self.name = name; self.icon = icon; self.color = color
        self.category = category
        self.width = width; self.height = height
        // Sensible default bounds when web doesn't specify them: ½× default
        // up to 3× default. EditVenueObjectSheet clamps user input to these.
        self.minW = minW ?? max(20, width * 0.5)
        self.maxW = maxW ?? width * 3
        self.minH = minH ?? max(20, height * 0.5)
        self.maxH = maxH ?? height * 3
        self.sizes = sizes; self.isObstacle = isObstacle
    }
}

enum VenueObjectCategory: String, CaseIterable {
    case entertainment, food, services, photo, ceremony, av, tradeshow, structure

    var displayName: String {
        switch self {
        case .entertainment: return "Entertainment & Music"
        case .food:          return "Food & Beverage"
        case .services:      return "Guest Services"
        case .photo:         return "Photo & Memories"
        case .ceremony:      return "Ceremony & Decor"
        case .av:            return "A/V & Tech"
        case .tradeshow:     return "Tradeshow & Expo"
        case .structure:     return "Venue Structure"
        }
    }
}

let venueObjectTypes: [VenueObjectDef] = [
    // Entertainment & Music — 7 items
    .init(.entertainment, type: "dance", name: "Dance Floor", icon: "music", color: "#EDE0C4",
          width: 180, height: 180, minW: 120, maxW: 900, minH: 120, maxH: 900,
          sizes: [
            .init(label: "Small",  w: 120, h: 120),
            .init(label: "Medium", w: 180, h: 180),
            .init(label: "Large",  w: 270, h: 270),
            .init(label: "XL",     w: 360, h: 360),
          ]),
    .init(.entertainment, type: "stage",     name: "Stage",            icon: "star",       color: "#D4A5A5",
          width: 160, height: 60, minW: 100, maxW: 1500, minH: 40, maxH: 600,
          sizes: [
            // Without explicit sizes the default fallback is
            // Small=min, Medium=default, Large=max — and Large at
            // (1500×600 px) ended up as 100×40 ft, a wild jump from
            // Medium's 10.7×4 ft. min/max stay generous for manual
            // entry; the presets are the realistic stage sizes
            // people actually want from a one-tap pick.
            .init(label: "Small",  w: 100, h: 40),   // 6.7×2.7ft — small platform
            .init(label: "Medium", w: 160, h: 60),   // 10.7×4ft — ceremony
            .init(label: "Large",  w: 240, h: 90),   // 16×6ft — band stage
            .init(label: "XL",     w: 360, h: 120),  // 24×8ft — concert
          ]),
    .init(.entertainment, type: "dj",        name: "DJ Booth",         icon: "headphones", color: "#2D2D2D", width: 80,  height: 50, minW: 60,  maxW: 150,  minH: 40, maxH: 100),
    .init(.entertainment, type: "band",      name: "Band Area",        icon: "music",      color: "#8B9DC3", width: 200, height: 100),
    .init(.entertainment, type: "piano",     name: "Piano",            icon: "music",      color: "#2D2D2D", width: 80,  height: 50),
    .init(.entertainment, type: "speaker",   name: "Speaker",          icon: "volume",     color: "#2D2D2D", width: 30,  height: 30),
    .init(.entertainment, type: "mic_stand", name: "Microphone Stand", icon: "mic",        color: "#6b655c", width: 20,  height: 20),

    // Food & Beverage — 10 items
    .init(.food, type: "bar", name: "Bar", icon: "glass", color: "#8B8680",
          width: 180, height: 45, minW: 60, maxW: 600, minH: 30, maxH: 120,
          sizes: [
            .init(label: "Small",  w: 90,  h: 30),
            .init(label: "Medium", w: 180, h: 45),
            .init(label: "Large",  w: 300, h: 60),
          ]),
    .init(.food, type: "buffet",        name: "Buffet Table",      icon: "list",    color: "#C4A882", width: 180, height: 50),
    .init(.food, type: "catering",      name: "Catering Station",  icon: "list",    color: "#9CAF88", width: 80,  height: 50),
    .init(.food, type: "cake",          name: "Cake Table",        icon: "cake",    color: "#D4A5A5", width: 70,  height: 70),
    .init(.food, type: "dessert",       name: "Dessert Table",     icon: "cake",    color: "#D4A5A5", width: 120, height: 50),
    .init(.food, type: "cocktail",      name: "Cocktail Table",    icon: "circle",  color: "#8B8680", width: 40,  height: 40),
    .init(.food, type: "beverage",      name: "Beverage Station",  icon: "coffee",  color: "#9CAF88", width: 80,  height: 50),
    .init(.food, type: "coffee",        name: "Coffee Station",    icon: "coffee",  color: "#6b655c", width: 80,  height: 40),
    .init(.food, type: "ice_sculpture", name: "Ice Sculpture",     icon: "sparkle", color: "#C4D4E0", width: 50,  height: 50),
    .init(.food, type: "food_truck",    name: "Food Truck/Cart",   icon: "square",  color: "#C4A882", width: 100, height: 60),

    // Guest Services — 9 items
    .init(.services, type: "registration",  name: "Check-in / Registration", icon: "clipboard", color: "#8B9DC3", width: 120, height: 40),
    .init(.services, type: "guestbook",     name: "Guest Book",              icon: "file",      color: "#C9A961", width: 60,  height: 40),
    .init(.services, type: "seating_cards", name: "Seating Cards",           icon: "tag",       color: "#D4A5A5", width: 80,  height: 40),
    .init(.services, type: "coat_check",    name: "Coat Check",              icon: "tag",       color: "#8B8680", width: 100, height: 40),
    .init(.services, type: "welcome",       name: "Welcome Sign",            icon: "sign",      color: "#C9A961", width: 60,  height: 80),
    .init(.services, type: "cardbox",       name: "Gift Box",                icon: "inbox",     color: "#D4A5A5", width: 50,  height: 40),
    .init(.services, type: "kids_area",     name: "Kids Play Area",          icon: "users",     color: "#9CAF88", width: 120, height: 100),
    .init(.services, type: "lounge",        name: "Lounge Seating",          icon: "square",    color: "#C4A882", width: 150, height: 100),
    .init(.services, type: "first_aid",     name: "First Aid Station",       icon: "heart",     color: "#D4A5A5", width: 60,  height: 40),

    // Photo & Memories — 8 items
    .init(.photo, type: "photobooth",   name: "Photo Booth",        icon: "camera",  color: "#D4A5A5", width: 80,  height: 80),
    .init(.photo, type: "backdrop",     name: "Photo Backdrop",     icon: "frame",   color: "#D4A5A5", width: 150, height: 20),
    .init(.photo, type: "memory",       name: "Memorial Table",     icon: "heart",   color: "#D4A5A5", width: 80,  height: 60),
    .init(.photo, type: "polaroid",     name: "Polaroid Station",   icon: "camera",  color: "#D4A5A5", width: 60,  height: 50),
    .init(.photo, type: "flower_wall",  name: "Flower Wall",        icon: "flower",  color: "#D4A5A5", width: 120, height: 15),
    .init(.photo, type: "neon_sign",    name: "Neon Sign",          icon: "sparkle", color: "#C9A961", width: 90,  height: 30),
    .init(.photo, type: "video",        name: "Videographer Spot",  icon: "camera",  color: "#6b655c", width: 40,  height: 40),
    .init(.photo, type: "ring_light",   name: "Selfie Station",     icon: "circle",  color: "#C9A961", width: 50,  height: 50),

    // Ceremony & Decor — 15 items
    .init(.ceremony, type: "altar",            name: "Altar / Arch",            icon: "arch",      color: "#C9A961", width: 120, height: 40),
    .init(.ceremony, type: "chuppah",          name: "Chuppah",                 icon: "arch",      color: "#FBF7EC", width: 100, height: 100),
    .init(.ceremony, type: "gazebo",           name: "Gazebo / Arbor",          icon: "tent",      color: "#9CAF88", width: 120, height: 120),
    .init(.ceremony, type: "aisle",            name: "Ceremony Aisle",          icon: "path",      color: "#FBF7EC", width: 60,  height: 200),
    .init(.ceremony, type: "ceremony_chairs",  name: "Ceremony Seating",        icon: "users",     color: "#C9A961", width: 200, height: 150),
    .init(.ceremony, type: "floral",           name: "Floral Arrangement",      icon: "flower",    color: "#9CAF88", width: 50,  height: 50),
    .init(.ceremony, type: "unity",            name: "Unity Table",             icon: "flame",     color: "#C9A961", width: 60,  height: 40),
    .init(.ceremony, type: "podium",           name: "Podium / Lectern",        icon: "mic",       color: "#8B9DC3", width: 50,  height: 50),
    .init(.ceremony, type: "gift",             name: "Gift Table",              icon: "gift",      color: "#9CAF88", width: 100, height: 50),
    .init(.ceremony, type: "candelabra",       name: "Candelabra",              icon: "flame",     color: "#C9A961", width: 30,  height: 30),
    .init(.ceremony, type: "lantern",          name: "Lantern / Light Feature", icon: "lightbulb", color: "#C9A961", width: 25,  height: 25),
    .init(.ceremony, type: "draping",          name: "Draping / Fabric",        icon: "flag",      color: "#FBF7EC", width: 150, height: 30),
    .init(.ceremony, type: "chandelier",       name: "Chandelier",              icon: "sparkle",   color: "#C9A961", width: 60,  height: 60),
    .init(.ceremony, type: "string_lights",    name: "String Lights",           icon: "sparkle",   color: "#C9A961", width: 120, height: 20),
    .init(.ceremony, type: "balloon_arch",     name: "Balloon Arch",            icon: "arch",      color: "#D4A5A5", width: 100, height: 80),

    // A/V & Tech — 6 items
    .init(.av, type: "screen",        name: "Screen / Projector",  icon: "image",    color: "#6b655c", width: 120, height: 20),
    .init(.av, type: "tv_monitor",    name: "TV / Monitor",        icon: "image",    color: "#2D2D2D", width: 80,  height: 50),
    .init(.av, type: "av_booth",      name: "AV / Tech Booth",     icon: "settings", color: "#2D2D2D", width: 60,  height: 40),
    .init(.av, type: "lighting",      name: "Lighting Rig",        icon: "lightbulb",color: "#2D2D2D", width: 100, height: 30),
    .init(.av, type: "sound_mixer",   name: "Sound Mixer",         icon: "settings", color: "#2D2D2D", width: 60,  height: 40),
    .init(.av, type: "camera_crane",  name: "Camera Position",     icon: "camera",   color: "#6b655c", width: 40,  height: 80),

    // Tradeshow & Expo — 15 items
    .init(.tradeshow, type: "booth_10x10",       name: "Booth (10×10)",       icon: "square",    color: "#8B9DC3", width: 100, height: 100),
    .init(.tradeshow, type: "booth_10x20",       name: "Booth (10×20)",       icon: "rect",      color: "#8B9DC3", width: 200, height: 100),
    .init(.tradeshow, type: "booth_island",      name: "Island Booth",        icon: "square",    color: "#8B9DC3", width: 200, height: 200),
    .init(.tradeshow, type: "demo_station",      name: "Demo Station",        icon: "zap",       color: "#9CAF88", width: 80,  height: 60),
    .init(.tradeshow, type: "poster_board",      name: "Poster Board",        icon: "image",     color: "#C4A882", width: 40,  height: 80),
    .init(.tradeshow, type: "info_desk",         name: "Information Desk",    icon: "clipboard", color: "#8B9DC3", width: 120, height: 50),
    .init(.tradeshow, type: "networking_lounge", name: "Networking Lounge",   icon: "users",     color: "#8B8680", width: 150, height: 120),
    .init(.tradeshow, type: "sponsor_banner",    name: "Sponsor Banner",      icon: "tag",       color: "#C9A961", width: 100, height: 30),
    .init(.tradeshow, type: "kiosk",             name: "Kiosk / Terminal",    icon: "square",    color: "#2D2D2D", width: 50,  height: 50),
    .init(.tradeshow, type: "charging_station",  name: "Charging Station",    icon: "zap",       color: "#9CAF88", width: 60,  height: 40),
    .init(.tradeshow, type: "table_skirted",     name: "Skirted Table",       icon: "rect",      color: "#C4A882", width: 80,  height: 40),
    .init(.tradeshow, type: "popup_display",     name: "Pop-up Display",      icon: "image",     color: "#8B9DC3", width: 100, height: 20),
    .init(.tradeshow, type: "literature_rack",   name: "Brochure Rack",       icon: "file",      color: "#8B8680", width: 30,  height: 50),
    .init(.tradeshow, type: "meeting_pod",       name: "Meeting Pod",         icon: "users",     color: "#8B9DC3", width: 100, height: 100),
    .init(.tradeshow, type: "lead_station",      name: "Lead Capture",        icon: "clipboard", color: "#9CAF88", width: 50,  height: 40),

    // Venue Structure — 13 items
    .init(.structure, type: "entrance",      name: "Main Entrance",       icon: "door",     color: "#2D2D2D", width: 40,  height: 60),
    .init(.structure, type: "exit",          name: "Emergency Exit",      icon: "door",     color: "#9CAF88", width: 40,  height: 50),
    .init(.structure, type: "restroom",      name: "Restrooms",           icon: "users",    color: "#8B9DC3", width: 50,  height: 50),
    .init(.structure, type: "pillar",        name: "Round Pillar",        icon: "circle",   color: "#6B6B6B", width: 30,  height: 30, isObstacle: true),
    .init(.structure, type: "pillar_rect",   name: "Square Pillar",       icon: "square",   color: "#6B6B6B", width: 40,  height: 40, isObstacle: true),
    .init(.structure, type: "tent_pole",     name: "Tent Pole",           icon: "circle",   color: "#6b655c", width: 20,  height: 20, isObstacle: true),
    .init(.structure, type: "window",        name: "Window",              icon: "square",   color: "#C4D4E0", width: 60,  height: 80),
    .init(.structure, type: "fireplace",     name: "Fireplace",           icon: "flame",    color: "#6b655c", width: 100, height: 30),
    .init(.structure, type: "stairs",        name: "Stairs / Steps",      icon: "path",     color: "#6B6B6B", width: 80,  height: 40),
    .init(.structure, type: "ramp",          name: "Wheelchair Ramp",     icon: "path",     color: "#8B9DC3", width: 100, height: 30),
    .init(.structure, type: "door",          name: "Door / Doorway",      icon: "door",     color: "#6b655c", width: 30,  height: 50),
    .init(.structure, type: "kitchen_entry", name: "Kitchen Entry",       icon: "utensils", color: "#8B8680", width: 60,  height: 30),
    .init(.structure, type: "text_label",    name: "Text Label",          icon: "type",     color: "#FBF7EC", width: 150, height: 30),
]

// Backwards compatibility: the previous "checkin" type id maps to web's
// "registration". Look it up here when reading existing plans so the icon
// + edit-sheet preset still surface correctly.
extension Array where Element == VenueObjectDef {
    func byType(_ id: String) -> VenueObjectDef? {
        if id == "checkin" { return first { $0.type == "registration" } }
        return first { $0.type == id }
    }
}

struct VenueObjectsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    /// Catalog grouped by category, then filtered by the search query.
    private var grouped: [(VenueObjectCategory, [VenueObjectDef])] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = q.isEmpty
            ? venueObjectTypes
            : venueObjectTypes.filter {
                $0.name.lowercased().contains(q) || $0.type.lowercased().contains(q)
            }
        return VenueObjectCategory.allCases.compactMap { cat in
            let items = filtered.filter { $0.category == cat }
            return items.isEmpty ? nil : (cat, items)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Add a venue element to your floor plan")
                        .font(SBFont.body)
                        .foregroundStyle(Color.sbWarm)
                        .padding(.top, 4)

                    // Search — useful with 93 entries.
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Color.sbWarm2)
                        TextField("Search venue objects", text: $query)
                            .font(SBFont.body)
                    }
                    .padding(10)
                    .background(Color.sbIvory2)
                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))

                    ForEach(grouped, id: \.0) { (category, items) in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(category.displayName.uppercased())
                                .font(SBFont.capsLabel)
                                .foregroundStyle(Color.sbGoldDk)
                                .letterSpacing(1.5)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(items, id: \.type) { obj in
                                    objectCard(obj)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, SBSpacing.screenMargin)
            }
            .background(Color.sbIvory)
            .navigationTitle("Venue Objects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sbWarm)
                }
            }
        }
    }

    private func objectCard(_ obj: VenueObjectDef) -> some View {
        Button {
            addObject(obj)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(hex: obj.color).opacity(0.22))
                        .frame(width: 40, height: 40)
                    // Ivory-on-ivory items (Chuppah, Aisle, Draping at #FBF7EC)
                    // were rendering invisibly. Fall back to charcoal for any
                    // colour too light to read against the pale tinted chip.
                    Image(systemName: VenueIconMap.sfSymbol(for: obj.icon))
                        .font(.system(size: 18))
                        .foregroundStyle(isLightColor(obj.color) ? Color.sbCharcoal : Color(hex: obj.color))
                }
                Text(obj.name)
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(Color.sbCharcoal)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer()
            }
            .padding(10)
            .background(Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: SBRadius.card)
                    .strokeBorder(Color.sbLine, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// True if a #RRGGBB hex is too light to read against the picker
    /// chip's pale ivory background. Threshold tuned to catch the
    /// near-white ceremony tones (#FBF7EC, #FAF6EC) while leaving
    /// gold/sage/dusty-pink on their own colour.
    private func isLightColor(_ hex: String) -> Bool {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return false }
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        // Rec. 601 luma — close enough for picker contrast.
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.88
    }

    private func addObject(_ def: VenueObjectDef) {
        guard var plan = appState.activePlan else { return }
        // Spawn at the centre of whatever the user is currently looking at
        // on the canvas — was previously a small jittered area near the
        // top-left, which sometimes dropped objects off-screen when the
        // user was zoomed in elsewhere.
        let spawnPoint = CanvasViewController.viewportCentre(forPlanId: plan.id)
            ?? CGPoint(x: 200 + Double.random(in: -50...50),
                       y: 200 + Double.random(in: -50...50))
        let obj = RoomObject(
            id: UUID().uuidString,
            type: def.type,
            name: def.name,
            x: max(0, Double(spawnPoint.x) - def.width / 2),
            y: max(0, Double(spawnPoint.y) - def.height / 2),
            width: def.width,
            height: def.height,
            rotation: 0,
            color: def.color,
            icon: def.icon,
            isObstacle: def.isObstacle ? true : nil
        )
        plan.objects.append(obj)
        appState.activePlan = plan
        HapticEngine.success()
        Task { try? await appState.database.savePlanData(plan: plan) }
        dismiss()
    }
}

// MARK: - EditVenueObjectSheet (web parity)
//
// Direct port of web's "Edit Venue Object" modal at App.jsx:17561. Fields:
// Name, Width (in current unit), Height (in current unit), Rotation slider
// (-45 / -15 / slider / +15 / +45 / Reset 0°), Quick Size buttons (uses
// per-type `sizes` array if present, else fallback Small=min, Medium=default,
// Large=max). All values clamped to def.minW..maxW / minH..maxH on commit
// so a typo can't push the object outside web's safe range.

struct EditVenueObjectSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let objectId: String

    @State private var name: String = ""
    @State private var widthText: String = ""
    @State private var heightText: String = ""
    @State private var rotation: Double = 0
    @State private var didLoad = false

    private var plan: SeatingPlan? { appState.activePlan }
    private var object: RoomObject? { plan?.objects.first { $0.id == objectId } }
    private var def: VenueObjectDef? { venueObjectTypes.byType(object?.type ?? "") }

    private var unit: String { plan?.measurementUnit ?? "imperial" }
    private var unitLabel: String { RoomScale.unitLabel(for: unit) }
    private var pxPerUnit: Double { RoomScale.factor(for: unit) }

    private var isLocked: Bool { object?.locked == true }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if isLocked {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.sbSage)
                            Text("Locked — unlock to edit size and rotation")
                                .font(SBFont.caption)
                                .foregroundStyle(Color.sbSage)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.sbSage.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    nameField
                    sizeFields
                        .disabled(isLocked)
                        .opacity(isLocked ? 0.5 : 1)
                    rotationField
                        .disabled(isLocked)
                        .opacity(isLocked ? 0.5 : 1)
                    quickSizeGrid
                        .disabled(isLocked)
                        .opacity(isLocked ? 0.5 : 1)
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, SBSpacing.screenMargin)
                .padding(.top, 12)
            }
            .background(Color.sbIvory)
            .navigationTitle("Edit Venue Object")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sbWarm)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        commitAndSave()
                        dismiss()
                    }
                    .font(SBFont.bodySemibold)
                    .foregroundStyle(Color.sbGoldDk)
                }
            }
        }
        .onAppear { loadFromObject() }
    }

    // MARK: Name

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NAME")
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)
            TextField("Name", text: $name)
                .font(SBFont.body)
                .padding(12)
                .background(Color.sbIvory2)
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
                .onChange(of: name) { _, _ in commitNameLive() }
        }
    }

    // MARK: Size inputs

    private var sizeFields: some View {
        HStack(spacing: 12) {
            sizeInput(label: "WIDTH (\(unitLabel))", text: $widthText, commit: commitWidth)
            sizeInput(label: "HEIGHT (\(unitLabel))", text: $heightText, commit: commitHeight)
        }
    }

    private func sizeInput(label: String, text: Binding<String>, commit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)
            TextField("", text: text)
                .font(SBFont.body)
                .keyboardType(.decimalPad)
                .padding(12)
                .background(Color.sbIvory2)
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
                .onSubmit(commit)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Rotation slider

    private var rotationField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ROTATION")
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)
            HStack(spacing: 6) {
                rotationStep(symbol: "arrow.counterclockwise.circle", delta: -45)
                rotationStep(label: "-15°", delta: -15)
                Slider(value: Binding(
                    get: { rotation },
                    set: { rotation = ((($0).rounded() + 360).truncatingRemainder(dividingBy: 360)); commitRotation() }
                ), in: 0...360, step: 5)
                .tint(Color.sbGold)
                rotationStep(label: "+15°", delta: 15)
                rotationStep(symbol: "arrow.clockwise.circle", delta: 45)
                Button {
                    rotation = 0
                    commitRotation()
                    HapticEngine.selection()
                } label: {
                    Text("0°")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbGoldDk)
                        .frame(width: 32, height: 30)
                        .background(Color.sbChampagne)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            Text("\(Int(rotation))°")
                .font(SBFont.caption)
                .foregroundStyle(Color.sbWarm)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func rotationStep(symbol: String? = nil, label: String? = nil, delta: Double) -> some View {
        Button {
            rotation = ((rotation + delta + 360).truncatingRemainder(dividingBy: 360))
            commitRotation()
            HapticEngine.selection()
        } label: {
            Group {
                if let s = symbol {
                    Image(systemName: s).font(.system(size: 14, weight: .medium))
                } else {
                    Text(label ?? "").font(SBFont.caption)
                }
            }
            .foregroundStyle(Color.sbCharcoal)
            .frame(width: 36, height: 30)
            .background(Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: Quick Size

    private var quickSizeGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QUICK SIZE")
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)
            let presets = quickSizePresets()
            let cols: [GridItem] = presets.count >= 4
                ? [GridItem(.flexible()), GridItem(.flexible())]
                : Array(repeating: GridItem(.flexible()), count: presets.count)
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(presets, id: \.label) { p in
                    Button {
                        applyQuickSize(w: p.w, h: p.h)
                    } label: {
                        VStack(spacing: 2) {
                            Text(p.label)
                                .font(SBFont.bodySmallBold)
                                .foregroundStyle(Color.sbCharcoal)
                            Text("\(formatUnit(p.w))×\(formatUnit(p.h))\(unitLabel)")
                                .font(SBFont.caption)
                                .foregroundStyle(Color.sbWarm)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.sbIvory2)
                        .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// If the venue object's def has explicit `sizes` (dance floor, bar) use
    /// those. Otherwise fall back to Small=min, Medium=default, Large=max.
    private func quickSizePresets() -> [VenueObjectSize] {
        guard let def = def else { return [] }
        if let s = def.sizes { return s }
        return [
            .init(label: "Small",  w: def.minW, h: def.minH),
            .init(label: "Medium", w: def.width, h: def.height),
            .init(label: "Large",  w: def.maxW, h: def.maxH),
        ]
    }

    // MARK: Load + commit

    private func loadFromObject() {
        guard let obj = object, !didLoad else { return }
        name = obj.name
        widthText = formatUnit(obj.width)
        heightText = formatUnit(obj.height)
        rotation = obj.rotation ?? 0
        didLoad = true
    }

    private func commitNameLive() {
        guard var plan = plan, let idx = plan.objects.firstIndex(where: { $0.id == objectId }) else { return }
        plan.objects[idx].name = name
        appState.activePlan = plan
    }

    private func commitWidth() {
        guard let def = def, let v = Double(widthText), v > 0 else {
            widthText = formatUnit(object?.width ?? 0); return
        }
        let px = max(def.minW, min(def.maxW, v * pxPerUnit))
        widthText = formatUnit(px)
        applySize(w: px, h: object?.height ?? def.height)
    }

    private func commitHeight() {
        guard let def = def, let v = Double(heightText), v > 0 else {
            heightText = formatUnit(object?.height ?? 0); return
        }
        let px = max(def.minH, min(def.maxH, v * pxPerUnit))
        heightText = formatUnit(px)
        applySize(w: object?.width ?? def.width, h: px)
    }

    private func commitRotation() {
        guard var plan = plan, let idx = plan.objects.firstIndex(where: { $0.id == objectId }) else { return }
        plan.objects[idx].rotation = rotation
        appState.activePlan = plan
    }

    private func applyQuickSize(w: Double, h: Double) {
        widthText = formatUnit(w)
        heightText = formatUnit(h)
        applySize(w: w, h: h)
        HapticEngine.selection()
    }

    private func applySize(w: Double, h: Double) {
        guard var plan = plan, let idx = plan.objects.firstIndex(where: { $0.id == objectId }) else { return }
        plan.objects[idx].width = w
        plan.objects[idx].height = h
        appState.activePlan = plan
    }

    /// Final save on Done — flushes any in-flight text fields and persists.
    private func commitAndSave() {
        commitWidth()
        commitHeight()
        commitNameLive()
        commitRotation()
        if let plan = appState.activePlan {
            Task { try? await appState.database.savePlanData(plan: plan) }
        }
    }

    /// Pixel value → user unit, formatted with 1 decimal if needed.
    private func formatUnit(_ px: Double) -> String {
        let v = px / pxPerUnit
        if abs(v - v.rounded()) < 0.05 { return String(format: "%.0f", v) }
        return String(format: "%.1f", v)
    }
}

#Preview {
    VenueObjectsSheet()
        .environment(AppState())
}
