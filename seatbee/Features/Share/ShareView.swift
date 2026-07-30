import SwiftUI
import CoreImage.CIFilterBuiltins

struct ShareView: View {
    @Environment(AppState.self) private var appState

    // Collaborators (web parity — /api/collab)
    @State private var collabIsOwner = false
    @State private var collabOwner: CollabPerson?
    @State private var collaborators: [CollabPerson] = []
    @State private var invitations: [PendingInvitation] = []
    @State private var collabLoading = false
    @State private var collabError: String?
    @State private var showInvitePrompt = false
    @State private var inviteEmail = ""
    @State private var inviteSending = false
    @State private var inviteResult: String?

    // Guest QR section state
    @State private var qrExpanded = false
    @State private var qrEnabled = false
    @State private var qrToken: String?
    @State private var qrSyncing = false
    @State private var qrError: String?

    // PDF export options (mirrors web's PDF Options panel — meals,
    // dietary, high chairs). Toggles are persisted only for the current
    // session; web doesn't persist these either.
    @State private var pdfOpts: PDFExportOpts = .default
    @State private var showCanvaSheet = false

    // Floor Plan share toggle — when on, names are drawn at each
    // filled seat in the Floor Plan share image. Defaults to ON
    // because a "seating plan" without names is just a room diagram.
    @State private var includeGuestNamesOnFloorPlan = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SBNavHeader(title: "Share plan")

