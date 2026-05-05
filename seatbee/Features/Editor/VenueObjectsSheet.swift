import SwiftUI

// MARK: - Venue object catalog (web parity)
//
// Mirrors the entries in `src/App.jsx VENUE_OBJECTS` for the items iOS
// currently surfaces. All width/height/min/max values are in the same px
// space as web (15 px = 1 ft imperial; web's `toUnit/fromUnit` handles
// conversion at render). When extending this list, copy fields verbatim
// from web — drift causes silent shape corruption on round-trip.

struct VenueObjectSize {
    let label: String
    let w: Double
    let h: Double
}

struct VenueObjectDef {
    let type: String
    let name: String
    let icon: String
    let color: String
    let width: Double          // default w on create
    let height: Double         // default h on create
    let minW: Double
    let maxW: Double
    let minH: Double
    let maxH: Double
    let sizes: [VenueObjectSize]?  // nil → fallback to {Small: minW/H, Medium: w/h, Large: maxW/H}
    let isObstacle: Bool

    init(type: String, name: String, icon: String, color: String,
         width: Double, height: Double,
         minW: Double, maxW: Double, minH: Double, maxH: Double,
         sizes: [VenueObjectSize]? = nil, isObstacle: Bool = false) {
        self.type = type; self.name = name; self.icon = icon; self.color = color
        self.width = width; self.height = height
        self.minW = minW; self.maxW = maxW; self.minH = minH; self.maxH = maxH
        self.sizes = sizes; self.isObstacle = isObstacle
    }
}

let venueObjectTypes: [VenueObjectDef] = [
    // Entertainment & Music
    .init(type: "dance", name: "Dance Floor", icon: "music.note", color: "#F7E7CE",
          width: 180, height: 180, minW: 120, maxW: 900, minH: 120, maxH: 900,
          sizes: [
            .init(label: "Small",  w: 120, h: 120),
            .init(label: "Medium", w: 180, h: 180),
            .init(label: "Large",  w: 270, h: 270),
            .init(label: "XL",     w: 360, h: 360),
          ]),
    .init(type: "stage", name: "Stage", icon: "star", color: "#D4A5A5",
          width: 160, height: 60, minW: 100, maxW: 1500, minH: 40, maxH: 600),
    .init(type: "dj", name: "DJ Booth", icon: "headphones", color: "#2D2D2D",
          width: 80, height: 50, minW: 60, maxW: 150, minH: 40, maxH: 100),

    // Food & Beverage
    .init(type: "bar", name: "Bar", icon: "wineglass", color: "#8B8680",
          width: 180, height: 45, minW: 60, maxW: 450, minH: 30, maxH: 120,
          sizes: [
            .init(label: "Small",  w: 90,  h: 30),
            .init(label: "Medium", w: 180, h: 45),
            .init(label: "Large",  w: 300, h: 60),
          ]),
    .init(type: "cake", name: "Cake Table", icon: "birthday.cake", color: "#FFE4E1",
          width: 70, height: 70, minW: 50, maxW: 120, minH: 50, maxH: 120),

    // Guest Services
    .init(type: "registration", name: "Check-in", icon: "list.clipboard", color: "#87CEEB",
          width: 120, height: 40, minW: 80, maxW: 200, minH: 30, maxH: 60),

    // Photo & Memories
    .init(type: "photobooth", name: "Photo Booth", icon: "camera", color: "#DDA0DD",
          width: 80, height: 80, minW: 60, maxW: 150, minH: 60, maxH: 150),

    // Ceremony & Decor
    .init(type: "podium", name: "Podium", icon: "mic", color: "#8B9DC3",
          width: 50, height: 50, minW: 40, maxW: 100, minH: 40, maxH: 100),
    .init(type: "gift", name: "Gift Table", icon: "gift", color: "#98D8C8",
          width: 100, height: 50, minW: 60, maxW: 180, minH: 40, maxH: 100),

    // Venue Structure
    .init(type: "entrance", name: "Entrance", icon: "door.left.hand.open", color: "#2D2D2D",
          width: 40, height: 60, minW: 30, maxW: 80, minH: 40, maxH: 100),
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Add a venue element to your floor plan")
                        .font(SBFont.body)
                        .foregroundStyle(Color.sbWarm)
                        .padding(.top, 8)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(venueObjectTypes, id: \.type) { obj in
                            Button {
                                addObject(obj)
                            } label: {
                                VStack(spacing: 8) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(hex: obj.color).opacity(0.2))
                                            .frame(width: 48, height: 48)
                                        Image(systemName: obj.icon)
                                            .font(.system(size: 20))
                                            .foregroundStyle(Color(hex: obj.color))
                                    }
                                    Text(obj.name)
                                        .font(SBFont.bodySmallBold)
                                        .foregroundStyle(Color.sbCharcoal)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(16)
                                .background(Color.sbIvory2)
                                .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))
                                .overlay(
                                    RoundedRectangle(cornerRadius: SBRadius.card)
                                        .strokeBorder(Color.sbLine, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
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

    private func addObject(_ def: VenueObjectDef) {
        guard var plan = appState.activePlan else { return }
        let obj = RoomObject(
            id: UUID().uuidString,
            type: def.type,
            name: def.name,
            x: 200 + Double.random(in: -50...50),
            y: 200 + Double.random(in: -50...50),
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    nameField
                    sizeFields
                    rotationField
                    quickSizeGrid
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
