import SwiftUI

struct EditorView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTableId: String?
    @State private var selectedObjectId: String?
    @State private var showDrawer = false
    @State private var showGuestPicker = false
    @State private var showAddTable = false
    @State private var showAddVenueObject = false
    @State private var showRoomSetup = false
    @State private var showAllTablesList = false
    @State private var showDetailSheet = false
    @State private var showDeleteConfirm = false
    @State private var assigningSeatIndex: Int?
    @State private var fitToken: Int = 0
    @State private var showEditObject = false
    /// One-shot soft-warning nudge — fires once per session when a free
    /// plan crosses 80% of its seated cap. Tapping Upgrade routes to
    /// the paywall; Dismiss just closes the alert (count keeps climbing
    /// silently until the hard 100-cap blocks further seating).
    @State private var showSoftSeatedNudge = false
    // Floor plan visibility — defaults to hidden so a fresh plan doesn't
    // crowd the canvas with the source image. Persists per-plan in
    // UserDefaults keyed by plan ID so user preference survives switches.
    @State private var floorPlanVisible: Bool = false
    // Ruler overlay — gold tick marks + unit labels on top + left
    // edges of the room rect. Same per-plan UserDefaults persistence
    // as floorPlanVisible. Off by default to keep the default canvas
    // clean.
    @State private var rulerVisible: Bool = false

    // Selection tracking

    private var plan: SeatingPlan? { appState.activePlan }
    private var tables: [SeatTable] { plan?.tables ?? [] }
    private var objects: [RoomObject] { plan?.objects ?? [] }
    private var selectedTable: SeatTable? {
        tables.first { $0.id == selectedTableId }
    }

    var body: some View {
        ZStack {
            if plan == nil {
                emptyState
            } else {
                // UIKit-based canvas — rock solid gestures
                CanvasViewRepresentable(
                    tables: tables,
                    objects: objects,
                    guests: plan?.guests ?? [],
                    selectedTableId: selectedTableId,
                    selectedObjectId: selectedObjectId,
                    roomShape: plan?.roomShape,
                    roomWidth: plan?.roomWidth,
                    roomHeight: plan?.roomHeight,
                    customRoomPoints: plan?.customRoomPoints,
                    roomFlipH: plan?.roomFlipH,
                    roomFlipV: plan?.roomFlipV,
                    roomZones: plan?.roomZones,
                    floorPlanBase64: floorPlanVisible ? (plan?.rawFloorPlanImage?.value as? String) : nil,
                    floorPlanOpacity: plan?.rawFloorPlanOpacity,
                    rulerVisible: rulerVisible,
                    measurementUnit: plan?.measurementUnit,
                    fitToken: fitToken,
                    planId: plan?.id,
                    onSelectTable: { id in
                        // Tap = select only. The compact toolbar appears
                        // in the bottom bar; the full guest-list sheet
                        // opens via the toolbar's "Guest List" button or
                        // by double-tapping the table on the canvas.
                        selectedObjectId = nil
                        showEditObject = false
                        selectedTableId = id
                        HapticEngine.selection()
                    },
                    onSelectObject: { id in
                        // Close the table sheet — without this it stays
                        // onscreen with no content (selectedTable is now
                        // nil) and renders as a blank white pane. The
                        // object's edit sheet opens via the pencil in
                        // the selection toolbar, not on tap.
                        selectedTableId = nil
                        showDetailSheet = false
                        selectedObjectId = id
                        HapticEngine.selection()
                    },
                    onDeselectAll: {
                        selectedTableId = nil
                        selectedObjectId = nil
                        showDetailSheet = false
                        showEditObject = false
                    },
                    onMoveTable: { id, x, y in
                        updateTablePosition(id: id, x: x, y: y)
                        savePositions()
                    },
                    onMoveObject: { id, x, y in
                        updateObjectPosition(id: id, x: x, y: y)
                        savePositions()
                    },
                    onDoubleTapTable: { id in
                        // Power-user shortcut to the deeper editor —
                        // skip the toolbar and go straight to the guest
                        // list. Matches web's onDoubleClick behavior.
                        selectedObjectId = nil
                        showEditObject = false
                        selectedTableId = id
                        showDetailSheet = true
                        HapticEngine.medium()
                    }
                )
                .ignoresSafeArea(.all, edges: .bottom)

                VStack {
                    topBar
                    Spacer()
                }

                VStack {
                    Spacer()
                    bottomBar
                }
            }
        }
        .background(Color.sbIvory2)
        .sheet(isPresented: $showDetailSheet) {
            if let table = selectedTable {
                tableDetailSheet(table)
                    .presentationDetents([.fraction(0.50), .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.50)))
                    .presentationCornerRadius(24)
            }
        }
        .sheet(isPresented: $showDrawer) {
            if let table = selectedTable {
                TableDrawerView(table: table)
                    .environment(appState)
                    .presentationDetents([.fraction(0.82)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(24)
            }
        }
        .sheet(isPresented: $showAddTable) {
            AddTableSheet()
                .environment(appState)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddVenueObject) {
            VenueObjectsSheet()
                .environment(appState)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showRoomSetup) {
            RoomSetupSheet()
                .environment(appState)
        }
        .sheet(isPresented: $showAllTablesList) {
            AllTablesListSheet()
                .environment(appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showEditObject) {
            if let id = selectedObjectId {
                EditVenueObjectSheet(objectId: id)
                    .environment(appState)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .alert(selectedTableId != nil ? "Delete table?" : "Delete object?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                // Route to whichever selection is active — toolbar's
                // delete button is shared across tables and objects via
                // the same showDeleteConfirm flag.
                if let id = selectedTableId {
                    deleteTableById(id)
                } else if let id = selectedObjectId {
                    deleteObjectById(id)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("You're at \(appState.seatedGuestCount) of \(appState.activePlanLimits.seatedGuests) seated guests",
               isPresented: $showSoftSeatedNudge) {
            Button("Upgrade") { appState.showUpgrade = true }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("The free plan caps seating at \(appState.activePlanLimits.seatedGuests) guests. Upgrade for a larger plan and watermark-free exports.")
        }
        .task {
            if appState.activePlan == nil {
                let plans = (try? await appState.database.fetchPlans()) ?? []
                if let first = plans.first { appState.activePlan = first }
            }
            if selectedTableId == nil, let first = tables.first {
                selectedTableId = first.id
            }
            loadFloorPlanVisible()
            loadRulerVisible()
        }
        .onChange(of: plan?.id) { _, _ in
            loadFloorPlanVisible()
            loadRulerVisible()
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectTable)) { notification in
            if let tableId = notification.userInfo?["tableId"] as? String {
                withAnimation(.seatbee) {
                    selectedTableId = tableId
                    showDetailSheet = true
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 40))
                .foregroundStyle(Color.sbWarm2)
            Text("Select a plan from the Plans tab")
                .font(SBFont.body)
                .foregroundStyle(Color.sbWarm)
            SBButton(title: "Go to Plans", icon: "square.grid.2x2", variant: .gold) {
                appState.selectedTab = .plans
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.sbIvory)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        // Spacing tightened from 10 → 6 to claw back ~24pt for the
        // event-name title — was getting truncated to "tst…" at 5
        // characters with the wider gap. Title also gets layoutPriority
        // and minimumScaleFactor so long names shrink to fit before
        // truncating.
        HStack(spacing: 6) {
            Text(plan?.name ?? "")
                .font(SBFont.displayNav)
                .foregroundStyle(Color.sbCharcoal)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
                .padding(.trailing, 4)

            Spacer(minLength: 4)

            Button { appState.undo(); HapticEngine.light() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(appState.undoManager.canUndo ? Color.sbCharcoal : Color.sbWarm2)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .disabled(!appState.undoManager.canUndo)
            .accessibilityLabel("Undo")
            .accessibilityHint("Reverse your last edit")

            Button { appState.redo(); HapticEngine.light() } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(appState.undoManager.canRedo ? Color.sbCharcoal : Color.sbWarm2)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .disabled(!appState.undoManager.canRedo)
            .accessibilityLabel("Redo")
            .accessibilityHint("Reapply the change you just undid")

            Button { fitToken &+= 1; HapticEngine.light() } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.sbCharcoal)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Fit to screen")
            .accessibilityHint("Zoom out so every table fits in view")

            // Floor plan show/hide — only renders when the plan has an image.
            // Tinted gold when visible so the active state reads at a glance.
            if hasFloorPlan {
                Button {
                    floorPlanVisible.toggle()
                    persistFloorPlanVisible()
                    HapticEngine.selection()
                } label: {
                    Image(systemName: floorPlanVisible ? "photo.fill" : "photo")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(floorPlanVisible ? Color.sbGoldDk : Color.sbCharcoal)
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .accessibilityLabel(floorPlanVisible ? "Hide floor plan" : "Show floor plan")
                .accessibilityHint("Toggle the uploaded floor plan image behind the tables")
                .accessibilityValue(floorPlanVisible ? "Visible" : "Hidden")
            }

            // Ruler overlay toggle — gold tick marks + unit labels on
            // the top + left edges of the room rect. Always available
            // (no plan precondition); off by default so the canvas
            // stays clean unless the user wants scale context.
            Button {
                rulerVisible.toggle()
                persistRulerVisible()
                HapticEngine.selection()
            } label: {
                Image(systemName: rulerVisible ? "ruler.fill" : "ruler")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(rulerVisible ? Color.sbGoldDk : Color.sbCharcoal)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .accessibilityLabel(rulerVisible ? "Hide ruler" : "Show ruler")
            .accessibilityHint("Toggle measurement ticks along the room edges")
            .accessibilityValue(rulerVisible ? "On" : "Off")

            Button { showAllTablesList = true; HapticEngine.light() } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.sbCharcoal)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Tables list")
            .accessibilityHint("Open a sheet listing every table and who's seated there")


            Button { showRoomSetup = true } label: {
                Image(systemName: "square.dashed")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.sbGoldDk)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Room setup")
            .accessibilityHint("Edit room shape, dimensions, floor plan, and zones")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(
            LinearGradient(colors: [Color.sbIvory2, Color.sbIvory2.opacity(0)], startPoint: .top, endPoint: .bottom)
        )
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            // Selected item toolbar — compact in-canvas controls.
            if let table = selectedTable {
                tableSelectionToolbar(table)
                    .padding(14)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))
                    .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: -4)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            } else if let objId = selectedObjectId, let obj = objects.first(where: { $0.id == objId }) {
                HStack(spacing: 6) {
                    let def = venueObjectTypes.byType(obj.type)
                    Image(systemName: def?.icon ?? "square")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.sbGoldDk)
                    // lineLimit + truncation prevents long names like
                    // "Photo Booth" from wrapping awkwardly mid-word
                    // when the toolbar buttons claim most of the row.
                    Text(obj.name)
                        .font(SBFont.bodySmallBold)
                        .foregroundStyle(Color.sbCharcoal)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 4)
                    // Quick rotation — 45° steps either direction.
                    // Disabled when the object is locked so the user
                    // can't accidentally rotate something they pinned.
                    Button {
                        rotateObject(id: objId, by: -45)
                        HapticEngine.selection()
                    } label: {
                        Image(systemName: "rotate.left")
                            .font(.system(size: 14))
                            .foregroundStyle(obj.locked == true ? Color.sbWarm2 : Color.sbCharcoal)
                            .frame(width: 34, height: 34)
                            .background(.regularMaterial)
                            .clipShape(Circle())
                    }
                    .disabled(obj.locked == true)
                    .accessibilityLabel("Rotate left")
                    .accessibilityHint("Turn this object 45 degrees counter-clockwise")
                    Button {
                        rotateObject(id: objId, by: 45)
                        HapticEngine.selection()
                    } label: {
                        Image(systemName: "rotate.right")
                            .font(.system(size: 14))
                            .foregroundStyle(obj.locked == true ? Color.sbWarm2 : Color.sbCharcoal)
                            .frame(width: 34, height: 34)
                            .background(.regularMaterial)
                            .clipShape(Circle())
                    }
                    .disabled(obj.locked == true)
                    .accessibilityLabel("Rotate right")
                    .accessibilityHint("Turn this object 45 degrees clockwise")
                    Button {
                        toggleObjectLock(id: objId)
                        HapticEngine.selection()
                    } label: {
                        Image(systemName: obj.locked == true ? "lock.fill" : "lock")
                            .font(.system(size: 14))
                            .foregroundStyle(obj.locked == true ? Color.sbGold : Color.sbWarm)
                            .frame(width: 34, height: 34)
                            .background(.regularMaterial)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel(obj.locked == true ? "Unlock object" : "Lock object")
                    .accessibilityHint("Locked objects can't be moved or rotated by accident")
                    .accessibilityValue(obj.locked == true ? "Locked" : "Unlocked")
                    Button {
                        showEditObject = true
                        HapticEngine.selection()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.sbGoldDk)
                            .frame(width: 34, height: 34)
                            .background(.regularMaterial)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Edit object")
                    .accessibilityHint("Open the venue object editor")
                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.sbError)
                            .frame(width: 34, height: 34)
                            .background(.regularMaterial)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Delete object")
                    .accessibilityHint("Remove this object from the canvas")
                    // Duplicate — handy for mirrored stages / dance
                    // floors. Direct button (not in a menu) so the
                    // toolbar reads as a flat icon row.
                    Button {
                        duplicateObject(id: objId)
                    } label: {
                        Image(systemName: "plus.square.on.square")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.sbCharcoal)
                            .frame(width: 34, height: 34)
                            .background(.regularMaterial)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Duplicate object")
                    .accessibilityHint("Create an offset copy of this object")
                }
                .padding(14)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: -4)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            // Action bar (stats caption is overlaid on this so it
            // sits visually flush with the top of the FAB / AI
            // buttons, instead of getting pushed up by the VStack
            // flow above 44pt-tall buttons).
            HStack(spacing: 16) {
                Menu {
                    Button { showAddTable = true } label: {
                        Label("Add Table", systemImage: "circle")
                    }
                    Button { showAddVenueObject = true } label: {
                        Label("Venue Object", systemImage: "square.on.square")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.sbCharcoal)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                }
                .accessibilityLabel("Add to canvas")
                .accessibilityHint("Add a new table or venue object")

                Spacer()

                // AI pill
                Button { appState.selectedTab = .ai } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold))
                        Text("AI seat \(unseatedCount)").font(SBFont.inter(11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.sbGold)
                    .clipShape(Capsule())
                    .shadow(color: Color.sbGold.opacity(0.3), radius: 8, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("AI seat \(unseatedCount) remaining guests")
                .accessibilityHint("Open the AI seating screen to auto-assign guests to tables")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            // Stats caption — sits in the safe-area gap between the
            // FAB / AI buttons and the iOS tab bar, so it reads as a
            // status footer for the canvas without ever occluding
            // the action row above it.
            if (plan?.tables.isEmpty == false) || (plan?.guests.isEmpty == false) {
                statsCaption
                    .padding(.horizontal, 12)
                    .padding(.bottom, 70)
            } else {
                // Keep the same vertical reservation when the
                // caption is hidden so a fresh-empty plan doesn't
                // pull the FAB row down toward the tab bar.
                Color.clear.frame(height: 70)
            }
        }
    }

    // MARK: - Table Selection Toolbar
    //
    // Compact in-canvas controls that show when a table is selected.
    // Mirrors the venue-object toolbar pattern. Quick actions (seat
    // stepper, size, lock, delete) are inline; the heavier "open guest
    // list / deeper edit" action is a labeled Edit button so it's
    // unambiguous after the auto-open-on-tap behavior was removed.
    @ViewBuilder
    private func tableSelectionToolbar(_ table: SeatTable) -> some View {
        let isLocked = table.locked == true
        let sizePresets = TableDefaults.sizePresets(for: table.type)
        VStack(spacing: 10) {
            // Top row — name + stat
            HStack(spacing: 10) {
                SBTableGraphic(totalSeats: table.seats, filledSeats: table.filledCount, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(table.name)
                        .font(SBFont.bodySmallBold)
                        .foregroundStyle(Color.sbCharcoal)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("\(table.filledCount)/\(table.seats) seated · \(table.type.rawValue)")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                // Direct shortcut to the deep editor (shape, rotation,
                // notes, tags) — saves a hop versus going through
                // Guest List → Edit Table.
                Button {
                    showDrawer = true
                    HapticEngine.selection()
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.sbGoldDk)
                        .frame(width: 34, height: 34)
                        .background(.regularMaterial)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Edit table")
                .accessibilityHint("Open the full table editor with shape, rotation, notes, and tags")
                // Lock toggle — same visual language as venue object lock.
                Button {
                    toggleTableLock(id: table.id)
                    HapticEngine.selection()
                } label: {
                    Image(systemName: isLocked ? "lock.fill" : "lock")
                        .font(.system(size: 14))
                        .foregroundStyle(isLocked ? Color.sbGold : Color.sbWarm)
                        .frame(width: 34, height: 34)
                        .background(.regularMaterial)
                        .clipShape(Circle())
                }
                .accessibilityLabel(isLocked ? "Unlock table" : "Lock table")
                // Delete — confirms via existing showDeleteConfirm alert
                // path (we route via tableId vs objectId based on which
                // selection state is set when the alert fires).
                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.sbError)
                        .frame(width: 34, height: 34)
                        .background(.regularMaterial)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Delete table")
            }
            // Bottom row — quick adjustments + prominent Edit
            HStack(spacing: 8) {
                // Seat stepper (− 8 +). Disabled when locked.
                HStack(spacing: 0) {
                    Button {
                        adjustTableSeats(id: table.id, by: -1)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isLocked || table.seats <= 1 ? Color.sbWarm2 : Color.sbCharcoal)
                            .frame(width: 32, height: 32)
                    }
                    .disabled(isLocked || table.seats <= 1)
                    Text("\(table.seats)")
                        .font(SBFont.bodySmallBold)
                        .foregroundStyle(Color.sbCharcoal)
                        .frame(minWidth: 22)
                    Button {
                        adjustTableSeats(id: table.id, by: 1)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isLocked || table.seats >= 20 ? Color.sbWarm2 : Color.sbCharcoal)
                            .frame(width: 32, height: 32)
                    }
                    .disabled(isLocked || table.seats >= 20)
                }
                .background(.regularMaterial)
                .clipShape(Capsule())
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Seat count")
                .accessibilityValue("\(table.seats) seats")

                // Size menu — only for table types that have presets
                // (round/oval/rect). Head/sweetheart use semantic dims
                // and are sized in the deeper editor.
                if let presets = sizePresets {
                    Menu {
                        ForEach(presets, id: \.self) { ft in
                            Button("\(ft) ft") { setTableSize(id: table.id, sizeFt: ft) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "ruler")
                                .font(.system(size: 12, weight: .medium))
                            Text("Size")
                                .font(SBFont.inter(12, weight: .semibold))
                        }
                        .foregroundStyle(isLocked ? Color.sbWarm2 : Color.sbCharcoal)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(.regularMaterial)
                        .clipShape(Capsule())
                    }
                    .disabled(isLocked)
                    .accessibilityLabel("Change table size")
                }

                Spacer(minLength: 4)

                // Prominent Edit / Guest List entry — the heavy action
                // moved here from auto-open. Labeled "Open Guest List"
                // so users always know where their seating UI lives.
                Button {
                    showDetailSheet = true
                    HapticEngine.selection()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Guest List")
                            .font(SBFont.inter(13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Color.sbGoldDk)
                    .clipShape(Capsule())
                }
                .accessibilityLabel("Open guest list and deeper editing for \(table.name)")
            }
        }
    }

    // MARK: - Table Detail Sheet (split panel)
    //
    // Two equal columns: left = seat list, right = unseated guests.
    // Tapping a guest on the right assigns them to the next empty seat at
    // this table — no extra picker sheet needed. Tapping an empty seat on
    // the left opens the full GuestPickerSheet (unchanged).

    private func tableDetailSheet(_ table: SeatTable) -> some View {
        let isLocked = table.locked == true
        return HStack(alignment: .top, spacing: 0) {

            // LEFT — seats
            VStack(alignment: .leading, spacing: 0) {
                // Column header
                VStack(alignment: .leading, spacing: 2) {
                    Text(table.name)
                        .font(SBFont.bodySmallBold)
                        .foregroundStyle(Color.sbCharcoal)
                        .lineLimit(1)
                    Text("\(table.filledCount)/\(table.seats) seated · \(table.type.rawValue)")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

                // Prominent Edit Table button
                Button {
                    showDetailSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showDrawer = true }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil").font(.system(size: 12, weight: .semibold))
                        Text("Edit Table").font(SBFont.inter(13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.sbGoldDk)
                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

                Divider()

                ScrollView {
                    seatList(table: table)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            // RIGHT — unseated guests
            VStack(alignment: .leading, spacing: 0) {
                let unseated = unassignedGuests
                // Column header
                HStack {
                    Text("Guests")
                        .font(SBFont.bodySmallBold)
                        .foregroundStyle(Color.sbCharcoal)
                    Spacer()
                    if !unseated.isEmpty {
                        Text("\(unseated.count) unseated")
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbWarm)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider()

                if unseated.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Color.sbSage)
                        Text("All guests seated")
                            .font(SBFont.meta)
                            .foregroundStyle(Color.sbWarm)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(unseated, id: \.id) { guest in
                                quickAssignRow(guest, table: table, isLocked: isLocked)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.sbIvory)
        // Nest the guest picker here — sibling .sheet modifiers on
        // EditorView can't stack; the seat-tap picker would be a no-op.
        .sheet(isPresented: $showGuestPicker) {
            if let plan {
                GuestPickerSheet(guests: plan.guests, tables: plan.tables) { guest in
                    assignGuest(guest)
                }
                .environment(appState)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // Compact guest row for the right column. Tapping assigns the guest
    // to the next available empty seat at the current table.
    private func quickAssignRow(_ guest: Guest, table: SeatTable, isLocked: Bool) -> some View {
        Button {
            guard !isLocked else { return }
            assignGuestToNextEmpty(guest)
        } label: {
            HStack(spacing: 8) {
                SBAvatar(name: guest.displayName, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(guest.displayName)
                        .font(SBFont.bodySmall)
                        .foregroundStyle(Color.sbCharcoal)
                        .lineLimit(1)
                    if let label = plan?.displayCategoryLabel(for: guest) {
                        Text(label)
                            .font(SBFont.capsLabel)
                            .foregroundStyle(Color.sbWarm)
                    }
                }
                Spacer()
                Image(systemName: "plus.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isLocked ? Color.sbWarm2 : Color.sbGoldDk)
            }
            .padding(8)
            .background(Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
    }

    // MARK: - Seat List

    private func seatList(table: SeatTable) -> some View {
        let isLocked = table.locked == true
        return VStack(spacing: 6) {
            ForEach(0..<table.seats, id: \.self) { index in
                let guestId = table.assignments.first { $0.value == index }?.key
                let guest = plan?.guests.first { $0.id == guestId }
                Group {
                    if let guest {
                        filledSeatRow(index: index, guest: guest, isLocked: isLocked)
                    } else {
                        emptySeatRow(index: index, isLocked: isLocked)
                    }
                }
                // Drop target on every row — locked tables refuse the
                // drop. The dragged transferable is the guest id; the
                // drop fires reorderSeat(...) which decides between
                // a swap (target filled) and a move (target empty).
                .dropDestination(for: String.self) { items, _ in
                    guard !isLocked, let droppedId = items.first else { return false }
                    return reorderSeat(tableId: table.id, draggedGuestId: droppedId, targetIndex: index)
                }
            }
        }
    }

    private func filledSeatRow(index: Int, guest: Guest, isLocked: Bool = false) -> some View {
        let body = HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.sbGold).frame(width: 22, height: 22)
                Text("\(index + 1)").font(SBFont.inter(10, weight: .bold)).foregroundStyle(.white)
            }
            SBAvatar(name: guest.displayName, size: 30)
            // Name only — meal pill + category label removed because the
            // two-column drawer (PR #70) is too narrow for the chips and
            // they wrapped character-by-character ("Beef" stacked as
            // B/e/e/f). Full guest detail one tap away in the sheet.
            Text(guest.displayName)
                .font(SBFont.inter(13, weight: .semibold))
                .foregroundStyle(Color.sbCharcoal)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            if !isLocked {
                Button { unassignGuest(guest) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(Color.sbWarm2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(guest.side == .bride || guest.side == .groom ? Color.sbChampagne.opacity(0.4) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))

        // Long-press → drag the guest to another seat to reorder.
        // SwiftUI ships String as Transferable, so the guest id is
        // enough payload — the receiver looks it up + swaps. Locked
        // tables don't expose .draggable so the icon stays still.
        return Group {
            if isLocked {
                body
            } else {
                body
                    .draggable(guest.id) {
                        // Lift preview — a gold-ringed mini avatar
                        // makes it obvious which guest is in the
                        // air during the drag.
                        HStack(spacing: 8) {
                            SBAvatar(name: guest.displayName, size: 28)
                            Text(guest.displayName)
                                .font(SBFont.inter(13, weight: .semibold))
                                .foregroundStyle(Color.sbCharcoal)
                                .lineLimit(1)
                        }
                        .padding(8)
                        .background(Color.sbIvory)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.sbGold, lineWidth: 1.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
            }
        }
    }

    private func emptySeatRow(index: Int, isLocked: Bool = false) -> some View {
        Button {
            guard !isLocked else { return }
            assigningSeatIndex = index
            showGuestPicker = true
            HapticEngine.light()
        } label: {
            HStack(spacing: 10) {
                Circle().strokeBorder(Color.sbWarm2, style: StrokeStyle(lineWidth: 1, dash: [3, 2])).frame(width: 22, height: 22)
                Text("Empty seat · tap to assign").font(SBFont.meta).foregroundStyle(Color.sbWarm)
                Spacer()
                Image(systemName: "plus").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.sbWarm2)
            }
            .padding(8)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.sbLine, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data Mutations

    private var unassignedGuests: [Guest] {
        guard let plan else { return [] }
        let assignedIds = Set(plan.tables.flatMap { $0.assignments.keys })
        // Hide rsvp == .no — they can't be seated (assignGuestToNextEmpty
        // rejects them), so showing them in the quick-assign column makes
        // taps look broken. Matches GuestPickerSheet.unseatedGuests.
        return plan.guests.filter { !assignedIds.contains($0.id) && $0.rsvp != .no }
    }

    private func assignGuestToNextEmpty(_ guest: Guest) {
        // Defence-in-depth: GuestPickerSheet + RSVPSheet already
        // hide rsvp == .no guests, but quickAssignRow funnels here
        // too, and AI-generated row tap-to-seat could regress in
        // future. Drop on the floor + error haptic so callers don't
        // need their own guard.
        guard guest.rsvp != .no else {
            HapticEngine.error()
            return
        }
        guard let tableId = selectedTableId,
              var p = appState.activePlan,
              let ti = p.tables.firstIndex(where: { $0.id == tableId }) else { return }
        // Tier gate (web parity: App.jsx checkTierLimit('seat_guest')).
        // Free plan is capped at 100 SEATED guests — adding to the list
        // is free, but assigning to a table counts.
        guard appState.canSeatGuest(guest.id) else {
            appState.showUpgrade = true
            HapticEngine.error()
            return
        }
        let table = p.tables[ti]
        let occupiedSeats = Set(table.assignments.values)
        guard let emptyIndex = (0..<table.seats).first(where: { !occupiedSeats.contains($0) }) else { return }
        p.tables[ti].assignments[guest.id] = emptyIndex
        appState.activePlan = p
        HapticEngine.success()
        maybeFireSoftSeatedNudge()
        Task { try? await appState.database.savePlanData(plan: p) }
    }

    /// Tiny caption above the action bar — four numbers, separated
    /// by middots, in muted gold. Single line of 10pt text, no
    /// pill / no shadow, sits flush above the FAB / AI row so it
    /// reads as a status footer rather than a UI element. Each
    /// number labels itself ("108 guests" not "108") so a glance
    /// is enough.
    private var statsCaption: some View {
        HStack(spacing: 8) {
            captionSegment(value: attendingCount, label: "guest")
            captionDivider
            captionSegment(value: unseatedCount, label: "to seat")
            captionDivider
            captionSegment(value: totalSeatsCount, label: "seat")
            captionDivider
            captionSegment(value: openSeatsCount, label: "open")
        }
        // Monospaced design + .monospacedDigit so the numbers feel
        // like a stats readout / clock-radio segment, with constant
        // glyph width so segments don't shimmy as values change.
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .monospacedDigit()
        .tracking(0.5)
        .foregroundStyle(Color.sbGoldDk.opacity(0.85))
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    /// "108 guests" / "0 to seat" — pluralisation handled per label.
    /// "to seat" doesn't pluralise the way nouns do; everything else
    /// gets a trailing s when count != 1.
    private func captionSegment(value: Int, label: String) -> some View {
        let suffix: String = {
            if label == "to seat" { return label }
            return value == 1 ? label : label + "s"
        }()
        return Text("\(value) \(suffix)")
    }

    private var captionDivider: some View {
        Text("·").foregroundStyle(Color.sbGoldDk.opacity(0.45))
    }

    /// Whether a guest counts as "to be seated" — same rule the AI
    /// seat call uses (web App.jsx:13092, iOS SeatService): drop
    /// declined; pending/unknown only count when includeMaybes is on.
    private func isAttending(_ g: Guest) -> Bool {
        if g.rsvp == .no { return false }
        let includeMaybes = plan?.includeMaybes ?? true
        if includeMaybes { return true }
        return g.rsvp == .yes
    }

    /// Attending guests currently assigned to a seat — drives the
    /// editor's "X seated" stat.
    private var attendingSeatedCount: Int {
        guard let plan else { return 0 }
        let attendingIds = Set(plan.guests.filter { isAttending($0) }.map(\.id))
        return plan.tables.reduce(0) { sum, t in
            sum + t.assignments.keys.filter { attendingIds.contains($0) }.count
        }
    }

    /// Total attending guests on the plan (the "108 guests" segment).
    /// Same attending rule as the seater so all four caption numbers
    /// share a consistent basis.
    private var attendingCount: Int {
        plan?.guests.filter { isAttending($0) }.count ?? 0
    }

    /// Total chairs across the whole room.
    private var totalSeatsCount: Int {
        plan?.tables.reduce(0) { $0 + $1.seats } ?? 0
    }

    /// Chairs with no occupant. Counts every assignment (including
    /// stale declined / pending sitters) as "filled" because the
    /// seat is still physically taken on the canvas — what the user
    /// cares about is "do I have room to drop someone here?".
    private var openSeatsCount: Int {
        guard let plan else { return 0 }
        let assignedCount = plan.tables.reduce(0) { $0 + $1.assignments.count }
        return max(0, totalSeatsCount - assignedCount)
    }

    /// Attending guests waiting on a seat. Used by the AI pill +
    /// the new stat ribbon. Web parity: declined never count
    /// regardless of includeMaybes; pending only counts when
    /// includeMaybes is on.
    private var unseatedCount: Int {
        guard let plan else { return 0 }
        let seatedIds = Set(plan.tables.flatMap { $0.assignments.keys })
        return plan.guests.filter { isAttending($0) && !seatedIds.contains($0.id) }.count
    }

    private func updateTablePosition(id: String, x: Double, y: Double) {
        guard var p = appState.activePlan,
              let idx = p.tables.firstIndex(where: { $0.id == id }) else { return }
        p.tables[idx].x = x
        p.tables[idx].y = y
        appState.activePlan = p
    }

    private func updateObjectPosition(id: String, x: Double, y: Double) {
        guard var p = appState.activePlan,
              let idx = p.objects.firstIndex(where: { $0.id == id }) else { return }
        p.objects[idx].x = x
        p.objects[idx].y = y
        appState.activePlan = p
    }

    private func toggleObjectLock(id: String) {
        guard var p = appState.activePlan,
              let idx = p.objects.firstIndex(where: { $0.id == id }) else { return }
        p.objects[idx].locked = !(p.objects[idx].locked ?? false)
        appState.activePlan = p
        Task { try? await appState.database.savePlanData(plan: p) }
    }

    private func toggleTableLock(id: String) {
        guard var p = appState.activePlan,
              let idx = p.tables.firstIndex(where: { $0.id == id }) else { return }
        p.tables[idx].locked = !(p.tables[idx].locked ?? false)
        appState.activePlan = p
        Task { try? await appState.database.savePlanData(plan: p) }
    }

    /// Adjust seat count by ±delta, clamped to 1...20 (web parity range).
    /// Drops assignments that fall off the end so the data stays consistent.
    private func adjustTableSeats(id: String, by delta: Int) {
        guard var p = appState.activePlan,
              let idx = p.tables.firstIndex(where: { $0.id == id }) else { return }
        let new = max(1, min(20, p.tables[idx].seats + delta))
        if new == p.tables[idx].seats { return }
        p.tables[idx].seats = new
        // Drop assignments to seat indices that no longer exist after a
        // shrink — leaves the guest unseated rather than silently
        // pinned to a phantom seat.
        p.tables[idx].assignments = p.tables[idx].assignments.filter { $0.value < new }
        appState.activePlan = p
        HapticEngine.selection()
        Task { try? await appState.database.savePlanData(plan: p) }
    }

    /// Apply a TableDefaults size preset (in feet) to the table's
    /// dimensions. Type-aware — round writes diameter, others write
    /// width/height per the preset's aspect ratio.
    private func setTableSize(id: String, sizeFt: Int) {
        guard var p = appState.activePlan,
              let idx = p.tables.firstIndex(where: { $0.id == id }) else { return }
        let dims = TableDefaults.dimensions(for: p.tables[idx].type, sizeFt: sizeFt)
        if let d = dims.diameter { p.tables[idx].diameter = d }
        if let w = dims.width { p.tables[idx].width = w }
        if let h = dims.height { p.tables[idx].height = h }
        appState.activePlan = p
        HapticEngine.selection()
        Task { try? await appState.database.savePlanData(plan: p) }
    }

    private func deleteTableById(_ id: String) {
        guard var p = appState.activePlan else { return }
        p.tables.removeAll { $0.id == id }
        appState.activePlan = p
        selectedTableId = nil
        HapticEngine.medium()
        Task { try? await appState.database.savePlanData(plan: p) }
    }

    /// Add `delta` degrees to the object's rotation, normalised to
    /// 0..<360 so the slider in the VenueObjects sheet shows a sane
    /// value if the user opens it next.
    private func rotateObject(id: String, by delta: Double) {
        guard var p = appState.activePlan,
              let idx = p.objects.firstIndex(where: { $0.id == id }) else { return }
        let current = p.objects[idx].rotation ?? 0
        let next = (current + delta).truncatingRemainder(dividingBy: 360)
        p.objects[idx].rotation = next < 0 ? next + 360 : next
        appState.activePlan = p
        Task { try? await appState.database.savePlanData(plan: p) }
    }

    /// Clone the object with a fresh ID and a small offset so the
    /// duplicate is visible (otherwise it'd land directly on top of
    /// the original). New object becomes the selection so the user
    /// can immediately drag/edit it.
    private func duplicateObject(id: String) {
        guard var p = appState.activePlan,
              let idx = p.objects.firstIndex(where: { $0.id == id }) else { return }
        let src = p.objects[idx]
        // RoomObject.id is `let`, so construct a fresh RoomObject
        // rather than mutating the clone.
        let clone = RoomObject(
            id: "obj_\(UUID().uuidString.prefix(8))",
            type: src.type, name: src.name,
            x: src.x + 24, y: src.y + 24,
            width: src.width, height: src.height,
            rotation: src.rotation,
            color: src.color, category: src.category, icon: src.icon,
            isObstacle: src.isObstacle, locked: false
        )
        // Insert immediately after the source so the duplicate sits
        // one layer above the original.
        p.objects.insert(clone, at: idx + 1)
        appState.activePlan = p
        selectedObjectId = clone.id
        HapticEngine.success()
        Task { try? await appState.database.savePlanData(plan: p) }
    }


    private func deleteObjectById(_ id: String) {
        guard var p = appState.activePlan else { return }
        p.objects.removeAll { $0.id == id }
        appState.activePlan = p
        selectedObjectId = nil
        HapticEngine.medium()
        Task { try? await appState.database.savePlanData(plan: p) }
    }

    private func savePositions() {
        guard let plan = appState.activePlan else { return }
        Task { try? await appState.database.savePlanData(plan: plan) }
    }

    /// Drag-drop seat reorder. Accepts a guest id (from .draggable
    /// on filledSeatRow) and a target seat index on the SAME table.
    /// Empty target → move; filled target → swap. Returns true to
    /// accept the drop. Locked tables are filtered upstream so we
    /// don't need a guard here.
    private func reorderSeat(tableId: String, draggedGuestId: String, targetIndex: Int) -> Bool {
        guard var p = appState.activePlan,
              let ti = p.tables.firstIndex(where: { $0.id == tableId }) else { return false }
        var t = p.tables[ti]
        // Drag must originate from this same table — cross-table
        // moves go through the existing assign flow, not this drop.
        guard let currentIndex = t.assignments[draggedGuestId] else { return false }
        if currentIndex == targetIndex { return false } // no-op

        if let occupant = t.assignments.first(where: { $0.value == targetIndex })?.key {
            // Swap: target occupant takes the dragged guest's old seat.
            t.assignments[occupant] = currentIndex
            t.assignments[draggedGuestId] = targetIndex
        } else {
            // Move into empty seat.
            t.assignments[draggedGuestId] = targetIndex
        }
        p.tables[ti] = t
        appState.activePlan = p
        HapticEngine.success()
        Task { try? await appState.database.savePlanData(plan: p) }
        return true
    }

    private func unassignGuest(_ guest: Guest) {
        guard let tableId = selectedTableId,
              var p = appState.activePlan,
              let ti = p.tables.firstIndex(where: { $0.id == tableId }) else { return }
        p.tables[ti].assignments.removeValue(forKey: guest.id)
        appState.activePlan = p
        HapticEngine.medium()
        Task { try? await appState.database.savePlanData(plan: p) }
    }

    private func assignGuest(_ guest: Guest) {
        // See assignGuestToNextEmpty — same RSVP=.no defence here.
        guard guest.rsvp != .no else {
            HapticEngine.error()
            return
        }
        guard let seatIndex = assigningSeatIndex,
              let tableId = selectedTableId,
              var p = appState.activePlan,
              let ti = p.tables.firstIndex(where: { $0.id == tableId }) else { return }
        // Same tier gate as assignGuestToNextEmpty — every seat-assignment
        // path on the free plan must respect the 100-guest cap.
        guard appState.canSeatGuest(guest.id) else {
            appState.showUpgrade = true
            HapticEngine.error()
            return
        }
        p.tables[ti].assignments[guest.id] = seatIndex
        appState.activePlan = p
        HapticEngine.success()
        maybeFireSoftSeatedNudge()
        Task { try? await appState.database.savePlanData(plan: p) }
    }

    /// Fires the once-per-session 80% soft-warning toast on free tier
    /// when the user has just crossed into the danger zone. We reuse
    /// `appState.hasShownGuestSoftWarning` so users don't get nagged on
    /// every subsequent seat.
    private func maybeFireSoftSeatedNudge() {
        guard appState.isAtSoftSeatedWarning,
              !appState.hasShownGuestSoftWarning else { return }
        appState.hasShownGuestSoftWarning = true
        showSoftSeatedNudge = true
    }

    // MARK: - Floor plan visibility

    private var hasFloorPlan: Bool {
        if let raw = plan?.rawFloorPlanImage?.value as? String, !raw.isEmpty {
            return true
        }
        return false
    }

    private func floorPlanVisibleKey(_ planId: String) -> String {
        "seatbee.floorPlanVisible.\(planId)"
    }

    private func loadFloorPlanVisible() {
        guard let id = plan?.id else { floorPlanVisible = false; return }
        floorPlanVisible = UserDefaults.standard.bool(forKey: floorPlanVisibleKey(id))
    }

    private func persistFloorPlanVisible() {
        guard let id = plan?.id else { return }
        UserDefaults.standard.set(floorPlanVisible, forKey: floorPlanVisibleKey(id))
    }

    // MARK: - Ruler visibility (mirrors floor-plan persistence)

    private func rulerVisibleKey(_ planId: String) -> String {
        "seatbee.rulerVisible.\(planId)"
    }

    private func loadRulerVisible() {
        guard let id = plan?.id else { rulerVisible = false; return }
        rulerVisible = UserDefaults.standard.bool(forKey: rulerVisibleKey(id))
    }

    private func persistRulerVisible() {
        guard let id = plan?.id else { return }
        UserDefaults.standard.set(rulerVisible, forKey: rulerVisibleKey(id))
    }

    // MARK: - Category lookup (web parity)

    private func categoryName(forId id: String) -> String? {
        guard let raw = plan?.rawCategories else { return nil }
        let entry = raw.first { ($0["id"]?.value as? String) == id }
        return (entry?["name"]?.value as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}

#Preview {
    EditorView()
        .environment(AppState())
}