                if appState.activePlan == nil {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.sbWarm2)
                        Text("No plan to share")
                            .font(SBFont.displaySmall)
                            .foregroundStyle(Color.sbCharcoal)
                        Text("Select a plan first")
                            .font(SBFont.body)
                            .foregroundStyle(Color.sbWarm)
                        SBButton(title: "Go to Plans", icon: "square.grid.2x2", variant: .gold) {
                            appState.selectedTab = .plans
                        }
                    }
                    Spacer()
                } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: SBSpacing.sectionGap) {
                        // Sample-event banner — explains why share-link /
                        // collaborators are gated. Mirrors the Guests-tab
                        // banner so the demo state is consistent across tabs.
                        if appState.activePlan?.isDemo == true {
                            sampleEventShareBanner
                        }

                        // Plan preview + collaborator banner (when non-owner)
                        if let plan = appState.activePlan {
                            planPreview(plan)
                            if !collabIsOwner, let owner = collabOwner {
                                collabBanner(owner: owner)
                            }
                        }

                        // Collaborators (web parity — /api/collab) — hidden
                        // entirely on the demo plan. Inviting a collaborator
                        // would require a real Supabase row, and there's no
                        // value in showing an empty card on a sample.
                        if let plan = appState.activePlan, !plan.isDemo {
                            collaboratorsCard(plan: plan)
                        }

                        SBOrnament(label: "Share via")

                        // Two big shareable image cards (Wrapped + Floor Plan).
                        // PDFs / Canva live in Print & Design below — different
                        // intent, different surface.
                        shareViaRow

                        // Guest QR (expandable, web parity)
                        if let plan = appState.activePlan {
                            guestQRSection(plan: plan)
                        }

                        // Export — Print & Design + Spreadsheet sections
                        printDesignSection
                        spreadsheetSection

                        // Seatbee Tools (web parity)
                        seatbeeToolsSection

                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, SBSpacing.screenMargin)
                    .padding(.top, SBSpacing.screenMargin)
                }
                } // end else
            }
            .background(Color.sbIvory)
            .task {
                if appState.activePlan == nil {
                    let plans = (try? await appState.database.fetchPlans()) ?? []
                    if let first = plans.first { appState.activePlan = first }
                }
            }
            .sheet(isPresented: $showCanvaSheet) {
                if let plan = appState.activePlan {
                    CanvaExportSheet(plan: plan)
                }
            }
        }
    }

    // MARK: - Plan Preview

    private func planPreview(_ plan: SeatingPlan) -> some View {
        HStack(spacing: 10) {
            SBAvatar(name: plan.name, size: 28)
            Text(plan.name)
                .font(SBFont.bodySmallBold)
                .foregroundStyle(Color.sbCharcoal)
            Spacer()
        }
        .padding(12)
        .background(Color.sbIvory2)
        .clipShape(RoundedRectangle(cornerRadius: SBRadius.chip))
    }

    // MARK: - Sample event banner

    private var sampleEventShareBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.sbGoldDk)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sample event")
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(Color.sbCharcoal)
                Text("Sharing, QR codes, and collaborators unlock when you sign up.")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.sbChampagne2)
        .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
    }

    // MARK: - Collaborator banner (when not the owner)

    private func collabBanner(owner: CollabPerson) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.sbGoldDk)
            VStack(alignment: .leading, spacing: 2) {
                Text("Shared by \(owner.name)")
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(Color.sbCharcoal)
                Text("You can edit guests, tables, and rules. Only the owner can rename or delete the plan.")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.sbChampagne.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: SBRadius.chip))
    }

    // MARK: - Collaborators (web parity — /api/collab)

    private func collaboratorsCard(plan: SeatingPlan) -> some View {
        SBCard(backgroundColor: .sbIvory2) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Collaborators")
                        .font(SBFont.bodySemibold)
                        .foregroundStyle(Color.sbCharcoal)
                    Spacer()
                    if collabLoading {
                        ProgressView().scaleEffect(0.7)
                    }
                }

                if let owner = collabOwner {
                    collaboratorRow(person: owner, isOwnerEntry: true, planId: plan.id)
                }
                ForEach(collaborators, id: \.userId) { c in
                    Divider().background(Color.sbLine)
                    collaboratorRow(person: c, isOwnerEntry: false, planId: plan.id)
                }
                ForEach(invitations, id: \.id) { inv in
                    Divider().background(Color.sbLine)
                    invitationRow(invitation: inv, planId: plan.id)
                }

                if collabIsOwner {
                    // Collaborator invites are a paid-tier feature on web
                    // (AccountSettings ~25149) and the dashboard tier
                    // badge already lists them as such. On free / expired
                    // plans we route the tap straight to the paywall —
                    // matches the "skip gate alerts, go straight to
                    // paywall" pattern Shayan wired for the other gates.
                    let isPaid = appState.activePlanTier != .free && !appState.isActivePlanExpired
                    Button {
                        if isPaid {
                            inviteEmail = ""
                            inviteResult = nil
                            showInvitePrompt = true
                        } else {
                            appState.upgradeTrigger = "share"
                            appState.showUpgrade = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isPaid ? "plus.circle.fill" : "lock.fill")
                            Text("Invite by email")
                            if !isPaid {
                                Text("· Upgrade")
                                    .font(SBFont.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.sbChampagne)
                                    .clipShape(Capsule())
                            }
                        }
                        .font(SBFont.bodySemibold)
                        .foregroundStyle(Color.sbGoldDk)
                    }
                    .buttonStyle(.plain)

                    // Fine print explaining what a collaborator can and
                    // can't do. Mirrors web's permission model: collabs
                    // get full edit access on guests / tables / rules /
                    // objects, but rename / delete / invitations stay
                    // owner-only.
                    Text("Collaborators can add guests, move tables, edit rules — full edit access. Only you can rename the event, manage collaborators, or delete the plan.")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                        .padding(.top, 4)
                }

                if let err = collabError {
                    Text(err)
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbError)
                }

                if collabOwner == nil && collaborators.isEmpty && invitations.isEmpty && !collabLoading {
                    Text("Loading collaborators…")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                }
            }
        }
        .onAppear { Task { await loadCollaborators(planId: plan.id) } }
        .onChange(of: appState.activePlan?.id) { _, newId in
            if let id = newId { Task { await loadCollaborators(planId: id) } }
        }
        .alert("Invite a collaborator", isPresented: $showInvitePrompt) {
            TextField("name@example.com", text: $inviteEmail)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Send invite") {
                Task { await sendInvite(planId: plan.id, email: inviteEmail) }
            }
        } message: {
            Text("They'll get an email link to join. Collaborators can edit guests, tables, and rules — but only you can rename or delete the plan.")
        }
        .alert("Invitation", isPresented: Binding(
            get: { inviteResult != nil },
            set: { if !$0 { inviteResult = nil } }
        )) {
            Button("OK", role: .cancel) { inviteResult = nil }
        } message: {
            Text(inviteResult ?? "")
        }
    }

    private func collaboratorRow(person: CollabPerson, isOwnerEntry: Bool, planId: String) -> some View {
        HStack(spacing: 10) {
            SBAvatar(name: person.name, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(person.name)
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(Color.sbCharcoal)
                if !person.email.isEmpty {
                    Text(person.email)
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isOwnerEntry {
                Text("OWNER")
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbGoldDk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.sbChampagne)
                    .clipShape(Capsule())
            } else if collabIsOwner {
                Button {
                    Task { await removeCollaborator(planId: planId, userId: person.userId) }
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.sbWarm2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func invitationRow(invitation: PendingInvitation, planId: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.sbIvory).frame(width: 32, height: 32)
                Image(systemName: "envelope")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sbWarm)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(invitation.email)
                    .font(SBFont.bodySmall)
                    .foregroundStyle(Color.sbCharcoal)
                    .lineLimit(1)
                Text("Pending")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
            }
            Spacer()
            Button {
                Task { await revokeInvitation(invitationId: invitation.id) }
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.sbWarm2)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Share via row
    //
    // Replaced the old 5-channel mock buttons (iMessage / WhatsApp /
    // IG / Email / More) with two real shareable artefacts. The old
    // row was misleading — every channel button opened the same
    // generic iOS activity sheet AND the URL it shared
    // (seatbee.app/plan/<id>) didn't resolve to anything on web. The
    // new row is content-first: pick what to share, iOS handles the
    // channel selection itself in the activity sheet. Visual
    // separation from the Print & Design row below: this row is
    // images for socials, that row is PDFs / Canva for printing.

    private var shareViaRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                snapshotShareCard
                seatingChartShareCard
            }

            // Inline toggle row for the Floor Plan variant. Drawn as a
            // tappable check pill rather than a SwiftUI Toggle so it
            // sits flush with the share-card row's typography.
            Button {
                includeGuestNamesOnFloorPlan.toggle()
                HapticEngine.selection()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: includeGuestNamesOnFloorPlan ? "checkmark.square.fill" : "square")
                        .font(.system(size: 16))
                        .foregroundStyle(includeGuestNamesOnFloorPlan ? Color.sbGoldDk : Color.sbWarm2)
                    Text("Include guest names on Floor Plan")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbCharcoal)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.sbIvory2)
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Share Via cards
    //
    // Each card has a stylised mini-preview hinting at the actual
    // exported image (not a literal render — too expensive — but
    // shapes + the brand palette so the card itself feels like a
    // tease of what'll get shared). Outcome-first copy: tells the
    // user what they're sending, not what file format it is. Two
    // distinct colour identities so the row doesn't read as two
    // copies of the same generic tile.

    /// Warm gold "wrapped"-style preview hinting at stats + sparkles.
    /// Headline is the LIVE seated-guest count for the active plan,
    /// so the card reflects actual progress on the current plan
    /// rather than a static mock or just the total RSVP'd count.
    /// Falls back to "100" when no plan is loaded so the card still
    /// looks like a populated preview.
    private var snapshotShareCard: some View {
        let seatedCount = appState.activePlan?.tables.reduce(0) { $0 + $1.assignments.count } ?? 0
        return Button {
            handleShareSocial()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 234/255, green: 220/255, blue: 188/255),  // champagne
                            Color(red: 213/255, green: 184/255, blue: 116/255),  // gold
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Inner mock card — gives the feel of a Wrapped
                    // preview without rendering the full image.
                    VStack(spacing: 2) {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 8, weight: .semibold))
                            Text("SEATBEE")
                                .font(.system(size: 7, weight: .bold))
                                .kerning(1)
                        }
                        .foregroundStyle(Color(white: 1).opacity(0.85))

                        Text(seatedCount > 0 ? "\(seatedCount)" : "100")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)
                        Text("SEATED")
                            .font(.system(size: 7, weight: .bold))
                            .kerning(1.5)
                            .foregroundStyle(Color(white: 1).opacity(0.85))
                    }
                }
                .frame(height: 88)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Seating Snapshot")
                        .font(SBFont.bodySmallBold)
                        .foregroundStyle(Color.sbCharcoal)
                    Text("Show off your plan — guests, tables, top categories.")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    /// Sage-tinted preview with stylised seat dots arranged around a
    /// table — hints at the actual floor-plan output without trying
    /// to render the full image. Title and subtitle flip with the
    /// "include names" toggle.
    private var seatingChartShareCard: some View {
        let withNames = includeGuestNamesOnFloorPlan
        return Button {
            handleShareFloorPlan()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 245/255, green: 240/255, blue: 224/255),  // soft ivory
                            Color(red: 213/255, green: 222/255, blue: 198/255),  // soft sage
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    seatingDotIllustration
                }
                .frame(height: 88)

                VStack(alignment: .leading, spacing: 2) {
                    Text(withNames ? "Seating Chart" : "Floor Plan")
                        .font(SBFont.bodySmallBold)
                        .foregroundStyle(Color.sbCharcoal)
                    Text(withNames
                         ? "See who sits where — perfect for the group chat."
                         : "Just the room layout, tables only.")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    /// 6 gold seat dots arranged around a small table circle. Pure
    /// SwiftUI shapes — no asset needed. Mirrors the look of the
    /// real floor-plan render so the card teases the actual output.
    private var seatingDotIllustration: some View {
        let goldDk = Color(red: 161/255, green: 132/255, blue: 65/255)
        let gold = Color(red: 201/255, green: 169/255, blue: 97/255)
        return ZStack {
            // Centre table
            Circle()
                .fill(Color.white.opacity(0.7))
                .overlay(Circle().strokeBorder(goldDk, lineWidth: 1))
                .frame(width: 32, height: 32)
            // 6 seats around it
            ForEach(0..<6, id: \.self) { i in
                let angle = Double(i) / 6 * 2 * .pi - .pi / 2
                Circle()
                    .fill(gold)
                    .frame(width: 8, height: 8)
                    .offset(x: 28 * cos(angle), y: 28 * sin(angle))
            }
        }
    }

    private func handleShareSocial() {
        guard let plan = appState.activePlan else { return }
        PDFExportService.shareSocialImage(plan: plan)
    }

    private func handleShareFloorPlan() {
        guard let plan = appState.activePlan else { return }
        PDFExportService.shareFloorPlanImage(plan: plan,
                                              showGuestNames: includeGuestNamesOnFloorPlan)
    }

    // MARK: - Export — PRINT & DESIGN
    //
    // Web parity (App.jsx ExpPanel ~13800). iOS surfaces the same three
    // PDF toggles (meals / dietary / high chairs), the same two PDFs
    // (Seating Chart + Planner View), and the Canva handoff. Place cards
    // and Social image are iOS-only fallbacks that web doesn't carry.
    //
    // Free-tier PDFs render with a diagonal SEATBEE.APP watermark; paid
    // tier renders cleanly. Canva is fully paid-gated (mirrors web).

    private var printDesignSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRINT & DESIGN")
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)

            pdfOptionsCard

            toolCard(
                icon: "doc.text",
                title: "Seating Chart (PDF)",
                subtitle: "Printable chart with all tables",
                action: { handleSeatingChartPDF() }
            )
            toolCard(
                icon: "rectangle.split.3x1",
                title: "Planner View (PDF)",
                subtitle: "Table diagrams with seat-by-seat details",
                action: { handlePlannerViewPDF() }
            )
            canvaCard
            // Web hand-off — see PARITY.md "Print pipeline" entry. The
            // styled place card / poster seating chart editor on web is
            // a deep, designer-driven flow (templates, fonts, colours,
            // bleed, etc.). We deliberately don't reimplement it on
            // iOS; tapping this card opens the web editor where the
            // user can sign in and use the full print toolkit.
            toolCard(
                icon: "square.grid.2x2",
                title: "Printable Cards & Charts",
                subtitle: "Styled place cards · Poster seating charts (opens on web)",
                action: { openPrintCardsOnWeb() }
            )
            // Social Image moved up to the Share Via row above —
            // image-shareables and printable artefacts live in
            // separate sections now (different user intent).
        }
    }

    private var spreadsheetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SPREADSHEET / DATA")
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)

            gatedToolCard(
                icon: "person.2",
                title: "Guest List (CSV)",
                subtitle: "Full guest data — Excel, Google Sheets, vendors",
                isPaidGate: true,
                action: { handleGuestCSV() }
            )
            gatedToolCard(
                icon: "square.grid.3x2",
                title: "Table Summary (CSV)",
                subtitle: "Per-table assignments + meal counts",
                isPaidGate: true,
                action: { handleTablesCSV() }
            )
        }
    }

    /// Three-toggle card matching web's "PDF Options" panel. State lives
    /// in `pdfOpts` and is threaded into the Seating Chart + Planner View
    /// PDF generators.
    private var pdfOptionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PDF OPTIONS")
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm2)
                .letterSpacing(1.5)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
            optionToggleRow(
                title: "Include meal selections",
                isOn: Binding(get: { pdfOpts.includeMeals },
                              set: { pdfOpts.includeMeals = $0 })
            )
            Divider().background(Color.sbLine).padding(.leading, 12)
            optionToggleRow(
                title: "Include dietary restrictions",
                isOn: Binding(get: { pdfOpts.includeDietary },
                              set: { pdfOpts.includeDietary = $0 })
            )
            Divider().background(Color.sbLine).padding(.leading, 12)
            optionToggleRow(
                title: "Flag high chairs",
                isOn: Binding(get: { pdfOpts.includeHighChairs },
                              set: { pdfOpts.includeHighChairs = $0 })
            )
        }
        .background(Color.sbIvory2)
        .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: SBRadius.card)
                .strokeBorder(Color.sbLine, lineWidth: 1)
        )
    }

    private func optionToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(SBFont.bodySmall)
                .foregroundStyle(Color.sbCharcoal)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.sbGold)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Canva card — paid-gated, opens the modal on tap when paid,
    /// routes to upgrade otherwise. Visually identical to other tool
    /// cards but with a lock badge + "Upgrade" pill on free tier.
    private var canvaCard: some View {
        let isPaid = appState.activePlanTier != .free && !appState.isActivePlanExpired
        return Button {
            if isPaid {
                showCanvaSheet = true
            } else {
                appState.upgradeTrigger = "export"
                appState.showUpgrade = true
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    // Canva logo on a tinted square. The SVG has a 1900×1900
                    // viewBox (circle in square), so square frame = no
                    // distortion. A small lock chip overlays when locked.
                    Image("CanvaLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                    if !isPaid {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.sbGoldDk)
                            .padding(3)
                            .background(Color.sbChampagne)
                            .clipShape(Circle())
                            .offset(x: 13, y: 13)
                    }
                }
                .frame(width: 40, height: 40)
                .background(Color(red: 0/255, green: 196/255, blue: 204/255).opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Export to Canva")
                            .font(SBFont.bodySmallBold)
                            .foregroundStyle(Color.sbCharcoal)
                        if !isPaid {
                            Text("UPGRADE")
                                .font(SBFont.capsLabel)
                                .foregroundStyle(Color.sbGoldDk)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.sbChampagne)
                                .clipShape(Capsule())
                        }
                    }
                    Text("Bulk-create place cards & table seating cards")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sbWarm2)
            }
            .padding(12)
            .background(Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: SBRadius.card)
                    .strokeBorder(Color.sbLine, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Variant of `toolCard` that shows a lock badge + Upgrade pill when
    /// `isPaidGate` is true and the active plan is on the free tier.
    private func gatedToolCard(icon: String, title: String, subtitle: String,
                               isPaidGate: Bool, action: @escaping () -> Void) -> some View {
        let locked = isPaidGate && (appState.activePlanTier == .free || appState.isActivePlanExpired)
        return Button {
            if locked { appState.upgradeTrigger = "export"; appState.showUpgrade = true } else { action() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: locked ? "lock.fill" : icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.sbGoldDk)
                    .frame(width: 40, height: 40)
                    .background(Color.sbChampagne.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(SBFont.bodySmallBold)
                            .foregroundStyle(Color.sbCharcoal)
                        if locked {
                            Text("UPGRADE")
                                .font(SBFont.capsLabel)
                                .foregroundStyle(Color.sbGoldDk)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.sbChampagne)
                                .clipShape(Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sbWarm2)
            }
            .padding(12)
            .background(Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: SBRadius.card)
                    .strokeBorder(Color.sbLine, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Export action handlers

    private var isPaidPlan: Bool {
        appState.activePlanTier != .free && !appState.isActivePlanExpired
    }

    private func handleSeatingChartPDF() {
        guard let plan = appState.activePlan else { return }
        PDFExportService.shareSeatingChartPDF(plan: plan, opts: pdfOpts, isPaid: isPaidPlan)
    }

    private func handlePlannerViewPDF() {
        guard let plan = appState.activePlan else { return }
        PDFExportService.sharePlannerViewPDF(plan: plan, opts: pdfOpts, isPaid: isPaidPlan)
    }

    /// Opens the web Print & Design surface where the user can pick
    /// styled place card / seating chart templates. Per PARITY.md the
    /// web printable editor stays canonical; iOS doesn't try to mirror
    /// it.
    ///
    /// Deep-link contract (handled by AppContent on web):
    ///   `?planId=<id>&openExport=printCards`
    /// On mount, web stashes both params in localStorage as
    /// `seatbee_deep_link`. If the user is already signed in, it
    /// loadPlan(id)s and pops the print modal immediately. If not, it
    /// shows the sign-in prompt; the payload survives the OAuth
    /// redirect and is consumed when `user` becomes truthy. Stale
    /// entries auto-expire after 30 min.
    private func openPrintCardsOnWeb() {
        guard let plan = appState.activePlan else {
            if let url = URL(string: "https://seatbee.app/app") {
                UIApplication.shared.open(url)
            }
            return
        }
        // Percent-encode the plan ID defensively even though they're
        // UUIDs — keeps us safe if the ID format ever changes.
        let safeId = plan.id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? plan.id
        let urlString = "https://seatbee.app/app?planId=\(safeId)&openExport=printCards"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }


    private func handleGuestCSV() {
        guard let plan = appState.activePlan else { return }
        PDFExportService.shareGuestListCSV(plan: plan)
    }

    private func handleTablesCSV() {
        guard let plan = appState.activePlan else { return }
        PDFExportService.shareTablesCSV(plan: plan)
    }

    // MARK: - Seatbee Tools (web parity)
    //
    // Two web tools that pre-fill from the active plan: Alphabetical
    // Seating Display (A–Z escort cards) and Dietary Summary
    // Generator (caterer brief). Web's Export panel hands off via
    // localStorage; iOS hands off via URL hash since Safari can't
    // share localStorage with the iOS process. Web tools accept
    // either source — see web commit 130f4db.

    private var seatbeeToolsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SEATBEE TOOLS")
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)
            toolCard(
                icon: "list.bullet.indent",
                title: "Alphabetical Seating Display",
                subtitle: "A–Z escort card display, pre-filled from your plan",
                action: openAlphabeticalSeatingTool
            )
            toolCard(
                icon: "clipboard",
                title: "Dietary Summary Generator",
                subtitle: "Pre-filled caterer brief from your guest dietary data",
                action: openDietarySummaryTool
            )
        }
    }

    private func toolCard(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.sbGoldDk)
                    .frame(width: 40, height: 40)
                    .background(Color.sbChampagne.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SBFont.bodySmallBold)
                        .foregroundStyle(Color.sbCharcoal)
                    Text(subtitle)
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sbWarm2)
            }
            .padding(12)
            .background(Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: SBRadius.card)
                    .strokeBorder(Color.sbLine, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func openAlphabeticalSeatingTool() {
        guard let plan = appState.activePlan else { return }
        // Web parity (App.jsx ~14751): build a `Guest Name, Table` CSV
        // from sorted seated guests, payload as { csv, event }. Use the
        // displayName (falls back to firstName+lastName, then name) so
        // guests whose `name` field is empty but `display`/`firstName`
        // is populated still surface in the alphabetical display.
        var rows: [[String]] = [["Guest Name", "Table"]]
        var seated: [(name: String, table: String)] = []
        for table in plan.tables {
            for gid in table.assignments.keys {
                guard let g = plan.guests.first(where: { $0.id == gid }) else { continue }
                let displayed = g.displayName  // tries display → first+last → name
                let name = displayed.isEmpty ? g.name : displayed
                guard !name.isEmpty else { continue }
                seated.append((name, table.name))
            }
        }
        seated.sort { $0.name.lowercased() < $1.name.lowercased() }
        for s in seated { rows.append([s.name, s.table]) }
        let csv = rows.map { r in r.map { c in
            "\"" + c.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }.joined(separator: ",") }.joined(separator: "\n")
        let payload: [String: Any] = ["csv": csv, "event": plan.name]
        openToolURL(path: "/tools/alphabetical-seating", payload: payload)
    }

    private func openDietarySummaryTool() {
        guard let plan = appState.activePlan else { return }
        // Web parity (App.jsx ~14820): build meals[] + crossRef from
        // seated guests' meal + dietaryTags. Payload mirrors web's
        // localStorage shape so the page can hydrate identically.
        let assignedIds = Set(plan.tables.flatMap { $0.assignments.keys })

        // Meals: tally seated guests by meal short.
        var mealCounts: [String: Int] = [:]
        for g in plan.guests where assignedIds.contains(g.id) {
            if let m = g.meal, !m.isEmpty {
                mealCounts[m, default: 0] += 1
            }
        }
        let meals: [[String: Any]] = mealCounts
            .sorted { $0.key < $1.key }
            .map { ["name": $0.key, "count": $0.value] }

        // crossRef: dietary key → { mealId: count }. Standard guests
        // (no dietary tags) go under `std`; tagged guests under their
        // tag's diet key. Mirrors web's tagToDietKey logic.
        let dietKeyByTag: [String: String] = [
            "vegetarian": "veg", "vegan": "vgn", "gluten-free": "gf",
            "dairy-free": "df", "nut-allergy": "nut",
            "shellfish-allergy": "sh", "halal": "hal", "kosher": "kos"
        ]
        var crossRef: [String: [String: Int]] = [:]
        // Custom-note breakdown — guests with a non-empty Guest.dietary
        // (free-text "other restriction" field). Surfaces as a list the
        // tool can render under an "Other notes" section so caterers
        // see things like "no pork" / "low sodium" that don't map to
        // the canonical 8 tags.
        var customNotes: [[String: Any]] = []
        for g in plan.guests where assignedIds.contains(g.id) {
            guard let m = g.meal, !m.isEmpty else { continue }
            let mealId = m
            let tags = g.dietaryTags ?? []
            let dietKeys = tags.compactMap { dietKeyByTag[$0] }
            let bucket = dietKeys.isEmpty ? ["std"] : dietKeys
            for k in bucket {
                crossRef[k, default: [:]][mealId, default: 0] += 1
            }
            if let note = g.dietary?.trimmingCharacters(in: .whitespaces),
               !note.isEmpty {
                customNotes.append([
                    "guest": g.displayName,
                    "meal": mealId,
                    "note": note,
                ])
            }
        }

        let payload: [String: Any] = [
            "eventName": plan.name,
            "eventDate": plan.eventDate.map { ISO8601DateFormatter().string(from: $0) } ?? "",
            "venueName": plan.venue ?? "",
            "meals": meals,
            "crossRef": crossRef,
            "customNotes": customNotes,
        ]
        openToolURL(path: "/tools/dietary-summary", payload: payload)
    }

    /// Encodes the payload as JSON → base64 → URL-encoded, appends as
    /// `#import=…` so the web tool can decode it on mount. Hash
    /// fragments aren't sent to the server so payload stays client-only.
    ///
    /// Uses `.alphanumerics` for percent-encoding so the base64 special
    /// chars `+`, `/`, `=` all become `%2B`, `%2F`, `%3D` instead of
    /// being passed literal — `+` in particular gets transformed to
    /// space by some URL parsers, which silently corrupts the payload.
    private func openToolURL(path: String, payload: [String: Any]) {
        guard let json = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return }
        let b64 = json.base64EncodedString()
        guard let encoded = b64.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return }
        guard let url = URL(string: "https://www.seatbee.app\(path)#import=\(encoded)") else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Guest QR section
    //
    // Web parity (src/App.jsx GuestQRPanel ~48046). iOS provides a slim
    // version: enable / disable, view + share / save the QR. Visual style
    // (custom colors, logo overlay) is intentionally left to web.

    private func guestQRSection(plan: SeatingPlan) -> some View {
        SBCard(backgroundColor: .sbIvory2) {
            VStack(alignment: .leading, spacing: 12) {
                // Header — always visible. Toggle is the primary control.
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.seatbee) { qrExpanded.toggle() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: qrExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.sbWarm)
                            Text("Guest QR Code")
                                .font(SBFont.bodySemibold)
                                .foregroundStyle(Color.sbCharcoal)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if qrSyncing {
                        ProgressView().scaleEffect(0.8)
                    }
                    Toggle("", isOn: Binding(
                        get: { qrEnabled },
                        set: { newValue in
                            qrEnabled = newValue
                            // Auto-expand the section when turning on so the
                            // user immediately sees their QR — they enabled
                            // it because they want to use it. Don't auto-
                            // collapse on toggle-off; user might want to
                            // re-share the link before re-enabling.
                            if newValue {
                                withAnimation(.seatbee) { qrExpanded = true }
                            }
                            Task { await saveQRConfig(planId: plan.id, enabled: newValue) }
                        }
                    ))
                    .labelsHidden()
                    .tint(.sbGold)
                    .disabled(qrSyncing)
                }

                if qrExpanded {
                    if qrEnabled, let token = qrToken {
                        let url = "https://seatbee.app/g/\(token)"
                        HStack(alignment: .top, spacing: 14) {
                            if let qrImage = UIImage.qrCode(from: url, size: 110) {
                                Image(uiImage: qrImage)
                                    .resizable()
                                    .interpolation(.none) // crisp pixels
                                    .frame(width: 110, height: 110)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(Color.sbLine, lineWidth: 1)
                                    )
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Text(url)
                                    .font(SBFont.caption)
                                    .foregroundStyle(Color.sbWarm)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                HStack(spacing: 8) {
                                    qrActionButton(icon: "square.and.arrow.up", label: "Share") {
                                        shareQR(url: url)
                                    }
                                    qrActionButton(icon: "square.and.arrow.down", label: "Save") {
                                        saveQRToPhotos(url: url)
                                    }
                                }
                            }
                        }
                        // Tell users what guests actually get when they
                        // scan, so the "design" link reads as polish, not
                        // a missing feature. Mirrors web's GuestQRPanel
                        // copy.
                        VStack(alignment: .leading, spacing: 6) {
                            Text("WHAT GUESTS SEE")
                                .font(SBFont.capsLabel)
                                .foregroundStyle(Color.sbWarm)
                                .letterSpacing(1.5)
                            Text("Their table assignment, your welcome message, dietary icons, meal selection, and any icebreakers you've written for the event.")
                                .font(SBFont.caption)
                                .foregroundStyle(Color.sbCharcoal2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 4)

                        Button {
                            openWebPlan(planId: plan.id)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "paintbrush")
                                Text("Customize colors, logo, welcome message, and icebreakers on web")
                                Image(systemName: "arrow.up.right.square")
                            }
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbGoldDk)
                            .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                    } else if qrEnabled && qrToken == nil {
                        Text("Enabling…")
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbWarm)
                    } else {
                        Text("Turn on to generate a QR code that guests can scan to see their table assignment.")
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbWarm)
                    }

                    if let err = qrError {
                        Text(err)
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbError)
                    }
                }
            }
        }
        .onAppear {
            syncQRStateFromPlan(plan)
            Task { await fetchQRConfig(planId: plan.id) }
        }
        .onChange(of: appState.activePlan?.id) { _, _ in
            if let p = appState.activePlan {
                syncQRStateFromPlan(p)
                Task { await fetchQRConfig(planId: p.id) }
            }
        }
    }

    private func qrActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(SBFont.inter(11, weight: .semibold))
            }
            .foregroundStyle(Color.sbGoldDk)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.sbChampagne)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - QR state + API

    /// Read current values out of the active plan's `rawGuestQR` blob into
    /// local @State so the toggle reflects the plan's actual state when the
    /// user lands on the Share tab. No network call here.
    private func syncQRStateFromPlan(_ plan: SeatingPlan) {
        qrEnabled = plan.guestQREnabled
        qrToken = plan.guestQRToken
    }

    /// GET current config from the server on first appearance. The token +
    /// enabled flag live on top-level `seating_plans` columns
    /// (`guest_link_token`, `guest_experience`) — NOT inside the JSONB
    /// `data` blob — so iOS has to ask the server rather than reading it
    /// off the local plan.
    private func fetchQRConfig(planId: String) async {
        // Demo plan never hits the server. Show a friendly message instead.
        if planId == SampleEventService.samplePlanId {
            qrError = "Sign up to share with your guests."
            qrEnabled = false
            qrToken = nil
            return
        }
        qrError = nil
        guard let url = URL(string: "\(AppConfig.guestAPIBaseURL)?action=config&planId=\(planId)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = await AuthService().accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return  // silent — section just stays in default state
            }
            qrToken = json["token"] as? String
            let config = (json["config"] as? [String: Any]) ?? [:]
            qrEnabled = (config["enabled"] as? Bool) ?? false
        } catch {
            // silent on read; the toggle still works for write
        }
    }

    /// POST to `/api/guest`. Server stores config in the `guest_experience`
    /// column and returns the (possibly newly-minted) token. iOS keeps the
    /// returned token in local @State; no JSONB writeback needed.
    private func saveQRConfig(planId: String, enabled: Bool) async {
        // Demo plan: never mint a token — that would create a real Supabase
        // row tied to a fake plan ID. Surface the conversion-pitch message.
        if planId == SampleEventService.samplePlanId {
            qrError = "Sign up to share your seating plan with guests."
            qrEnabled = false
            return
        }

        qrError = nil
        qrSyncing = true
        defer { qrSyncing = false }

        guard let url = URL(string: "\(AppConfig.guestAPIBaseURL)") else {
            qrError = "Couldn't reach the QR service."
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = await AuthService().accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            qrError = "Sign-in required. Try the Plans tab to refresh."
            return
        }

        let body: [String: Any] = [
            "action": "save-config",
            "planId": planId,
            "config": ["enabled": enabled],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                qrError = "Unexpected response."
                return
            }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if http.statusCode != 200 {
                let serverError = (json?["error"] as? String) ?? "status \(http.statusCode)"
                qrError = "QR save failed: \(serverError)"
                return
            }
            qrToken = (json?["token"] as? String) ?? qrToken
        } catch {
            qrError = "Network error: \(error.localizedDescription)"
        }
    }

    private func shareQR(url: String) {
        guard let img = UIImage.qrCode(from: url, size: 600),
              let png = img.pngData() else { return }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("Seatbee Guest QR.png")
        try? png.write(to: tmp)
        let activityVC = UIActivityViewController(
            activityItems: [tmp, URL(string: url)!],
            applicationActivities: nil
        )
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            // iPad requires a non-nil popover source — omitting it crashes immediately.
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = root.view
                popover.sourceRect = CGRect(x: root.view.bounds.midX,
                                            y: root.view.bounds.midY,
                                            width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            root.present(activityVC, animated: true)
        }
    }

    private func saveQRToPhotos(url: String) {
        guard let img = UIImage.qrCode(from: url, size: 600) else { return }
        // No Info.plist photo permission is required for UIImageWriteToSavedPhotosAlbum
        // when the user has granted Photos access via the activity sheet flow,
        // but iOS still expects NSPhotoLibraryAddUsageDescription. If missing,
        // the call no-ops silently — surface a hint via haptic + share fallback.
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        HapticEngine.success()
    }

    private func openWebPlan(planId: String) {
        if let url = URL(string: "https://seatbee.app/plan/\(planId)") {
            UIApplication.shared.open(url)
        }
    }


    // MARK: - Collaborator API
    //
    // Web parity (api/collab.js). All four actions hit the www subdomain
    // directly to avoid the seatbee.app → www.seatbee.app 307 redirect
    // that strips Authorization headers in URLSession.

    private func loadCollaborators(planId: String) async {
        // Demo plan: never call /api/collab — it returns "Plan not found"
        // because the demo plan ID isn't in the database. Set a clean
        // empty state and a friendly message instead.
        if planId == SampleEventService.samplePlanId {
            collabOwner = nil
            collaborators = []
            invitations = []
            collabIsOwner = false
            collabError = nil
            collabLoading = false
            return
        }

        collabError = nil
        collabLoading = true
        defer { collabLoading = false }

        guard let url = URL(string: "\(AppConfig.collabAPIBaseURL)?action=list&planId=\(planId)") else {
            collabError = "Couldn't build collab URL."
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        guard let token = await AuthService().accessToken else {
            collabError = "Sign in again to load collaborators."
            return
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if http.statusCode != 200 {
                collabError = (json?["error"] as? String) ?? "Couldn't load collaborators."
                return
            }
            collabIsOwner = (json?["isOwner"] as? Bool) ?? false

            if let ownerDict = json?["owner"] as? [String: Any] {
                collabOwner = CollabPerson(dict: ownerDict)
            }
            if let arr = json?["collaborators"] as? [[String: Any]] {
                collaborators = arr.compactMap { CollabPerson(dict: $0) }
            }
            if let arr = json?["invitations"] as? [[String: Any]] {
                // Filter out invitations that have already been accepted —
                // web's API returns the full history (`SELECT *`), but the
                // accepted user already appears in `collaborators` and
                // showing the invite row again confuses users (it looks
                // like Shayan is both a collaborator AND pending).
                invitations = arr
                    .compactMap { PendingInvitation(dict: $0) }
                    .filter { !$0.accepted }
            } else {
                invitations = []
            }
        } catch {
            collabError = "Network error: \(error.localizedDescription)"
        }
    }

    private func sendInvite(planId: String, email: String) async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            inviteResult = "Email can't be empty."
            return
        }
        inviteSending = true
        defer { inviteSending = false }

        guard let url = URL(string: "\(AppConfig.collabAPIBaseURL)?action=invite") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = await AuthService().accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            inviteResult = "Sign in again to invite."
            return
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "planId": planId,
            "email": trimmed,
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if http.statusCode == 200 {
                let emailSent = (json?["emailSent"] as? Bool) ?? false
                inviteResult = emailSent ? "Invite sent to \(trimmed)." : "Invite created for \(trimmed). They can sign up to join."
                HapticEngine.success()
                await loadCollaborators(planId: planId)
            } else {
                inviteResult = (json?["error"] as? String) ?? "Invite failed (status \(http.statusCode))."
            }
        } catch {
            inviteResult = "Network error: \(error.localizedDescription)"
        }
    }

    private func removeCollaborator(planId: String, userId: String) async {
        guard let url = URL(string: "\(AppConfig.collabAPIBaseURL)?action=remove") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = await AuthService().accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "planId": planId,
            "userId": userId,
        ])
        _ = try? await URLSession.shared.data(for: request)
        await loadCollaborators(planId: planId)
    }

    private func revokeInvitation(invitationId: String) async {
        guard let plan = appState.activePlan else { return }
        guard let url = URL(string: "\(AppConfig.collabAPIBaseURL)?action=revoke") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = await AuthService().accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "invitationId": invitationId,
        ])
        _ = try? await URLSession.shared.data(for: request)
        await loadCollaborators(planId: plan.id)
    }
}

