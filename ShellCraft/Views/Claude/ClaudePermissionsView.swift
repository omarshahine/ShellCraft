import SwiftUI

struct ClaudePermissionsView: View {
    @Bindable var viewModel: ClaudePermissionsViewModel
    @State private var showAddSheet = false
    @State private var editingPermission: ClaudePermission?

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            filterBar
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            // Two-column layout
            HSplitView {
                // Allow list
                permissionList(
                    title: "Allow",
                    permissions: viewModel.allowPermissions,
                    count: viewModel.allowCount,
                    accentColor: .green
                )

                // Deny list
                permissionList(
                    title: "Deny",
                    permissions: viewModel.denyPermissions,
                    count: viewModel.denyCount,
                    accentColor: .red
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Permission", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            PermissionEditorSheet(mode: .add) { pattern, list in
                viewModel.add(pattern: pattern, list: list)
            }
        }
        .sheet(item: $editingPermission) { permission in
            PermissionEditorSheet(mode: .edit(permission)) { pattern, list in
                viewModel.update(permission, pattern: pattern, list: list)
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter permissions...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(6)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Picker("Category", selection: $viewModel.selectedCategory) {
                Text("All Categories").tag(PermissionCategory?.none)
                Divider()
                ForEach(PermissionCategory.allCases) { category in
                    Text(category.rawValue).tag(PermissionCategory?.some(category))
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)
        }
    }

    // MARK: - Permission List Column

    private func permissionList(
        title: String,
        permissions: [ClaudePermission],
        count: Int,
        accentColor: Color
    ) -> some View {
        VStack(spacing: 0) {
            // Column header
            HStack {
                Image(systemName: title == "Allow" ? "checkmark.shield" : "xmark.shield")
                    .foregroundStyle(accentColor)
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(accentColor.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Permission list
            List {
                ForEach(permissions) { permission in
                    permissionRow(permission, accentColor: accentColor)
                        .contextMenu {
                            Button("Edit") {
                                editingPermission = permission
                            }

                            let targetList: ClaudePermission.PermissionList = permission.list == .allow ? .deny : .allow
                            Button("Move to \(targetList.displayName)") {
                                viewModel.move(permission, to: targetList)
                            }

                            Divider()

                            Button("Delete", role: .destructive) {
                                viewModel.remove(permission)
                            }
                        }
                }
            }
            .listStyle(.plain)
        }
        .frame(minWidth: 300)
    }

    // MARK: - Permission Row

    private func permissionRow(_ permission: ClaudePermission, accentColor: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.pattern)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)

                Text(permission.category.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(categoryColor(permission.category).opacity(0.15))
                    .foregroundStyle(categoryColor(permission.category))
                    .clipShape(Capsule())
            }

            Spacer()

            Button(role: .destructive) {
                viewModel.remove(permission)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.6))
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private func categoryColor(_ category: PermissionCategory) -> Color {
        switch category {
        case .bash: .blue
        case .git: .orange
        case .buildTools: .purple
        case .fileAccess: .green
        case .webAccess: .cyan
        case .mcpTools: .indigo
        case .skills: .pink
        case .other: .gray
        }
    }
}
