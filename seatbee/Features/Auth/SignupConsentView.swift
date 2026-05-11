import SwiftUI

/// Post-auth consent screen. First-time iOS signups land here before
/// the dashboard so we capture the same data web's signup form
/// collects: user_roles multi-select, email_marketing_opt_in toggle,
/// and an explicit acknowledgement of the TOS / Privacy links.
///
/// Web parity: src/App.jsx PlannerAuthModal (lines 22437–22770) +
/// src/hooks/useAuth.jsx signUp profile write (line 141). The same
/// four role options and the default-on marketing toggle.
struct SignupConsentView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedRoles: Set<String> = []
    @State private var emailMarketingOptIn = true   // matches web default
    @State private var isSubmitting = false
    @State private var enteredName = ""

    // Web parity: role IDs must match App.jsx line 22633 exactly.
    private static let roleOptions: [(id: String, label: String, icon: String)] = [
        ("bride_groom",    "Bride or Groom",               "heart.fill"),
        ("event_host",     "Event Host",                   "person.fill"),
        ("wedding_planner","Professional Wedding Planner",  "briefcase.fill"),
        ("wedding_vendor", "Wedding Vendor",               "storefront.fill"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    // Skip the name section entirely when the OAuth provider
                    // already gave us a non-empty name (Google always; Apple
                    // when the user picked "Use My Real Name"). Faster flow,
                    // no awkward "confirm your name" beat. Editable later
                    // from Settings if needed.
                    if !hasPrefilledName {
                        nameSection
                    }
                    roleSection
                    marketingSection
                    tosSection
                    Spacer(minLength: 16)
                    continueButton
                }
                .padding(.horizontal, SBSpacing.screenMargin)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
            .background(Color.sbIvory)
        }
        .onAppear {
            // Pre-fill enteredName at the view level (not just inside the
            // nameSection's onAppear) so the Continue gate has a populated
            // value even when the name section itself is hidden.
            if let name = appState.auth.displayName, !name.isEmpty {
                enteredName = name
            }
        }
    }

    /// True when we already know the user's name from the OAuth provider
    /// (or any pre-fill source). Drives whether to show the name section.
    private var hasPrefilledName: Bool {
        if let name = appState.auth.displayName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome to Seatbee")
                .font(SBFont.displayLarge)
                .foregroundStyle(Color.sbCharcoal)
            Text("A couple of quick questions so we can tailor your experience.")
                .font(SBFont.body)
                .foregroundStyle(Color.sbWarm)
        }
    }

    // Name field — only rendered when the OAuth provider didn't give us
    // a usable name (Apple "Hide My Name" or email/magic-link sign-ins).
    // Required when shown — Continue stays disabled until non-empty.
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR NAME")
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)
            TextField("First and last name", text: $enteredName)
                .font(SBFont.body)
                .padding(14)
                .background(Color.sbIvory2)
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
                .overlay(
                    RoundedRectangle(cornerRadius: SBRadius.button)
                        .strokeBorder(Color.sbLine, lineWidth: 1)
                )
                .textContentType(.name)
                .autocorrectionDisabled()
        }
    }

    /// Trimmed name — empty after trim disables Continue, so a user
    /// can't proceed by typing whitespace.
    private var trimmedName: String {
        enteredName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var roleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("I AM A…  (optional)")
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)
            ForEach(Self.roleOptions, id: \.id) { opt in
                roleChip(opt)
            }
        }
    }

    private func roleChip(_ opt: (id: String, label: String, icon: String)) -> some View {
        let active = selectedRoles.contains(opt.id)
        return Button {
            if active { selectedRoles.remove(opt.id) }
            else      { selectedRoles.insert(opt.id) }
            HapticEngine.selection()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: opt.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(active ? Color.sbGoldDk : Color.sbWarm)
                    .frame(width: 24)
                Text(opt.label)
                    .font(SBFont.bodySemibold)
                    .foregroundStyle(Color.sbCharcoal)
                Spacer()
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(active ? Color.sbGold : Color.sbWarm2)
            }
            .padding(14)
            .background(active ? Color.sbChampagne.opacity(0.5) : Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
            .overlay(
                RoundedRectangle(cornerRadius: SBRadius.button)
                    .strokeBorder(active ? Color.sbGold : Color.sbLine, lineWidth: active ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var marketingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EMAIL UPDATES")
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)
            Toggle(isOn: $emailMarketingOptIn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wedding planning tips, one email a week")
                        .font(SBFont.bodySemibold)
                        .foregroundStyle(Color.sbCharcoal)
                    Text("Unsubscribe anytime.")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                }
            }
            .tint(Color.sbGold)
            .padding(14)
            .background(Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
        }
    }

    private var tosSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("By tapping Continue you agree to Seatbee's")
                .font(SBFont.caption)
                .foregroundStyle(Color.sbWarm)
            HStack(spacing: 4) {
                Link("Terms of Service",   destination: URL(string: "https://www.seatbee.app/terms")!)
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbGoldDk)
                Text("and")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
                Link("Privacy Policy",     destination: URL(string: "https://www.seatbee.app/privacy")!)
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbGoldDk)
                Text(".")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
            }
        }
    }

    private var continueButton: some View {
        SBButton(title: isSubmitting ? "Saving…" : "Continue",
                 icon: "arrow.right",
                 variant: .gold,
                 fullWidth: true) {
            Task {
                isSubmitting = true
                await appState.auth.completeSignupConsent(
                    userRoles: Array(selectedRoles),
                    emailMarketingOptIn: emailMarketingOptIn,
                    displayName: trimmedName
                )
                // needsSignupConsent flips to false inside the call,
                // RootView swaps to AppRouter automatically.
                isSubmitting = false
            }
        }
        .disabled(isSubmitting || trimmedName.isEmpty)
    }
}

#Preview {
    SignupConsentView()
        .environment(AppState())
}
