import SwiftUI
import CashFlowKit

struct CategorizationRulesView: View {
    @Bindable var viewModel: CategorizationRulesViewModel

    var body: some View {
        List {
            if let banner = viewModel.bannerMessage {
                Text(banner)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if viewModel.rules.isEmpty {
                ContentUnavailableView(
                    "No rules yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text(
                        "Rules run when you sync and whenever you save a rule. They categorize matching unlocked transactions."
                    )
                )
            } else {
                ForEach(viewModel.rules) { rule in
                    Button {
                        viewModel.editorRoute = .edit(rule.id)
                    } label: {
                        ruleRow(rule)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Delete", role: .destructive) {
                            Task { await viewModel.delete(rule) }
                        }
                    }
                }
                .onMove { source, destination in
                    Task { await viewModel.move(from: source, to: destination) }
                }
            }
        }
        .navigationTitle("Rules")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.editorRoute = .create
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add rule")
            }
        }
        .task {
            await viewModel.onAppear()
        }
        .sheet(item: $viewModel.editorRoute, onDismiss: {
            Task { await viewModel.reload() }
        }) { route in
            NavigationStack {
                editor(for: route)
            }
        }
        .disabled(viewModel.isBusy)
        .overlay {
            if viewModel.isBusy {
                ProgressView()
            }
        }
    }

    @ViewBuilder
    private func editor(for route: CategorizationRulesViewModel.EditorRoute) -> some View {
        switch route {
        case .create:
            CategorizationRuleEditorView(
                viewModel: makeEditorViewModel()
            )
        case .edit(let id):
            if let rule = viewModel.rules.first(where: { $0.id == id }) {
                CategorizationRuleEditorView(
                    viewModel: makeEditorViewModel(existing: rule)
                )
            }
        case .createFromTransaction(let title, let categoryID):
            CategorizationRuleEditorView(
                viewModel: makeEditorViewModel(
                    prefillTitle: title,
                    prefillCategoryID: categoryID
                )
            )
        }
    }

    private func makeEditorViewModel(
        existing: CategorizationRule? = nil,
        prefillTitle: String? = nil,
        prefillCategoryID: CategoryID? = nil
    ) -> CategorizationRuleEditorViewModel {
        CategorizationRuleEditorViewModel(
            ruleRepository: viewModel.ruleRepository,
            ruleApplying: viewModel.ruleApplying,
            accountRepository: viewModel.accountRepository,
            existing: existing,
            prefillTitle: prefillTitle,
            prefillCategoryID: prefillCategoryID
        )
    }

    private func ruleRow(_ rule: CategorizationRule) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: rule.appliesCategory
                ? CategoryIcon.systemName(for: rule.categoryID)
                : "pencil")
                .font(.body)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(ruleTitle(for: rule))
                    .font(.body.weight(.semibold))
                Text(viewModel.summary(for: rule))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Toggle(
                "Enabled",
                isOn: Binding(
                    get: { rule.isEnabled },
                    set: { newValue in
                        Task { await viewModel.setEnabled(rule, isEnabled: newValue) }
                    }
                )
            )
            .labelsHidden()
            .accessibilityLabel("Enable rule")
        }
    }

    private func ruleTitle(for rule: CategorizationRule) -> String {
        if rule.appliesCategory {
            return SystemCategory.category(for: rule.categoryID).name
        }
        if let renameTitle = rule.renameTitle {
            return "Rename to “\(renameTitle)”"
        }
        return "Rename"
    }
}
