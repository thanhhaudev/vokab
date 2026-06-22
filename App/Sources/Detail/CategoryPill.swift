import SwiftUI
import VokabKit

/// Teal folder pill that shows an entry's category and lets the user override it
/// (existing categories + "New category…"). SPEC §13.
struct CategoryPill: View {
    @EnvironmentObject private var env: AppEnvironment
    let current: String?
    /// Called with the chosen canonical name (already run through canonicalize) or nil.
    let onPick: (String?) -> Void

    @State private var taxonomy: [String] = []
    @State private var showingNew = false
    @State private var newName = ""

    var body: some View {
        Menu {
            ForEach(taxonomy, id: \.self) { name in
                Button { onPick(name) } label: {
                    if name == current { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
            }
            Divider()
            Button(L.t("New category…", "Chủ đề mới…")) { showingNew = true }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder")
                Text(current ?? L.t("Uncategorized", "Chưa phân loại"))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.saveFg)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Theme.saveBg).clipShape(Capsule())
        }
        .menuStyle(.borderlessButton).fixedSize()
        .task { taxonomy = (try? env.categories.currentTaxonomy()) ?? [] }
        .alert(L.t("New category", "Chủ đề mới"), isPresented: $showingNew) {
            TextField(L.t("Name", "Tên"), text: $newName)
            Button(L.t("Add", "Thêm")) {
                let canonical = (try? env.categories.canonicalize(newName)) ?? nil
                if let canonical {
                    onPick(canonical)
                    taxonomy = (try? env.categories.currentTaxonomy()) ?? taxonomy
                }
                newName = ""
            }
            Button(L.t("Cancel", "Huỷ"), role: .cancel) { newName = "" }
        }
    }
}