// MARK: - Collaborator response models

struct CollabPerson {
    let userId: String
    let name: String
    let email: String

    init?(dict: [String: Any]) {
        // userId field name differs between owner ({userId:..., isOwner:true})
        // and collaborator entries — both use "userId" per the API contract.
        guard let id = dict["userId"] as? String else { return nil }
        self.userId = id
        self.name = (dict["name"] as? String) ?? "Unknown"
        self.email = (dict["email"] as? String) ?? ""
    }
}

struct PendingInvitation {
    let id: String
    let email: String
    let accepted: Bool

    init?(dict: [String: Any]) {
        guard let id = dict["id"] as? String else { return nil }
        self.id = id
        self.email = (dict["email"] as? String) ?? ""
        self.accepted = (dict["accepted"] as? Bool) ?? false
    }
}

#Preview {
    ShareView()
        .environment(AppState())
}

// MARK: - QR code generator (Core Image)
//
// Web parity (`qr-code-styling` library, errorCorrectionLevel: 'H'). iOS
// uses CIFilter.qrCodeGenerator with the same correction level (H = up to
// 30% recovery, robust at small print sizes). No third-party deps.

extension UIImage {
    /// Generates a Seatbee-branded QR code: gold modules on white,
    /// with the bee logo overlaid in a white halo at the centre. Web
    /// parity (`qr-code-styling` config in App.jsx GuestQRPanel) uses
    /// the same gold + center logo treatment. H-level error correction
    /// (~30% recovery) is what lets the centre cells be obscured by
    /// the logo without breaking the scan.
    static func qrCode(from string: String,
                       size: CGFloat = 240,
                       accentColor: UIColor = UIColor(red: 201/255, green: 169/255, blue: 97/255, alpha: 1),
                       centerLogo: UIImage? = UIImage(named: "SeatbeeLogo")) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        let qrFilter = CIFilter.qrCodeGenerator()
        qrFilter.message = data
        qrFilter.correctionLevel = "H"
        guard let qrImage = qrFilter.outputImage else { return nil }

