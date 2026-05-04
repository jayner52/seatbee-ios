import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var step = 1
    @State private var partnerName1 = ""
    @State private var partnerName2 = ""
    @State private var weddingDate = Date()
    @State private var hasSetDate = false
    @State private var venueName = ""
    @State private var guestListText = ""
    @State private var isProcessing = false
    @State private var detectedGuests: [Guest] = []
    @State private var isCreating = false
    @State private var errorMessage: String?

    private var planName: String {
        if !partnerName1.isEmpty && !partnerName2.isEmpty {
            return "\(partnerName1) & \(partnerName2)"
        } else if !partnerName1.isEmpty {
            return partnerName1
        }
        return "My Wedding"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress dots
                progressDots
                    .padding(.top, 16)

                ScrollView {
                    VStack(spacing: 0) {
                        switch step {
                        case 1: weddingDetailsStep
                        case 2: guestListStep
                        case 3: creatingStep
                        default: EmptyView()
                        }
                    }
                    .padding(.horizontal, SBSpacing.screenMargin)
                    .padding(.top, 24)
                }

                // Bottom CTA
                if step < 3 {
                    bottomCTA
                        .padding(.horizontal, SBSpacing.screenMargin)
                        .padding(.bottom, 32)
                }
            }
            .background(Color.sbIvory)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step > 1 && step < 3 {
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
                    Button("Cancel") { dismiss() }
                        .font(SBFont.bodySmall)
                        .foregroundStyle(Color.sbWarm)
                }
            }
        }
    }

    // MARK: - Progress Dots

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

    // MARK: - Step 1: Wedding Details

    private var weddingDetailsStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Hero
            VStack(spacing: 8) {
                Image("SeatbeeLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 56, height: 56)

                Text("Plan your wedding")
                    .font(SBFont.displayLarge)
                    .foregroundStyle(Color.sbCharcoal)

                Text("Tell us about your big day")
                    .font(SBFont.body)
                    .foregroundStyle(Color.sbWarm)
            }
            .frame(maxWidth: .infinity)

            // Partner names
            VStack(alignment: .leading, spacing: 8) {
                Text("WHO'S GETTING MARRIED?")
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbWarm)
                    .letterSpacing(1.5)

                HStack(spacing: 12) {
                    TextField("Partner 1", text: $partnerName1)
                        .font(SBFont.body)
                        .padding(14)
                        .background(Color.sbIvory2)
                        .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
                        .overlay(
                            RoundedRectangle(cornerRadius: SBRadius.button)
                                .strokeBorder(Color.sbLine2, lineWidth: 1)
                        )

                    Text("&")
                        .font(SBFont.fraunces(24, weight: .medium))
                        .foregroundStyle(Color.sbGold)

                    TextField("Partner 2", text: $partnerName2)
                        .font(SBFont.body)
                        .padding(14)
                        .background(Color.sbIvory2)
                        .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
                        .overlay(
                            RoundedRectangle(cornerRadius: SBRadius.button)
                                .strokeBorder(Color.sbLine2, lineWidth: 1)
                        )
                }
            }

            // Preview of plan name
            if !partnerName1.isEmpty {
                Text("\"\(planName)'s Wedding\"")
                    .font(SBFont.fraunces(18, weight: .medium))
                    .foregroundStyle(Color.sbGoldDk)
                    .italic()
                    .frame(maxWidth: .infinity)
            }

            // Wedding date
            VStack(alignment: .leading, spacing: 8) {
                Text("WHEN'S THE BIG DAY?")
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbWarm)
                    .letterSpacing(1.5)

                DatePicker("Wedding date", selection: $weddingDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .font(SBFont.body)
                    .tint(Color.sbGold)
                    .onChange(of: weddingDate) { _, _ in hasSetDate = true }
            }

            // Venue
            VStack(alignment: .leading, spacing: 8) {
                Text("WHERE? (OPTIONAL)")
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbWarm)
                    .letterSpacing(1.5)

                TextField("The Garden House", text: $venueName)
                    .font(SBFont.body)
                    .padding(14)
                    .background(Color.sbIvory2)
                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
                    .overlay(
                        RoundedRectangle(cornerRadius: SBRadius.button)
                            .strokeBorder(Color.sbLine2, lineWidth: 1)
                    )
            }

            Spacer(minLength: 40)
        }
    }

    // MARK: - Step 2: Guest List

    private var guestListStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your guest list")
                    .font(SBFont.displayLarge)
                    .foregroundStyle(Color.sbCharcoal)

                Text("Paste from anywhere — we'll detect names, +1s, diets, and sides.")
                    .font(SBFont.bodySmall)
                    .foregroundStyle(Color.sbWarm)
            }

            // Paste area
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: SBRadius.button)
                    .strokeBorder(Color.sbWarm2, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .background(
                        RoundedRectangle(cornerRadius: SBRadius.button)
                            .fill(Color.sbIvory2)
                    )

                if guestListText.isEmpty {
                    Text("Sarah Chen, Bride's side, vegetarian\nJon Park + guest, Groom's family\nThe Martinez Family (4)\n...")
                        .font(SBFont.bodySmall)
                        .foregroundStyle(Color.sbWarm2)
                        .padding(16)
                }

                TextEditor(text: $guestListText)
                    .font(SBFont.bodySmall)
                    .scrollContentBackground(.hidden)
                    .padding(12)
            }
            .frame(height: 180)

            // Detected preview
            if !detectedGuests.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(detectedGuests.count) GUESTS DETECTED")
                        .font(SBFont.capsLabel)
                        .foregroundStyle(Color.sbGoldDk)
                        .letterSpacing(1.5)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(detectedGuests.prefix(8)), id: \.id) { guest in
                                SBChip(text: guest.displayName, variant: .gold)
                            }
                            if detectedGuests.count > 8 {
                                SBChip(text: "+\(detectedGuests.count - 8)", variant: .default)
                            }
                        }
                    }
                }
            }

            if isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Detecting guests...")
                        .font(SBFont.body)
                        .foregroundStyle(Color.sbWarm)
                }
                .frame(maxWidth: .infinity)
            }

            // Skip option
            Button {
                createPlan(withGuests: false)
            } label: {
                Text("Skip — I'll add guests later")
                    .font(SBFont.bodySmall)
                    .foregroundStyle(Color.sbWarm)
                    .underline()
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            Spacer(minLength: 40)
        }
    }

    // MARK: - Step 3: Creating

    private var creatingStep: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 80)

            if isCreating {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(Color.sbGold)

                Text("Setting up your wedding...")
                    .font(SBFont.displaySmall)
                    .foregroundStyle(Color.sbCharcoal)

                Text("\(planName)'s Wedding")
                    .font(SBFont.fraunces(22, weight: .medium))
                    .foregroundStyle(Color.sbGoldDk)
                    .italic()
            } else if let errorMessage {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.sbError)
                Text(errorMessage)
                    .font(SBFont.body)
                    .foregroundStyle(Color.sbWarm)
                    .multilineTextAlignment(.center)

                SBButton(title: "Try again", variant: .primary) {
                    createPlan(withGuests: !guestListText.isEmpty)
                }
            }

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
                .disabled(partnerName1.isEmpty)
                .opacity(partnerName1.isEmpty ? 0.5 : 1)

            case 2:
                if guestListText.isEmpty {
                    SBButton(title: "Create plan", icon: "sparkles", variant: .gold, fullWidth: true) {
                        createPlan(withGuests: false)
                    }
                } else if detectedGuests.isEmpty {
                    SBButton(title: "Detect guests", icon: "sparkles", variant: .gold, fullWidth: true) {
                        detectGuests()
                    }
                    .disabled(isProcessing)
                } else {
                    SBButton(title: "Create with \(detectedGuests.count) guests", icon: "sparkles", variant: .gold, fullWidth: true) {
                        createPlan(withGuests: true)
                    }
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

    private func createPlan(withGuests: Bool) {
        withAnimation(.seatbee) { step = 3 }
        isCreating = true
        errorMessage = nil

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        Task {
            do {
                let guestDTOs: [GuestDTO]? = withGuests && !detectedGuests.isEmpty
                    ? detectedGuests.map { guest in
                        GuestDTO(
                            id: guest.id, name: guest.name, firstName: guest.firstName,
                            lastName: guest.lastName, email: guest.email,
                            categories: guest.categories, dietary: guest.dietary,
                            notes: guest.notes, rsvp: guest.rsvp.rawValue,
                            side: guest.side.rawValue, vip: guest.vip,
                            accessibility: guest.accessibility, plusOne: guest.plusOne,
                            party: guest.party, display: guest.displayName,
                            dietaryTags: guest.dietaryTags, highChair: guest.highChair,
                            groupIds: guest.groupIds, isBride: guest.isBride,
                            isGroom: guest.isGroom, meal: guest.meal,
                            createdAt: guest.guestCreatedAt
                        )
                    }
                    : nil

                let plan = try await appState.database.createPlan(
                    name: "\(planName)'s Wedding",
                    eventType: "wedding",
                    eventDate: hasSetDate ? dateFormatter.string(from: weddingDate) : nil,
                    venue: venueName.isEmpty ? nil : venueName,
                    guests: guestDTOs,
                    tables: nil
                )

                appState.activePlan = plan
                HapticEngine.success()

                // Brief pause then dismiss
                try? await Task.sleep(for: .seconds(0.8))
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
}

#Preview {
    OnboardingView()
        .environment(AppState())
}
