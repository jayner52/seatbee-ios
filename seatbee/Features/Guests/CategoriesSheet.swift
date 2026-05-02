import SwiftUI

struct CategoriesSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var newCategoryName = ""
    @State private var selectedColor = "#C9A961"

    private let colorPresets = ["#C9A961", "#9CAF88", "#D4A5A5", "#8B9DC3", "#DDA0DD", "#87CEEB", "#98D8C8", "#FFD700", "#F4A460", "#20B2AA", "#778899", "#DB7093"]

    private var categories: [String] {
        let allCats = appState.activePlan?.guests.flatMap { $0.categories } ?? []
        return Array(Set(allCats)).sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Existing categories
                    if !categories.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CATEGORIES")
                                .font(SBFont.capsLabel)
                                .foregroundStyle(Color.sbWarm)
                                .letterSpacing(1.5)

                            ForEach(categories, id: \.self) { cat in
                                categoryRow(cat)
                            }
                        }
                    }

                    // Add new category
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ADD CATEGORY")
                            .font(SBFont.capsLabel)
                            .foregroundStyle(Color.sbWarm)
                            .letterSpacing(1.5)

                        HStack(spacing: 12) {
                            TextField("Category name", text: $newCategoryName)
                                .font(SBFont.body)
                                .padding(12)
                                .background(Color.sbIvory2)
                                .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))

                            Button {
                                addCategory()
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(Color.sbGold)
                            }
                            .buttonStyle(.plain)
                            .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }

                        // Color picker
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(colorPresets, id: \.self) { color in
                                    Circle()
                                        .fill(Color(hex: color))
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.sbCharcoal, lineWidth: selectedColor == color ? 2 : 0)
                                        )
                                        .onTapGesture {
                                            selectedColor = color
                                            HapticEngine.selection()
                                        }
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
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.sbGoldDk)
                }
            }
        }
    }

    private func categoryRow(_ category: String) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.sbGold)
                .frame(width: 12, height: 12)

            Text(category)
                .font(SBFont.body)
                .foregroundStyle(Color.sbCharcoal)

            Spacer()

            let count = appState.activePlan?.guests.filter { $0.categories.contains(category) }.count ?? 0
            Text("\(count) guests")
                .font(SBFont.caption)
                .foregroundStyle(Color.sbWarm)

            // Delete
            Button {
                deleteCategory(category)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.sbWarm2)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.sbIvory2)
        .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
    }

    private func addCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        newCategoryName = ""
        HapticEngine.success()
    }

    private func deleteCategory(_ category: String) {
        guard var plan = appState.activePlan else { return }
        for i in plan.guests.indices {
            plan.guests[i].categories.removeAll { $0 == category }
        }
        appState.activePlan = plan
        HapticEngine.medium()
        Task { try? await appState.database.savePlanData(plan: plan) }
    }
}

#Preview {
    CategoriesSheet()
        .environment(AppState())
}
