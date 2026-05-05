import SwiftUI
import PhotosUI

struct RoomSetupSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var roomWidth = ""
    @State private var roomHeight = ""
    @State private var useMetric = false
    @State private var selectedShape = "rect"
    @State private var flipH = false
    @State private var flipV = false
    @State private var showImagePicker = false
    @State private var selectedImage: PhotosPickerItem?
    @State private var floorPlanImage: UIImage?
    @State private var isAnalyzing = false
    @State private var analysisResult: String?

    // Web parity: 8 preset shapes. iOS lays them out in a 4×2 grid.
    // Icons are SF Symbols approximations — exact glyphs differ from web SVG
    // but read clearly enough that users can match the shape they want.
    private let shapes: [(id: String, label: String, icon: String, mirror: Bool)] = [
        ("rect",   "Rectangle", "rectangle", false),
        ("l",      "L-Shape",   "l.rectangle.roundedbottom", false),
        ("l_rev",  "L-Reversed","l.rectangle.roundedbottom", true),
        ("t",      "T-Shape",   "t.square", false),
        ("u",      "U-Shape",   "u.square", false),
        ("oval",   "Oval",      "oval", false),
        ("circle", "Circle",    "circle", false),
        ("custom", "Custom",    "scribble.variable", false),
    ]

    // Web parity: matches the Quick Presets row in src/App.jsx Room Settings.
    // Stored in feet — converted to pixels (or metric meters) on apply.
    private let quickPresets: [(label: String, sub: String, w: Double, h: Double)] = [
        ("Small",      "50×35ft",   50,  35),
        ("Medium",     "80×60ft",   80,  60),
        ("Large",      "110×80ft",  110, 80),
        ("Ballroom",   "150×100ft", 150, 100),
        ("Grand",      "200×150ft", 200, 150),
        ("Convention", "300×200ft", 300, 200),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Quick Presets — one-tap dimension shortcuts (web parity).
                    formSection("QUICK PRESETS") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(quickPresets, id: \.label) { preset in
                                Button {
                                    useMetric = false
                                    roomWidth = String(format: "%.0f", preset.w)
                                    roomHeight = String(format: "%.0f", preset.h)
                                    HapticEngine.selection()
                                } label: {
                                    VStack(spacing: 2) {
                                        Text(preset.label)
                                            .font(SBFont.bodySmallBold)
                                            .foregroundStyle(Color.sbCharcoal)
                                        Text(preset.sub)
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

                    // Room shape — 8 presets in a 4×2 grid (web parity).
                    formSection("ROOM SHAPE") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(shapes, id: \.id) { shape in
                                Button {
                                    selectedShape = shape.id
                                    HapticEngine.selection()
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: shape.icon)
                                            .font(.system(size: 22))
                                            .scaleEffect(x: shape.mirror ? -1 : 1, y: 1)
                                            .foregroundStyle(selectedShape == shape.id ? Color.sbGoldDk : Color.sbWarm)
                                        Text(shape.label)
                                            .font(SBFont.capsLabel)
                                            .foregroundStyle(selectedShape == shape.id ? Color.sbGoldDk : Color.sbWarm)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.7)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(selectedShape == shape.id ? Color.sbChampagne : Color.sbIvory2)
                                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Flip H / Flip V (web parity — Trace canvas Flip buttons,
                    // surfaced here as quick toggles since iOS V2 has no trace UI yet).
                    formSection("ORIENTATION") {
                        HStack(spacing: 10) {
                            flipButton(title: "Flip H", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right", isOn: flipH) {
                                flipH.toggle()
                                HapticEngine.selection()
                            }
                            flipButton(title: "Flip V", systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down", isOn: flipV) {
                                flipV.toggle()
                                HapticEngine.selection()
                            }
                        }
                    }

                    // Dimensions
                    formSection("DIMENSIONS") {
                        HStack(spacing: 12) {
                            HStack {
                                TextField("Width", text: $roomWidth)
                                    .font(SBFont.body)
                                    .keyboardType(.decimalPad)
                                Text(useMetric ? "m" : "ft")
                                    .font(SBFont.caption)
                                    .foregroundStyle(Color.sbWarm)
                            }
                            .padding(12)
                            .background(Color.sbIvory2)
                            .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))

                            Text("x")
                                .font(SBFont.body)
                                .foregroundStyle(Color.sbWarm)

                            HStack {
                                TextField("Height", text: $roomHeight)
                                    .font(SBFont.body)
                                    .keyboardType(.decimalPad)
                                Text(useMetric ? "m" : "ft")
                                    .font(SBFont.caption)
                                    .foregroundStyle(Color.sbWarm)
                            }
                            .padding(12)
                            .background(Color.sbIvory2)
                            .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
                        }

                        Toggle(isOn: $useMetric) {
                            Text("Use metric (meters)")
                                .font(SBFont.bodySmall)
                        }
                        .tint(Color.sbGold)
                    }

                    // Zones (read-only V2 — web users can author Dance Floor /
                    // Bar / Stage areas; iOS doesn't have an editor yet, so
                    // surface them as a list so users know they exist).
                    if let zones = appState.activePlan?.roomZones, !zones.isEmpty {
                        formSection("LABELED AREAS") {
                            VStack(spacing: 8) {
                                ForEach(zones, id: \.id) { zone in
                                    HStack(spacing: 10) {
                                        Image(systemName: "rectangle.dashed")
                                            .font(.system(size: 14))
                                            .foregroundStyle(Color.sbGoldDk)
                                        Text(zone.label)
                                            .font(SBFont.bodySmallBold)
                                            .foregroundStyle(Color.sbCharcoal)
                                        Spacer()
                                        Text("\(Int(zone.w))×\(Int(zone.h))")
                                            .font(SBFont.caption)
                                            .foregroundStyle(Color.sbWarm)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(Color.sbIvory2)
                                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
                                }
                                Text("Edit areas on the web app for now.")
                                    .font(SBFont.caption)
                                    .foregroundStyle(Color.sbWarm)
                                    .padding(.top, 4)
                            }
                        }
                    }

                    // Floor plan upload
                    formSection("FLOOR PLAN IMAGE") {
                        if let image = floorPlanImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))

                            if isAnalyzing {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("AI analyzing floor plan...")
                                        .font(SBFont.body)
                                        .foregroundStyle(Color.sbWarm)
                                }
                            }

                            if let result = analysisResult {
                                Text(result)
                                    .font(SBFont.caption)
                                    .foregroundStyle(Color.sbSage)
                                    .padding(10)
                                    .background(Color.sbSage.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }

                        PhotosPicker(selection: $selectedImage, matching: .images) {
                            HStack {
                                Image(systemName: "photo.badge.plus")
                                Text(floorPlanImage == nil ? "Upload floor plan" : "Change image")
                            }
                            .font(SBFont.bodySemibold)
                            .foregroundStyle(Color.sbGoldDk)
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(Color.sbIvory2)
                            .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
                            .overlay(
                                RoundedRectangle(cornerRadius: SBRadius.button)
                                    .strokeBorder(Color.sbLine2, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                            )
                        }
                        .onChange(of: selectedImage) { _, newItem in
                            Task {
                                if let data = try? await newItem?.loadTransferable(type: Data.self),
                                   let uiImage = UIImage(data: data) {
                                    floorPlanImage = uiImage
                                    analyzeFloorPlan(uiImage)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, SBSpacing.screenMargin)
                .padding(.top, 16)
            }
            .background(Color.sbIvory)
            .navigationTitle("Room Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sbWarm)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { applySetup() }
                        .font(SBFont.bodySemibold)
                        .foregroundStyle(Color.sbGoldDk)
                }
            }
        }
        .onAppear { loadCurrentSetup() }
    }

    private func flipButton(title: String, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                Text(title)
                    .font(SBFont.bodySmallBold)
            }
            .foregroundStyle(isOn ? Color.sbGoldDk : Color.sbCharcoal)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isOn ? Color.sbChampagne : Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
        }
        .buttonStyle(.plain)
    }

    private func formSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)
            content()
        }
    }

    private func loadCurrentSetup() {
        guard let plan = appState.activePlan else { return }
        // Web stores dimensions in pixels; convert back to ft/m for display.
        let unit = plan.measurementUnit ?? "imperial"
        useMetric = (unit.lowercased() == "metric")
        let factor = RoomScale.factor(for: unit)
        if let w = plan.roomWidth { roomWidth = String(format: "%.0f", w / factor) }
        if let h = plan.roomHeight { roomHeight = String(format: "%.0f", h / factor) }
        if let shape = plan.roomShape, !shape.isEmpty { selectedShape = shape }
        flipH = plan.roomFlipH ?? false
        flipV = plan.roomFlipV ?? false
    }

    private func applySetup() {
        guard var plan = appState.activePlan else { return }
        let unit = useMetric ? "metric" : "imperial"
        let factor = RoomScale.factor(for: unit)

        // Convert user-entered ft/m to pixels before persisting (web parity).
        let widthPx = (Double(roomWidth) ?? 0) * factor
        let heightPx = (Double(roomHeight) ?? 0) * factor
        plan.roomWidth = widthPx > 0 ? widthPx : plan.roomWidth
        plan.roomHeight = heightPx > 0 ? heightPx : plan.roomHeight
        plan.measurementUnit = unit

        // If shape changed (or this is the first time the user has set
        // a shape), regenerate customRoomPoints from the preset. Web's
        // SHAPE-button onClick does exactly this.
        let previousShape = appState.activePlan?.roomShape
        if selectedShape != previousShape || plan.customRoomPoints == nil {
            plan.roomShape = selectedShape
            if let w = plan.roomWidth, let h = plan.roomHeight, w > 0, h > 0 {
                plan.customRoomPoints = RoomShapePresets.defaultPoints(
                    shape: selectedShape, width: w, height: h
                )
            }
        } else {
            plan.roomShape = selectedShape
        }

        // Flip flags persist (web parity — Trace canvas Flip H/V buttons).
        // Canvas reads these in its roomBezierPath() to mirror the rendered
        // shape without mutating customRoomPoints.
        plan.roomFlipH = flipH
        plan.roomFlipV = flipV

        // Persist floor plan image (if user uploaded one) as a base64 data
        // URL on rawFloorPlanImage. Default opacity matches web (0.4).
        if let image = floorPlanImage,
           let data = image.jpegData(compressionQuality: 0.85) {
            let dataURL = "data:image/jpeg;base64," + data.base64EncodedString()
            plan.rawFloorPlanImage = AnyCodable(dataURL)
            if plan.rawFloorPlanOpacity == nil { plan.rawFloorPlanOpacity = 0.4 }
        }

        appState.activePlan = plan
        HapticEngine.success()
        Task { try? await appState.database.savePlanData(plan: plan) }
        dismiss()
    }

    private func analyzeFloorPlan(_ image: UIImage) {
        isAnalyzing = true
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            isAnalyzing = false
            return
        }
        let base64 = "data:image/jpeg;base64," + imageData.base64EncodedString()

        Task {
            do {
                let result = try await appState.ai.call(
                    action: .parseFloorPlan,
                    systemPrompt: "Analyze this venue floor plan image.",
                    userMessage: base64
                )
                analysisResult = "AI analysis complete. Check dimensions above."
                // Try to extract dimensions from result
                if let data = result.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let dims = json["dimensions"] as? [String: Any] {
                    if let w = dims["width"] as? Double { roomWidth = String(format: "%.0f", w) }
                    if let h = dims["height"] as? Double { roomHeight = String(format: "%.0f", h) }
                }
            } catch {
                analysisResult = "Analysis failed: \(error.localizedDescription)"
            }
            isAnalyzing = false
        }
    }
}

#Preview {
    RoomSetupSheet()
        .environment(AppState())
}
