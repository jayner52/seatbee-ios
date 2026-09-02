import SwiftUI

/// One-time, skippable ask for an email address we can actually reach the user
/// at. Shown only to users whose sign-in address is unusable: Apple Hide My
/// Email relays, or accounts with no email at all.
///
/// Why this exists as its own surface rather than a field on
/// SignupConsentView: `signInWithApple` passes `skipConsent: true`
/// (AuthService) so Apple users never see that screen, and they're exactly the
/// cohort whose stored address is a relay. Everyone who *does* see the consent
/// screen already handed us a real inbox at sign-in, and it gets copied to
/// contact_email silently by backfillContactEmailIfMissing().
///
/// Deliberately not presented immediately after Sign in with Apple. AppRouter
/// gates it behind the feature tour, which keeps a beat between the SIWA sheet
/// and this ask.
///
/// Motion: a staggered entrance (mark, copy, field, then each benefit row),
/// a slow hover on the bee mark, and a spring on the Save button when the
/// address becomes valid. All native SwiftUI on the design-system tokens in
/// Motion.swift; no Rive/Lottie dependency for one screen. Everything
/// continuous is switched off under Reduce Motion.
struct ContactEmailSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var email = ""
    @State private var isSubmitting = false
    @State private var didSave = false
    /// Non-nil while there's something to tell the user. Covers both a
    /// malformed address and a write that didn't land, which need different
    /// wording: a network failure isn't the user's typo.
    @State private var errorMessage: String?

    /// Drives the entrance choreography. Flipped once on appear; every
    /// element keys its own delay off it.
    @State private var appeared = false
    /// Drives the bee's idle hover. Separate from `appeared` so the loop can
    /// start after the entrance settles instead of fighting it.
    @State private var hovering = false

    /// Format-valid and ready to save.
    private var canSave: Bool { EmailUtils.isValidFormat(email) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    emailSection
                        .entrance(appeared, delay: 0.18, reduceMotion: reduceMotion)
                    whatYouGet
                }
                .padding(.horizontal, SBSpacing.screenMargin)
                .padding(.top, 28)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)

            // Pinned so Save is always reachable regardless of screen height
            // or keyboard state.
            VStack(spacing: 4) {
                saveButton
                skipButton
            }
            .padding(.horizontal, SBSpacing.screenMargin)
            .padding(.bottom, 24)
            .entrance(appeared, delay: 0.42, reduceMotion: reduceMotion)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sbIvory)
        .onAppear {
            // One spring for the whole cascade; per-element delays do the
            // staggering. Under Reduce Motion the `entrance` modifier drops
            // the offset and scale, so this becomes a plain fade.
            withAnimation(.seatbeeSpring) { appeared = true }
            guard !reduceMotion else { return }
            // Let the entrance land before the idle hover starts.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    hovering = true
                }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            beeMark
                .padding(.bottom, 6)
            Text("Stay in the loop")
                .font(SBFont.displayLarge)
                .foregroundStyle(Color.sbCharcoal)
                .entrance(appeared, delay: 0.08, reduceMotion: reduceMotion)
            // Say why we're asking. The honest version lands better than a
            // generic "join our list", and it explains why we're asking at all
            // when the user already signed in with an email.
            Text(reasonCopy)
                .font(SBFont.body)
                .foregroundStyle(Color.sbWarm)
                .entrance(appeared, delay: 0.12, reduceMotion: reduceMotion)
        }
    }

    /// Brand mark with a soft champagne halo. The halo breathes and the bee
    /// drifts a few points, out of phase, so it reads as hovering rather than
    /// bouncing. Same `SeatbeeLogo` treatment as the dashboard hero.
    private var beeMark: some View {
        ZStack {
            Circle()
                .fill(Color.sbChampagne)
                .frame(width: 64, height: 64)
                .scaleEffect(hovering ? 1.08 : 0.92)
                .opacity(hovering ? 0.55 : 0.9)
            Image("SeatbeeLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .offset(y: hovering ? -3 : 3)
                .rotationEffect(.degrees(hovering ? 2 : -2))
        }
        .frame(width: 64, height: 64)
        // The mark leads the cascade: scale from small with the spring, so it
        // has a little overshoot the text elements don't.
        .scaleEffect(appeared ? 1 : 0.5)
        .opacity(appeared ? 1 : 0)
    }

    /// Tailored to why we can't reach them, since the two cases read very
    /// differently to a user.
    private var reasonCopy: String {
        if appState.auth.signInEmailIsAppleRelay {
            return "Sign in with Apple kept your email private, so we don't have a way to reach you. Add one and we'll only use it for the occasional important update."
        }
        return "We don't have an email on file for you. Add one and we'll only use it for the occasional important update."
    }

    // Field mirrors SignupConsentView.nameSection so the two screens read as
    // one family, with the email keyboard/content-type set from AuthView.
    private var emailSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR EMAIL")
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)
            // Placeholder is "Email address" rather than a sample address on
            // purpose: iOS data-detects an email-shaped placeholder and draws
            // it in link blue, which reads as tappable and doesn't match the
            // grey placeholders everywhere else in the app.
            TextField("Email address", text: $email)
                .font(SBFont.body)
                .padding(14)
                .background(Color.sbIvory2)
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
                .overlay(
                    RoundedRectangle(cornerRadius: SBRadius.button)
                        .strokeBorder(fieldBorder, lineWidth: canSave ? 1.5 : 1)
                        .animation(.seatbee, value: canSave)
                        .animation(.seatbee, value: errorMessage == nil)
                )
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .onSubmit { if canSave { save() } }
                .onChange(of: email) { errorMessage = nil }

            if let errorMessage {
                Text(errorMessage)
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbGoldDk)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text("Unsubscribe anytime. You can change or remove it in Settings.")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
                    .transition(.opacity)
            }
        }
        .animation(.seatbee, value: errorMessage)
    }

    /// Border tracks state: gold once the address is valid, dark gold on an
    /// error, hairline otherwise. A small, continuous cue that the Save button
    /// is about to light up.
    private var fieldBorder: Color {
        if errorMessage != nil { return .sbGoldDk }
        return canSave ? .sbGold : .sbLine
    }

    // What the address is actually for. Every row is something the campaign
    // sender does today (see api/admin.js segments) so we're not promising a
    // newsletter cadence that doesn't exist.
    private var whatYouGet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("WHAT WE'LL SEND")
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)
                .entrance(appeared, delay: 0.24, reduceMotion: reduceMotion)

            VStack(alignment: .leading, spacing: 0) {
                benefitRow(
                    index: 0,
                    icon: "envelope.badge",
                    title: "Notices about your plan",
                    detail: "Anything that affects your seating plan or your account."
                )
                Divider().overlay(Color.sbLine).padding(.leading, 60)
                benefitRow(
                    index: 1,
                    icon: "sparkles",
                    title: "New features, when they land",
                    detail: "Seatbee ships often. Hear about the useful ones."
                )
                Divider().overlay(Color.sbLine).padding(.leading, 60)
                benefitRow(
                    index: 2,
                    icon: "hand.raised",
                    title: "Never sold, never shared",
                    detail: "One sender, one-tap unsubscribe, and it stays with us."
                )
            }
            .background(Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: SBRadius.card)
                    .strokeBorder(Color.sbLine, lineWidth: 1)
            )
            .entrance(appeared, delay: 0.28, reduceMotion: reduceMotion)
        }
    }

    /// Rows cascade in 90ms apart after the card itself, and each icon does a
    /// single symbol bounce as it lands. Bounce is a one-shot keyed to
    /// `appeared`, so it never loops and doesn't retrigger on re-render.
    private func benefitRow(index: Int, icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.sbChampagne)
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sbGoldDk)
                    .symbolEffect(.bounce, options: .nonRepeating, value: appeared)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(Color.sbCharcoal)
                Text(detail)
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .entrance(appeared, delay: 0.34 + Double(index) * 0.09, reduceMotion: reduceMotion, distance: 10)
    }

    private var saveButton: some View {
        SBButton(title: buttonTitle,
                 icon: didSave ? "checkmark" : "arrow.right",
                 variant: .gold,
                 fullWidth: true) {
            save()
        }
        .disabled(isSubmitting || didSave || !canSave)
        .opacity(canSave || didSave ? 1 : 0.5)
        // The moment the address validates, the button pops. Under Reduce
        // Motion this collapses to the opacity change alone.
        .scaleEffect(canSave && !reduceMotion ? 1.0 : 0.97)
        .animation(.seatbeeSpring, value: canSave)
        .animation(.seatbee, value: didSave)
        .sensoryFeedback(.success, trigger: didSave)
    }

    private var buttonTitle: String {
        if didSave { return "Saved" }
        return isSubmitting ? "Saving…" : "Save"
    }

    // Plain text button, same treatment as SpotlightTourView's Skip.
    private var skipButton: some View {
        Button("Not now") {
            HapticEngine.selection()
            // No write needed: AppRouter stamps contact_email_prompted_at when
            // it presents this sheet, so swiping it away counts the same as
            // tapping here and we can't end up asking twice.
            dismiss()
        }
        .font(SBFont.body)
        .foregroundStyle(Color.sbWarm)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .disabled(isSubmitting || didSave)
    }

    // MARK: - Actions

    private func save() {
        guard canSave, !isSubmitting, !didSave else {
            if !canSave { errorMessage = "That doesn't look like an email address." }
            HapticEngine.error()
            return
        }
        Task {
            isSubmitting = true
            let saved = await appState.auth.saveContactEmail(email)
            isSubmitting = false
            if saved {
                // Show the "Saved" checkmark state for a beat before leaving,
                // so the user sees the write land instead of the sheet just
                // vanishing under their thumb.
                didSave = true
                try? await Task.sleep(nanoseconds: 650_000_000)
                dismiss()
            } else {
                // Write genuinely didn't land (offline, or the profiles row
                // still isn't there after 4 retries). Keep the sheet up so the
                // address isn't silently lost.
                HapticEngine.error()
                errorMessage = "Couldn't save that just now. Check your connection and try again."
            }
        }
    }
}

// MARK: - Entrance modifier

private extension View {
    /// Fade + rise (+ a touch of scale) keyed to a shared `appeared` flag with a
    /// per-element delay. This is the same shape as the dashboard hero's
    /// `ctaAppeared` treatment, lifted into a modifier so a dozen elements can
    /// share one spring. With Reduce Motion on, only the opacity animates.
    func entrance(_ appeared: Bool, delay: Double, reduceMotion: Bool, distance: CGFloat = 14) -> some View {
        self
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : distance)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.98, anchor: .top)
            .animation(.seatbeeSpring.delay(delay), value: appeared)
    }
}

#Preview {
    ContactEmailSheet()
        .environment(AppState())
}
