import SwiftUI
import PhotosUI

struct RoomSetupSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var roomWidth = ""
    @State private var roomHeight = ""
    @State private var useMetric = false
    @State private var selectedShape = "rect"
    @State private var showImagePicker = false
    @State private var selectedImage: PhotosPickerItem?
    @State private var floorPlanImage: UIImage?
    @State private var isAnalyzing = false
    @State private var analysisResult: String?

    private let shapes = [
        ("rect", "Rectangle", "rectangle"),
        ("l", "L-Shape", "l.rectangle.roundedbottom"),
        ("t", "T-Shape", "t.square"),
        ("u", "U-Shape", "u.square"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Room shape
                    formSection("ROOM SHAPE") {
                        HStack(spacing: 10) {
                            ForEach(shapes, id: \.0) { shape in
                                Button {
                                    selectedShape = shape.0
                                    HapticEngine.selection()
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: shape.2)
                                            .font(.system(size: 24))
                                            .foregroundStyle(selectedShape == shape.0 ? Color.sbGoldDk : Color.sbWarm)
                                        Text(shape.1)
                                            .font(SBFont.capsLabel)
                                            .foregroundStyle(selectedShape == shape.0 ? Color.sbGoldDk : Color.sbWarm)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(12)
                                    .background(selectedShape == shape.0 ? Color.sbChampagne : Color.sbIvory2)
                                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
                                }
                                .buttonStyle(.plain)
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
        if let w = plan.roomWidth { roomWidth = String(format: "%.0f", w) }
        if let h = plan.roomHeight { roomHeight = String(format: "%.0f", h) }
    }

    private func applySetup() {
        guard var plan = appState.activePlan else { return }
        plan.roomWidth = Double(roomWidth)
        plan.roomHeight = Double(roomHeight)
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
