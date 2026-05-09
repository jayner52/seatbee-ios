import SwiftUI
import PhotosUI
import PDFKit
import UniformTypeIdentifiers

struct RoomSetupSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var roomWidth = ""
    @State private var roomHeight = ""
    @State private var useMetric = false
    @State private var selectedShape = "rect"
    @State private var flipH = false
    @State private var flipV = false
    @State private var showPhotoPicker = false
    @State private var showFilePicker = false
    @State private var selectedImage: PhotosPickerItem?
    @State private var floorPlanImage: UIImage?
    @State private var isAnalyzing = false
    @State private var analysisResult: String?
    @State private var importError: String?
    @State private var showTraceSheet = false
    @State private var workingPoints: [RoomPoint]? = nil

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
                    // Preset values are stored in feet (the canonical web unit
                    // for these labels); displayed and applied in the user's
                    // current unit. Tapping a preset never flips the unit
                    // toggle — only the dimension fields update.
                    formSection("QUICK PRESETS") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(quickPresets, id: \.label) { preset in
                                Button {
                                    let displayW = useMetric ? preset.w / 3.28084 : preset.w
                                    let displayH = useMetric ? preset.h / 3.28084 : preset.h
                                    roomWidth = String(format: "%.0f", displayW)
                                    roomHeight = String(format: "%.0f", displayH)
                                    // Quick Presets are W×H rectangle dimensions
                                    // by definition, so snap shape to Rectangle.
                                    // Drops any prior custom polygon — applySetup
                                    // regenerates points at the new dims.
                                    selectedShape = "rect"
                                    workingPoints = nil
                                    HapticEngine.selection()
                                } label: {
                                    VStack(spacing: 2) {
                                        Text(preset.label)
                                            .font(SBFont.bodySmallBold)
                                            .foregroundStyle(Color.sbCharcoal)
                                        Text(presetSubtitle(preset))
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
                                        let iconColor = selectedShape == shape.id ? Color.sbGoldDk : Color.sbWarm
                                        if ["l", "l_rev", "t", "u"].contains(shape.id) {
                                            RoomShapeIcon(shape: shape.id, color: iconColor)
                                                .frame(width: 26, height: 26)
                                        } else {
                                            Image(systemName: shape.icon)
                                                .font(.system(size: 22))
                                                .scaleEffect(x: shape.mirror ? -1 : 1, y: 1)
                                                .foregroundStyle(iconColor)
                                        }
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

                    // Edit Shape — opens the interactive trace canvas (V3).
                    // Mirrors web's "Edit Shape" button under the shape grid.
                    Button {
                        showTraceSheet = true
                        HapticEngine.selection()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "scribble.variable")
                                .font(.system(size: 14, weight: .medium))
                            Text("Edit Shape")
                                .font(SBFont.bodySemibold)
                        }
                        .foregroundStyle(Color.sbGoldDk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.sbChampagne.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
                    }
                    .buttonStyle(.plain)

                    // Flip H / Flip V (web parity — Trace canvas Flip buttons,
                    // surfaced here as quick toggles for users who don't open the trace sheet).
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
                        .onChange(of: useMetric) { _, newValue in
                            // Convert displayed values to the new unit so the
                            // numbers in the field reflect what they mean.
                            // 1 m = 3.28084 ft. Empty fields stay empty.
                            let ftPerM = 3.28084
                            if newValue {
                                if let w = Double(roomWidth), w > 0 {
                                    roomWidth = String(format: "%.0f", w / ftPerM)
                                }
                                if let h = Double(roomHeight), h > 0 {
                                    roomHeight = String(format: "%.0f", h / ftPerM)
                                }
                            } else {
                                if let w = Double(roomWidth), w > 0 {
                                    roomWidth = String(format: "%.0f", w * ftPerM)
                                }
                                if let h = Double(roomHeight), h > 0 {
                                    roomHeight = String(format: "%.0f", h * ftPerM)
                                }
                            }
                        }
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

                    // Floor plan upload — supports both Photos and Files
                    // (Files lets users grab a PDF or image from iCloud
                    // Drive, Dropbox, etc., matching web's accept="image/*,.pdf").
                    formSection("FLOOR PLAN") {
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

                        if let err = importError {
                            Text(err)
                                .font(SBFont.caption)
                                .foregroundStyle(Color.sbError)
                        }

                        HStack(spacing: 10) {
                            PhotosPicker(selection: $selectedImage, matching: .images) {
                                uploadButtonLabel(icon: "photo.on.rectangle", label: "Photos")
                            }
                            .onChange(of: selectedImage) { _, newItem in
                                Task {
                                    importError = nil
                                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                                       let uiImage = UIImage(data: data) {
                                        floorPlanImage = uiImage
                                        analyzeFloorPlan(uiImage)
                                    } else if newItem != nil {
                                        importError = "Couldn't load that photo."
                                    }
                                }
                            }

                            Button {
                                showFilePicker = true
                            } label: {
                                uploadButtonLabel(icon: "doc.badge.plus", label: "Files / PDF")
                            }
                            .buttonStyle(.plain)
                        }

                        Text(floorPlanImage == nil
                             ? "Pick a floor plan from your photo library or a PDF / image from Files."
                             : "Pick a different one to replace.")
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbWarm)
                    }
                    .fileImporter(
                        isPresented: $showFilePicker,
                        allowedContentTypes: [.pdf, .image],
                        allowsMultipleSelection: false
                    ) { result in
                        importError = nil
                        switch result {
                        case .success(let urls):
                            guard let url = urls.first else { return }
                            handleImportedFile(url: url)
                        case .failure(let error):
                            importError = "Import failed: \(error.localizedDescription)"
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
        .sheet(isPresented: $showTraceSheet) {
            traceSheetContent()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func traceSheetContent() -> some View {
        // Build initial points from either the user's current customRoomPoints
        // or the active preset (fallback handles plans whose customRoomPoints
        // never got authored). Width/height come from the live form inputs
        // converted back to pixels — keeps the trace sheet in sync with whatever
        // dimensions the user is currently typing.
        let unit = useMetric ? "metric" : "imperial"
        let factor = RoomScale.factor(for: unit)
        let widthPx = max((Double(roomWidth) ?? 0) * factor, 100)
        let heightPx = max((Double(roomHeight) ?? 0) * factor, 100)
        // Pick the right starting points for the trace canvas. If the user
        // changed dimensions (e.g. tapped a Quick Preset) but kept a preset
        // shape, the saved customRoomPoints are at the OLD size and would
        // render off-screen — regenerate from preset at the live dims.
        // Custom-shaped plans preserve their saved points only when the
        // bbox roughly matches current dims; otherwise we fall back too.
        let livePoints: [RoomPoint] = {
            if let traced = workingPoints { return traced }
            let saved = appState.activePlan?.customRoomPoints
            if let saved = saved, !saved.isEmpty {
                let maxX = saved.map(\.x).max() ?? 0
                let maxY = saved.map(\.y).max() ?? 0
                let widthMatches = widthPx > 0 && abs(maxX - widthPx) / widthPx < 0.15
                let heightMatches = heightPx > 0 && abs(maxY - heightPx) / heightPx < 0.15
                if widthMatches && heightMatches { return saved }
            }
            let shape = selectedShape == "custom" ? "rect" : selectedShape
            return RoomShapePresets.defaultPoints(shape: shape, width: widthPx, height: heightPx)
        }()

        TraceShapeSheet(
            initialPoints: livePoints,
            initialFlipH: flipH,
            initialFlipV: flipV,
            currentShape: selectedShape,
            roomWidth: widthPx,
            roomHeight: heightPx,
            measurementUnit: unit,
            floorPlanImage: floorPlanImage
        ) { newPoints, newFlipH, newFlipV in
            workingPoints = newPoints
            flipH = newFlipH
            flipV = newFlipV
            selectedShape = "custom"
        }
    }

    private func presetSubtitle(_ p: (label: String, sub: String, w: Double, h: Double)) -> String {
        // Preset values are stored in feet. Show ft when imperial, m when metric.
        if useMetric {
            let w = p.w / 3.28084
            let h = p.h / 3.28084
            return String(format: "%.0f×%.0fm", w, h)
        }
        return p.sub
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
        // Decode the saved floor plan into local state so the trace sheet
        // shows it as a backdrop for tracing — without this, an existing
        // plan's uploaded floor plan was invisible inside Edit Shape.
        if floorPlanImage == nil,
           let raw = plan.rawFloorPlanImage?.value as? String,
           let image = decodeBase64ImageDataURL(raw) {
            floorPlanImage = image
        }
    }

    /// Decode a base64 `data:image/...` URL string into a UIImage. Web
    /// persists floor plans this way (so they round-trip through Supabase
    /// JSONB without external storage). Returns nil if the prefix is
    /// missing or the bytes don't form a valid image.
    private func decodeBase64ImageDataURL(_ raw: String) -> UIImage? {
        guard let comma = raw.firstIndex(of: ",") else { return nil }
        let b64 = String(raw[raw.index(after: comma)...])
        guard let data = Data(base64Encoded: b64) else { return nil }
        return UIImage(data: data)
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

        // Regenerate customRoomPoints from the preset whenever EITHER the
        // shape OR the dimensions changed — otherwise tapping a Quick Preset
        // (e.g. Small 50×35ft) updated roomWidth/roomHeight but kept the
        // old polygon, leaving the canvas rendering the previous room
        // size. Custom shape preserves whatever points the user traced.
        // Trace-sheet output (workingPoints) overrides everything.
        let previousShape = appState.activePlan?.roomShape
        let previousW = appState.activePlan?.roomWidth ?? -1
        let previousH = appState.activePlan?.roomHeight ?? -1
        let shapeChanged = selectedShape != previousShape
        let dimsChanged = abs((plan.roomWidth ?? 0) - previousW) > 1
                       || abs((plan.roomHeight ?? 0) - previousH) > 1

        plan.roomShape = selectedShape
        if let traced = workingPoints {
            plan.customRoomPoints = traced
        } else if selectedShape != "custom" &&
                  (shapeChanged || dimsChanged || plan.customRoomPoints == nil) {
            if let w = plan.roomWidth, let h = plan.roomHeight, w > 0, h > 0 {
                plan.customRoomPoints = RoomShapePresets.defaultPoints(
                    shape: selectedShape, width: w, height: h
                )
            }
        }
        // (else: selectedShape == "custom" with no traced override → preserve
        // the user's existing custom polygon as-is.)

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

    // Reusable button face for the two upload entry points (Photos / Files).
    @ViewBuilder
    private func uploadButtonLabel(icon: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
            Text(label)
                .font(SBFont.bodySmallBold)
        }
        .foregroundStyle(Color.sbGoldDk)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.sbIvory2)
        .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
        .overlay(
            RoundedRectangle(cornerRadius: SBRadius.button)
                .strokeBorder(Color.sbLine2, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        )
    }

    // Handle a file picked from the Files app. fileImporter gives us a
    // security-scoped URL that we have to open + close around the read.
    // PDFs render page 1 to a UIImage via PDFKit (matches web's PDF.js
    // page-1-only behavior); standard image files load directly.
    private func handleImportedFile(url: URL) {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            guard let image = renderPDFFirstPage(at: url) else {
                importError = "Couldn't render that PDF."
                return
            }
            floorPlanImage = image
            analyzeFloorPlan(image)
            return
        }

        // Anything else: try to load as an image. UIImage(data:) auto-handles
        // HEIC/JPG/PNG/GIF; falls through to error if the bytes aren't usable.
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            importError = "That file format isn't supported."
            return
        }
        floorPlanImage = image
        analyzeFloorPlan(image)
    }

    // Render the first page of a PDF at 2× display scale into a UIImage.
    // 2× keeps the AI input crisp without blowing up base64 size; we use
    // the page's mediaBox bounds rather than cropBox so margins are kept
    // (some floor plans use cropBox to hide the legend).
    private func renderPDFFirstPage(at url: URL) -> UIImage? {
        guard let pdf = PDFDocument(url: url),
              let page = pdf.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
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

// MARK: - RoomShapeIcon
//
// Draws actual floor-plan polygon outlines for L / L-Reversed / T / U shapes
// so the picker shows the room silhouette rather than the letter glyph.
// Coordinates are normalized 0…1 and scaled to the frame at draw time.

struct RoomShapeIcon: View {
    let shape: String
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            guard let pts = points(for: shape) else { return }
            let w = size.width, h = size.height
            var path = Path()
            path.move(to: CGPoint(x: pts[0].x * w, y: pts[0].y * h))
            for pt in pts.dropFirst() { path.addLine(to: CGPoint(x: pt.x * w, y: pt.y * h)) }
            path.closeSubpath()
            ctx.fill(path, with: .color(color.opacity(0.12)))
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
        }
    }

    private func points(for id: String) -> [CGPoint]? {
        switch id {
        case "l":
            // Tall left column + bottom bar extending right
            return [
                CGPoint(x: 0, y: 0), CGPoint(x: 0.45, y: 0),
                CGPoint(x: 0.45, y: 0.52), CGPoint(x: 1, y: 0.52),
                CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1),
            ]
        case "l_rev":
            // Mirror of L: tall right column + bottom bar extending left
            return [
                CGPoint(x: 0, y: 0.52), CGPoint(x: 0.55, y: 0.52),
                CGPoint(x: 0.55, y: 0), CGPoint(x: 1, y: 0),
                CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1),
            ]
        case "t":
            // Wide top bar + narrow center stem
            return [
                CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
                CGPoint(x: 1, y: 0.42), CGPoint(x: 0.65, y: 0.42),
                CGPoint(x: 0.65, y: 1), CGPoint(x: 0.35, y: 1),
                CGPoint(x: 0.35, y: 0.42), CGPoint(x: 0, y: 0.42),
            ]
        case "u":
            // Two arms + bottom bar, open at top
            return [
                CGPoint(x: 0, y: 0), CGPoint(x: 0.3, y: 0),
                CGPoint(x: 0.3, y: 0.62), CGPoint(x: 0.7, y: 0.62),
                CGPoint(x: 0.7, y: 0), CGPoint(x: 1, y: 0),
                CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1),
            ]
        default:
            return nil
        }
    }
}