        // Recolour: black → accent (gold), white → fully transparent
        // so the white card background shows through cleanly. Web's
        // qr-code-styling does the equivalent.
        let colorFilter = CIFilter.falseColor()
        colorFilter.inputImage = qrImage
        colorFilter.color0 = CIColor(color: accentColor)
        colorFilter.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 0)
        guard let coloured = colorFilter.outputImage else { return nil }

        // Default CI output is ~25–35pt; scale to the requested size.
        let scale = size / coloured.extent.width
        let scaled = coloured.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        let qrUIImage = UIImage(cgImage: cgImage)

        // Composite white-card-background + QR + centre logo.
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            qrUIImage.draw(in: CGRect(x: 0, y: 0, width: size, height: size))

            if let logo = centerLogo {
                // ~22% of the QR's width — well within H-level's 30%
                // recovery budget, so the QR still scans reliably.
                let logoSize = size * 0.22
                let logoRect = CGRect(
                    x: (size - logoSize) / 2,
                    y: (size - logoSize) / 2,
                    width: logoSize, height: logoSize
                )
                // White halo behind the logo so gold-on-gold modules
                // don't bleed into it.
                let halo = logoRect.insetBy(dx: -logoSize * 0.18, dy: -logoSize * 0.18)
                UIColor.white.setFill()
                UIBezierPath(ovalIn: halo).fill()
                logo.draw(in: logoRect)
            }
        }
    }
}
