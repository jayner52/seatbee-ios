import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var guestListText = ""
    @State private var isProcessing = false
    @State private var detectedGuests: [Guest] = []
    @State private var showLayoutPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SBNavHeader(
                    title: "New plan",
                    backLabel: "Cancel",
                    backAction: { dismiss() }
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: SBSpacing.sectionGap) {
                        // Headline
                        Text("Start with your guest list")
                            .font(SBFont.displayLarge)
                            .foregroundStyle(Color.sbCharcoal)

                        Text("Paste from anywhere. We'll detect +1s, diets, accessibility.")
                            .font(SBFont.bodySmall)
                            .foregroundStyle(Color.sbWarm)

                        // Paste textarea
                        pasteArea

                        // Upload alternative
                        Button {} label: {
                            Text("Or upload CSV / Excel")
                                .font(SBFont.bodySmall)
                                .foregroundStyle(Color.sbGoldDk)
                                .underline()
                        }
                        .buttonStyle(.plain)

                        // Detected preview
                        if !detectedGuests.isEmpty {
                            detectedPreview
                        }

                        // Continue CTA
                        SBButton(
                            title: isProcessing ? "Detecting..." : "Continue",
                            icon: isProcessing ? nil : "arrow.right",
                            variant: .gold,
                            fullWidth: true
                        ) {
                            processGuestList()
                        }
                        .disabled(guestListText.isEmpty || isProcessing)
                        .opacity(guestListText.isEmpty ? 0.5 : 1)

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, SBSpacing.screenMargin)
                    .padding(.top, SBSpacing.sectionGap)
                }
            }
            .background(Color.sbIvory)
        }
    }

    // MARK: - Paste Area

    private var pasteArea: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: SBRadius.button)
                .strokeBorder(Color.sbWarm2, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .background(
                    RoundedRectangle(cornerRadius: SBRadius.button)
                        .fill(Color.sbIvory2)
                )

            if guestListText.isEmpty {
                Text("Sarah Chen, Bride's side, vegetarian\nJon Park + guest\nThe Martinez Family (4)\n...")
                    .font(SBFont.bodySmall)
                    .foregroundStyle(Color.sbWarm2)
                    .padding(16)
            }

            TextEditor(text: $guestListText)
                .font(SBFont.bodySmall)
                .scrollContentBackground(.hidden)
                .padding(12)
        }
        .frame(height: 200)
    }

    // MARK: - Detected Preview

    private var detectedPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DETECTED")
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbGoldDk)
                .letterSpacing(1.5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(detectedGuests.prefix(6)), id: \.id) { guest in
                        SBChip(text: guest.displayName, variant: .gold)
                    }
                    if detectedGuests.count > 6 {
                        SBChip(text: "+\(detectedGuests.count - 6) more", variant: .default)
                    }
                }
            }
        }
    }

    // MARK: - Logic

    private func processGuestList() {
        isProcessing = true
        Task {
            do {
                detectedGuests = try await appState.ai.parseGuestList(text: guestListText)
                HapticEngine.success()
            } catch {
                // Handle error
                HapticEngine.error()
            }
            isProcessing = false
        }
    }
}

#Preview {
    OnboardingView()
        .environment(AppState())
}