#Preview {
    RoomSetupSheet()
        .environment(AppState())
}

// MARK: - TraceShapeSheet (V3 — interactive room shape editor)
//
// Web parity reference: src/App.jsx RoomEditorModal step 1 ("Trace Shape").
// iOS scopes V3 to the operations Jayne specifically called out: tap a wall
// to insert a corner, drag corners to fine-tune, long-press a corner to
// delete, with live edge-length labels in ft / m. Reset regenerates from
// the current preset. Flip H / Flip V mirror points without leaving the
// sheet. Arc / curve editing and the Set Dimensions slider step are V4.

struct TraceShapeSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initialPoints: [RoomPoint]
    let initialFlipH: Bool
    let initialFlipV: Bool
    let currentShape: String
    let roomWidth: Double
    let roomHeight: Double
    let measurementUnit: String?
    /// Optional floor-plan image rendered behind the polygon as a faded
    /// reference so the user can trace the actual walls. Web does the
    /// same thing in RoomEditorModal step 1.
    var floorPlanImage: UIImage? = nil

    /// Called with the user's final point list + flip flags when they tap Apply.
    /// Cancel discards everything; the parent sheet keeps its existing values.
    let onApply: ([RoomPoint], Bool, Bool) -> Void

    @State private var points: [RoomPoint] = []
    @State private var flipH = false
    @State private var flipV = false
    @State private var draggingIndex: Int? = nil
    @State private var pendingDelete: Int? = nil

    private var unitLabel: String { RoomScale.unitLabel(for: measurementUnit) }
    private var pixelsPerUnit: Double { RoomScale.factor(for: measurementUnit) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                instructions
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.sbIvory2)

                // Aspect-ratio container instead of GeometryReader-fill —
                // GR sometimes returns the wrong size while the sheet is
                // animating in, which left the polygon drawn at stale
                // coordinates and only one corner visible. Locking the
                // canvas to the room's aspect ratio with a max height
                // gives a stable size on first paint.
                let aspect = max(roomWidth / max(roomHeight, 1), 0.1)
                GeometryReader { geo in
                    traceCanvas(in: geo.size)
                }
                .aspectRatio(aspect, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.sbIvory)

                toolbar
            }
            .background(Color.sbIvory)
            .navigationTitle("Edit Shape")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sbWarm)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(points, flipH, flipV)
                        HapticEngine.success()
                        dismiss()
                    }
                    .font(SBFont.bodySemibold)
                    .foregroundStyle(Color.sbGoldDk)
                    .disabled(points.count < 3)
                }
            }
            .alert("Delete corner?", isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { pendingDelete = nil }
                Button("Delete", role: .destructive) {
                    if let idx = pendingDelete, points.count > 3 {
                        points.remove(at: idx)
                        HapticEngine.success()
                    }
                    pendingDelete = nil
                }
            } message: {
                Text("A shape needs at least 3 corners.")
            }
        }
        .onAppear {
            points = initialPoints
            flipH = initialFlipH
            flipV = initialFlipV
        }
    }

    // MARK: Instructions

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(points.count) corner\(points.count == 1 ? "" : "s") · \(currentShape.uppercased())")
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)
            Text("Tap a wall to add a corner · Double-tap to curve · Tap the curve handle to flip · Drag handle to adjust depth · Long-press a corner to delete")
                .font(SBFont.caption)
                .foregroundStyle(Color.sbCharcoal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Canvas
    //
    // The canvas fits the room into the available area with a small margin,
    // preserving aspect ratio. All hit-tests and drags work in screen coords;
    // we convert to / from room space (room pixels — the on-disk unit) at
    // the boundaries.
    private func traceCanvas(in size: CGSize) -> some View {
        let layout = canvasLayout(canvasSize: size)
        let imageRect = CGRect(
            x: layout.offsetX,
            y: layout.offsetY,
            width: roomWidth * layout.scale,
            height: roomHeight * layout.scale
        )
        return ZStack {
            // Floor-plan reference image (when provided) sits beneath
            // everything at half-opacity so corners + edges read clearly.
            if let img = floorPlanImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: imageRect.width, height: imageRect.height)
                    .clipped()
                    .opacity(0.5)
                    .position(x: imageRect.midX, y: imageRect.midY)
                    .allowsHitTesting(false)
            }

            // Filled outline
            shapeFillPath(layout: layout)
                .fill(Color.sbChampagne.opacity(floorPlanImage == nil ? 0.35 : 0.18))

            shapeOutlinePath(layout: layout)
                .stroke(Color.sbGoldDk, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            // Tap targets along each edge — invisible thick segments. Hit
            // detection uses point-to-segment distance; we render an overlay
            // capsule on each edge so the user has a visible affordance for
            // "tap here to add a corner".
            ForEach(0..<displayedPoints.count, id: \.self) { i in
                let a = displayedPoints[i]
                let b = displayedPoints[(i + 1) % displayedPoints.count]
                let mid = midpoint(a, b, layout: layout)
                let edgeLen = distanceUnits(a, b)

                // Edge label
                Text(String(format: "%.0f%@", edgeLen, unitLabel))
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbCharcoal)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.sbIvory.opacity(0.85))
                    .clipShape(Capsule())
                    .position(mid)
                    .allowsHitTesting(false)
            }

            // Tap-to-add-corner / double-tap-to-curve: shared transparent
            // layer covering the canvas. Single tap on a wall inserts a
            // corner; double tap on a wall toggles a curve (semicircle by
            // default, sweep outward). count:2 is checked first so the
            // single-tap handler defers automatically.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { location in
                    if let edgeIndex = nearestEdgeIndex(to: location, layout: layout, threshold: 28) {
                        toggleArcOnWall(edgeIndex: edgeIndex)
                    }
                }
                .onTapGesture { location in
                    if let edgeIndex = nearestEdgeIndex(to: location, layout: layout, threshold: 28) {
                        insertCorner(after: edgeIndex, at: location, layout: layout)
                    }
                }

            // Corner handles. Drawn last so they sit above the tap layer.
            ForEach(displayedPoints.indices, id: \.self) { i in
                let screenPos = roomToScreen(displayedPoints[i], layout: layout)
                cornerHandle(index: i, isDragging: draggingIndex == i)
                    .position(screenPos)
                    .gesture(cornerDragGesture(for: i, layout: layout))
                    .onLongPressGesture {
                        if points.count > 3 { pendingDelete = i }
                        else { HapticEngine.error() }
                    }
            }

            // Arc apex handles — one per curved wall. The handle is the
            // canonical control for an existing curve:
            //   • TAP   → flip the bulge to the other side of the chord
            //   • DRAG  → adjust depth (drag past the chord also flips)
            // Smaller than corner handles so they read as adjustments,
            // not anchors. Double-tap on the wall itself just adds /
            // removes the curve — once it exists, the handle takes over.
            ForEach(displayedPoints.indices, id: \.self) { i in
                if let arc = displayedPoints[i].arc {
                    let prev = displayedPoints[(i - 1 + displayedPoints.count) % displayedPoints.count]
                    let curr = displayedPoints[i]
                    let apexRoom = arcApex(start: prev, end: curr, arc: arc)
                    let apexScreen = CGPoint(
                        x: apexRoom.x * layout.scale + layout.offsetX,
                        y: apexRoom.y * layout.scale + layout.offsetY
                    )
                    let underlyingIdx = underlyingIndex(forDisplayed: i)
                    arcApexHandle()
                        .position(apexScreen)
                        .gesture(arcApexDragGesture(forEndIndex: underlyingIdx, layout: layout))
                        .onTapGesture { flipArcDirection(forEndIndex: underlyingIdx) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func arcApexHandle() -> some View {
        ZStack {
            Circle()
                .fill(Color.sbIvory)
                .frame(width: 18, height: 18)
                .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
            Circle()
                .strokeBorder(Color.sbGoldDk, lineWidth: 1.5)
                .frame(width: 18, height: 18)
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.sbGoldDk)
        }
        .contentShape(Circle().inset(by: -6))
    }

    private func cornerHandle(index: Int, isDragging: Bool) -> some View {
        ZStack {
            Circle()
                .fill(Color.sbIvory)
                .frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.2), radius: isDragging ? 6 : 2, x: 0, y: isDragging ? 4 : 1)
            Circle()
                .strokeBorder(Color.sbGoldDk, lineWidth: 2)
                .frame(width: 28, height: 28)
            Text("\(index + 1)")
                .font(SBFont.caption)
                .foregroundStyle(Color.sbGoldDk)
        }
        .scaleEffect(isDragging ? 1.2 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isDragging)
    }

    // MARK: Bottom toolbar
    //
    // Two rows. Top row = transforms that change the polygon as a
    // whole (scale ±5%, rotate ±15°) — web parity with App.jsx
    // RoomEditorModal phase 2 (scalePts / rotatePts). Bottom row =
    // mirror toggles + reset that already shipped before scale.

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                toolButton(label: "Smaller", icon: "minus.magnifyingglass", isOn: false) {
                    scalePoints(by: 0.95)
                }
                toolButton(label: "Bigger", icon: "plus.magnifyingglass", isOn: false) {
                    scalePoints(by: 1.05)
                }
                toolButton(label: "Rotate -15°", icon: "rotate.left", isOn: false) {
                    rotatePoints(byDegrees: -15)
                }
                toolButton(label: "Rotate +15°", icon: "rotate.right", isOn: false) {
                    rotatePoints(byDegrees: 15)
                }
            }
            HStack(spacing: 10) {
                toolButton(label: "Flip H", icon: "arrow.left.and.right", isOn: flipH) {
                    flipH.toggle()
                    HapticEngine.selection()
                }
                toolButton(label: "Flip V", icon: "arrow.up.and.down", isOn: flipV) {
                    flipV.toggle()
                    HapticEngine.selection()
                }
                toolButton(label: "Reset", icon: "arrow.counterclockwise", isOn: false) {
                    points = RoomShapePresets.defaultPoints(
                        shape: currentShape, width: roomWidth, height: roomHeight
                    )
                    flipH = false
                    flipV = false
                    HapticEngine.error()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.sbIvory2)
    }

    /// Scale every polygon point about the centroid by `factor`.
    /// Direct port of web App.jsx:9481 scalePts. Used by ±5% buttons.
    private func scalePoints(by factor: Double) {
        guard points.count >= 3 else { return }
        let cx = points.map(\.x).reduce(0, +) / Double(points.count)
        let cy = points.map(\.y).reduce(0, +) / Double(points.count)
        points = points.map { p in
            RoomPoint(
                x: (cx + (p.x - cx) * factor).rounded(),
                y: (cy + (p.y - cy) * factor).rounded(),
                arc: p.arc
            )
        }
        HapticEngine.selection()
    }

    /// Rotate every polygon point about the centroid by `angleDegrees`.
    /// Port of web App.jsx:9488 rotatePts.
    private func rotatePoints(byDegrees angleDegrees: Double) {
        guard points.count >= 3 else { return }
        let cx = points.map(\.x).reduce(0, +) / Double(points.count)
        let cy = points.map(\.y).reduce(0, +) / Double(points.count)
        let rad = angleDegrees * .pi / 180
        let cos = Foundation.cos(rad)
        let sin = Foundation.sin(rad)
        points = points.map { p in
            let dx = p.x - cx
            let dy = p.y - cy
            return RoomPoint(
                x: (cx + dx * cos - dy * sin).rounded(),
                y: (cy + dx * sin + dy * cos).rounded(),
                arc: p.arc
            )
        }
        HapticEngine.selection()
    }

    private func toolButton(label: String, icon: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                Text(label)
                    .font(SBFont.caption)
            }
            .foregroundStyle(isOn ? Color.sbGoldDk : Color.sbCharcoal)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isOn ? Color.sbChampagne : Color.sbIvory)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
        }
        .buttonStyle(.plain)
    }

    // MARK: Coordinate transforms
    //
    // Room (model) space is in pixels: 0..roomWidth × 0..roomHeight. Canvas
    // (screen) space is the SwiftUI view's local frame. Layout precomputes
    // the scale + offset so all conversions are O(1).

    private struct CanvasLayout {
        let scale: Double
        let offsetX: Double
        let offsetY: Double
    }

    private func canvasLayout(canvasSize: CGSize) -> CanvasLayout {
        // Margin reserves space for corner handles (28pt circles) and arc
        // apex handles to extend past the polygon edge without clipping.
        let margin: Double = 36
        let availW = max(canvasSize.width - 2 * margin, 1)
        let availH = max(canvasSize.height - 2 * margin, 1)
        // Fit to the actual displayed-polygon bounding box, NOT to
        // roomWidth/roomHeight. Scaling the polygon up via the Bigger
        // tool used to push points beyond the rect — the polygon would
        // visually clip and the user couldn't see the edges. Fitting to
        // the live bbox keeps the whole shape on screen always. Falls
        // back to the rect dims when no points are loaded yet.
        let pts = displayedPoints
        let fitW: Double
        let fitH: Double
        let originX: Double
        let originY: Double
        if pts.count >= 2 {
            let minX = pts.map(\.x).min() ?? 0
            let maxX = pts.map(\.x).max() ?? roomWidth
            let minY = pts.map(\.y).min() ?? 0
            let maxY = pts.map(\.y).max() ?? roomHeight
            fitW = max(maxX - minX, 1)
            fitH = max(maxY - minY, 1)
            originX = minX
            originY = minY
        } else {
            fitW = max(roomWidth, 1)
            fitH = max(roomHeight, 1)
            originX = 0
            originY = 0
        }
        let scale = min(availW / fitW, availH / fitH)
        let drawnW = fitW * scale
        let drawnH = fitH * scale
        // Subtract originX*scale so a point at x=originX maps to the
        // left side of the visible canvas (polygon's leftmost edge).
        let offsetX = margin + (availW - drawnW) / 2 - originX * scale
        let offsetY = margin + (availH - drawnH) / 2 - originY * scale
        return CanvasLayout(scale: scale, offsetX: offsetX, offsetY: offsetY)
    }

    private func roomToScreen(_ p: RoomPoint, layout: CanvasLayout) -> CGPoint {
        CGPoint(
            x: p.x * layout.scale + layout.offsetX,
            y: p.y * layout.scale + layout.offsetY
        )
    }

    private func screenToRoom(_ p: CGPoint, layout: CanvasLayout) -> RoomPoint {
        RoomPoint(
            x: (Double(p.x) - layout.offsetX) / layout.scale,
            y: (Double(p.y) - layout.offsetY) / layout.scale
        )
    }

    /// Display order honours flip flags so the visible polygon mirrors what
    /// the user will see on the editor canvas after Apply. Hit tests below
    /// always work against this displayed order so taps line up with what
    /// the user sees, then we map back to the underlying `points` array.
    private var displayedPoints: [RoomPoint] {
        points.map { p in
            var f = p
            if flipH { f.x = roomWidth - p.x }
            if flipV { f.y = roomHeight - p.y }
            return f
        }
    }

    // MARK: Drawing helpers

    private func shapeOutlinePath(layout: CanvasLayout) -> Path {
        var path = Path()
        guard !displayedPoints.isEmpty else { return path }
        let first = roomToScreen(displayedPoints[0], layout: layout)
        path.move(to: first)
        // Walk every segment. If the END point has an arc, render
        // the segment as a circular arc (we author rx == ry on
        // double-tap toggle, and the canvas's SVG-arc renderer
        // handles the same data identically). Else straight line.
        for i in 1..<displayedPoints.count {
            appendSegment(
                from: displayedPoints[i - 1],
                to: displayedPoints[i],
                into: &path,
                layout: layout
            )
        }
        // Close: arc on the FIRST point means the closing segment is
        // also curved — match how CanvasViewController.roomBezierPath
        // closes the polygon.
        if displayedPoints[0].arc != nil {
            appendSegment(
                from: displayedPoints[displayedPoints.count - 1],
                to: displayedPoints[0],
                into: &path,
                layout: layout
            )
        }
        path.closeSubpath()
        return path
    }

    /// Append a single edge to `path`. Straight when the destination
    /// has no arc; circular arc when it does. Mirrors the trace's
    /// own toggleArcOnWall (rx == ry) so the visual matches what the
    /// user just authored.
    private func appendSegment(from a: RoomPoint, to b: RoomPoint, into path: inout Path, layout: CanvasLayout) {
        let endScreen = roomToScreen(b, layout: layout)
        guard let arc = b.arc, arc.rx > 0 else {
            path.addLine(to: endScreen)
            return
        }
        let startScreen = roomToScreen(a, layout: layout)
        let r = arc.rx * layout.scale
        let chord = (
            (endScreen.x - startScreen.x) * (endScreen.x - startScreen.x) +
            (endScreen.y - startScreen.y) * (endScreen.y - startScreen.y)
        ).squareRoot()
        // Arc center sits perpendicular to the chord, offset by the
        // height of the circular segment (h = √(r² − (chord/2)²)).
        let half = chord / 2
        let hSq = r * r - half * half
        let h = hSq > 0 ? hSq.squareRoot() : 0
        let mx = (startScreen.x + endScreen.x) / 2
        let my = (startScreen.y + endScreen.y) / 2
        // Perpendicular unit vector — rotate (end - start) 90° one
        // way or the other based on sweep flag. SVG sweep 1 =
        // clockwise.
        let dx = endScreen.x - startScreen.x
        let dy = endScreen.y - startScreen.y
        let len = max(1, (dx * dx + dy * dy).squareRoot())
        let perpX = -dy / len
        let perpY = dx / len
        let sign: CGFloat = arc.sweep == 1 ? -1 : 1
        let centerX = mx + sign * perpX * h
        let centerY = my + sign * perpY * h
        let center = CGPoint(x: centerX, y: centerY)
        let startAngle = atan2(startScreen.y - centerY, startScreen.x - centerX)
        let endAngle = atan2(endScreen.y - centerY, endScreen.x - centerX)
        // SwiftUI's clockwise flag is INVERTED relative to what you'd
        // expect (Apple's coordinate system) — `clockwise: true` draws
        // counter-clockwise on screen. Sweep 1 == clockwise on web,
        // so we pass `clockwise: false` for sweep 1.
        path.addArc(
            center: center,
            radius: r,
            startAngle: .radians(startAngle),
            endAngle: .radians(endAngle),
            clockwise: arc.sweep != 1
        )
    }

    private func shapeFillPath(layout: CanvasLayout) -> Path {
        shapeOutlinePath(layout: layout)
    }

    private func midpoint(_ a: RoomPoint, _ b: RoomPoint, layout: CanvasLayout) -> CGPoint {
        let sa = roomToScreen(a, layout: layout)
        let sb = roomToScreen(b, layout: layout)
        return CGPoint(x: (sa.x + sb.x) / 2, y: (sa.y + sb.y) / 2)
    }

    private func distanceUnits(_ a: RoomPoint, _ b: RoomPoint) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        let pxDist = (dx * dx + dy * dy).squareRoot()
        return pxDist / pixelsPerUnit
    }

    // MARK: Hit testing

    /// Returns the index `i` of the edge between `displayedPoints[i]` and
    /// `displayedPoints[i+1]` whose perpendicular distance from `point` is
    /// the smallest, OR nil if no edge is within `threshold` pixels.
    /// Excludes edges where the point would land near an existing corner
    /// (so a finger tap on a handle doesn't double-fire as add-corner).
    private func nearestEdgeIndex(to point: CGPoint, layout: CanvasLayout, threshold: Double) -> Int? {
        var bestIdx: Int? = nil
        var bestDist = threshold

        // Skip if the point is too close to any existing corner.
        for p in displayedPoints {
            let s = roomToScreen(p, layout: layout)
            if hypot(Double(s.x - point.x), Double(s.y - point.y)) < 24 {
                return nil
            }
        }

        for i in 0..<displayedPoints.count {
            let a = roomToScreen(displayedPoints[i], layout: layout)
            let b = roomToScreen(displayedPoints[(i + 1) % displayedPoints.count], layout: layout)
            let d = pointToSegmentDistance(point: point, a: a, b: b)
            if d < bestDist {
                bestDist = d
                bestIdx = i
            }
        }
        return bestIdx
    }

    private func pointToSegmentDistance(point p: CGPoint, a: CGPoint, b: CGPoint) -> Double {
        let abx = Double(b.x - a.x), aby = Double(b.y - a.y)
        let apx = Double(p.x - a.x), apy = Double(p.y - a.y)
        let len2 = abx * abx + aby * aby
        if len2 == 0 { return hypot(apx, apy) }
        let t = max(0, min(1, (apx * abx + apy * aby) / len2))
        let projX = Double(a.x) + t * abx
        let projY = Double(a.y) + t * aby
        return hypot(Double(p.x) - projX, Double(p.y) - projY)
    }

    // MARK: Mutations

    /// Toggle a curve on the wall between displayedPoints[edgeIndex]
    /// and displayedPoints[edgeIndex+1]. Add a semicircular bulge
    /// outward from the polygon centroid if none exists, otherwise
    /// remove the existing curve. To FLIP an existing curve to the
    /// other side, tap the apex handle (see flipArcDirection).
    private func toggleArcOnWall(edgeIndex: Int) {
        guard points.count >= 3 else { return }
        let endIdx = (edgeIndex + 1) % points.count
        var working = points
        if working[endIdx].arc != nil {
            // Already curved → remove
            working[endIdx] = RoomPoint(x: working[endIdx].x, y: working[endIdx].y, arc: nil)
            HapticEngine.error()
        } else {
            // None → outward semicircle (bulge away from polygon centroid)
            let s = working[edgeIndex]
            let e = working[endIdx]
            let chord = ((e.x - s.x) * (e.x - s.x) + (e.y - s.y) * (e.y - s.y)).squareRoot()
            let r = max(1, chord / 2)
            let cx = working.map(\.x).reduce(0, +) / Double(working.count)
            let cy = working.map(\.y).reduce(0, +) / Double(working.count)
            let mx = (s.x + e.x) / 2
            let my = (s.y + e.y) / 2
            let cross = (e.x - s.x) * (cy - my) - (e.y - s.y) * (cx - mx)
            let outwardSweep = cross > 0 ? 0 : 1
            working[endIdx] = RoomPoint(
                x: working[endIdx].x,
                y: working[endIdx].y,
                arc: RoomArc(rx: r, ry: r, sweep: outwardSweep, largeArc: 0)
            )
            HapticEngine.selection()
        }
        points = working
    }

    /// Flip an existing arc to the opposite side of its chord. Triggered
    /// by tapping the apex handle. Preserves radius, just inverts sweep.
    private func flipArcDirection(forEndIndex endIdx: Int) {
        guard points.indices.contains(endIdx), let arc = points[endIdx].arc else { return }
        let p = points[endIdx]
        points[endIdx] = RoomPoint(
            x: p.x, y: p.y,
            arc: RoomArc(rx: arc.rx, ry: arc.ry, sweep: 1 - arc.sweep, largeArc: 0)
        )
        HapticEngine.selection()
    }

    /// Compute the apex of an arc in ROOM coordinates given the chord
    /// endpoints + arc parameters. The apex is the point on the arc
    /// that's farthest from the chord — the natural place for a
    /// drag handle. h = sagitta = r - sqrt(r² - (chord/2)²).
    private func arcApex(start: RoomPoint, end: RoomPoint, arc: RoomArc) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let chord = (dx * dx + dy * dy).squareRoot()
        let half = chord / 2
        let r = max(arc.rx, half) // clamp so sqrt arg can't go negative
        let h = r - max(0, (r * r - half * half).squareRoot())
        let mx = (start.x + end.x) / 2
        let my = (start.y + end.y) / 2
        let len = max(1, chord)
        // Perpendicular to the chord, normalized. Sweep flag picks
        // which side of the chord the arc bulges to.
        let perpX = -dy / len
        let perpY = dx / len
        let sign: Double = arc.sweep == 1 ? -1 : 1
        return CGPoint(x: mx + sign * perpX * h, y: my + sign * perpY * h)
    }

    /// User dragged the apex handle for the wall ending at `endIdx`.
    /// Recompute the arc's radius (and sweep direction, if the user
    /// pulled the handle past the chord to the other side) so the arc
    /// passes through the new apex location. Result is always a
    /// circular arc (rx == ry) since that's all we author.
    private func updateArc(forEndIndex endIdx: Int, newApex roomApex: CGPoint) {
        guard points.indices.contains(endIdx), points.count >= 3 else { return }
        let startIdx = (endIdx - 1 + points.count) % points.count
        let s = points[startIdx]
        let e = points[endIdx]
        let dx = e.x - s.x
        let dy = e.y - s.y
        let chord = (dx * dx + dy * dy).squareRoot()
        guard chord > 0.5 else { return }
        let half = chord / 2
        let mx = (s.x + e.x) / 2
        let my = (s.y + e.y) / 2
        let len = max(1, chord)
        let perpX = -dy / len
        let perpY = dx / len
        // Signed distance from chord midpoint to apex along the
        // perpendicular. Sign tells us which side the arc bulges to.
        let signedH = (Double(roomApex.x) - mx) * perpX + (Double(roomApex.y) - my) * perpY
        let h = max(2.0, abs(signedH)) // floor so the arc never collapses
        // Radius from chord half + sagitta: r = (h² + half²) / (2h)
        let r = (h * h + half * half) / (2 * h)
        // Existing sweep flag is sweep==1 → sign=-1 (perpendicular flipped).
        // Recompute sweep so the arc lives on the same side the user
        // dragged the handle to: if signedH > 0 we want sign=+1 (sweep=0),
        // else sweep=1.
        let sweep = signedH > 0 ? 0 : 1
        points[endIdx] = RoomPoint(
            x: e.x, y: e.y,
            arc: RoomArc(rx: r, ry: r, sweep: sweep, largeArc: 0)
        )
    }

    private func insertCorner(after edgeIndex: Int, at screenPoint: CGPoint, layout: CanvasLayout) {
        // edgeIndex is in displayedPoints order. With flips applied, that's a
        // mirrored view of points. We resolve the insertion slot in the
        // underlying array based on whether either flip is active.
        let n = points.count
        let insertSlot: Int
        if flipH != flipV {
            // Flipping H xor V reverses winding order in the displayed polygon.
            // The displayed edge between indices i and i+1 corresponds to the
            // underlying edge between (n-1-i) and (n-2-i).
            insertSlot = ((n - 1 - edgeIndex) + n) % n
        } else {
            insertSlot = (edgeIndex + 1) % n
        }
        // Convert the screen tap back to room space, then un-flip so the
        // stored point lives in canonical (un-flipped) coordinates.
        var roomPt = screenToRoom(screenPoint, layout: layout)
        if flipH { roomPt.x = roomWidth - roomPt.x }
        if flipV { roomPt.y = roomHeight - roomPt.y }
        points.insert(roomPt, at: insertSlot)
        HapticEngine.selection()
    }

    private func cornerDragGesture(for displayedIndex: Int, layout: CanvasLayout) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                draggingIndex = displayedIndex
                // Convert drag location → un-flipped room coords.
                var roomPt = screenToRoom(value.location, layout: layout)
                if flipH { roomPt.x = roomWidth - roomPt.x }
                if flipV { roomPt.y = roomHeight - roomPt.y }
                // displayedPoints index → underlying index
                let underlyingIdx = underlyingIndex(forDisplayed: displayedIndex)
                if points.indices.contains(underlyingIdx) {
                    // No clamp to the room rect — scaled-up polygons can
                    // legitimately live outside [0, roomWidth/roomHeight].
                    // The fit-to-bbox layout keeps everything visible.
                    points[underlyingIdx] = RoomPoint(x: roomPt.x, y: roomPt.y, arc: points[underlyingIdx].arc)
                }
            }
            .onEnded { _ in
                draggingIndex = nil
                HapticEngine.light()
            }
    }

    /// Drag handle for an arc apex. Pulls the curve in or out; pulling
    /// it across the chord flips the bulge direction. Updates the arc
    /// in place via `updateArc`.
    private func arcApexDragGesture(forEndIndex endIdx: Int, layout: CanvasLayout) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                var roomPt = screenToRoom(value.location, layout: layout)
                if flipH { roomPt.x = roomWidth - roomPt.x }
                if flipV { roomPt.y = roomHeight - roomPt.y }
                updateArc(forEndIndex: endIdx, newApex: CGPoint(x: roomPt.x, y: roomPt.y))
            }
            .onEnded { _ in
                HapticEngine.light()
            }
    }

    private func underlyingIndex(forDisplayed i: Int) -> Int {
        let n = points.count
        guard n > 0 else { return 0 }
        if flipH != flipV {
            // Flipping H xor V reverses winding direction visually, but our
            // displayedPoints array applies flips per-coordinate without
            // reversing order — so displayed index always equals underlying
            // index. The reversal only matters for *edge* index → insertion
            // slot mapping in insertCorner above.
            return i
        }
        return i
    }
}
