import SwiftUI
import CashFlowKit

struct ManageTagsSheet: View {
    @Bindable var viewModel: InsightsViewModel
    @State private var isComposingTag = false

    var body: some View {
        NavigationStack {
            Form {
                if let error = viewModel.tagEditorError {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("insights.tags.error")
                    }
                }

                Section {
                    TagChipScroller(
                        items: viewModel.tags.map {
                            TagChipScroller.Item(
                                id: $0.id,
                                title: $0.name,
                                isSelected: viewModel.renamingTagID == $0.id,
                                accessibilityKey: $0.id.rawValue
                            )
                        },
                        isComposing: isComposingTag,
                        draftName: $viewModel.newTagName,
                        onSelect: { id in
                            if let tag = viewModel.tags.first(where: { $0.id == id }) {
                                viewModel.beginRename(tag)
                            }
                        },
                        onBeginCompose: { isComposingTag = true },
                        onSubmitCompose: {
                            Task {
                                await viewModel.createTag()
                                if viewModel.newTagName
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .isEmpty
                                {
                                    isComposingTag = false
                                }
                            }
                        },
                        onCancelCompose: {
                            isComposingTag = false
                            viewModel.newTagName = ""
                        },
                        accessibilityPrefix: "insights.tags"
                    )
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

                    if let renamingID = viewModel.renamingTagID {
                        HStack {
                            TextField("Rename tag", text: $viewModel.renameDraft)
                                .submitLabel(.done)
                                .onSubmit {
                                    Task { await viewModel.commitRename() }
                                }
                            Button("Save") {
                                Task { await viewModel.commitRename() }
                            }
                            .disabled(viewModel.isSavingTag)
                            Button("Delete", role: .destructive) {
                                if let tag = viewModel.tags.first(where: { $0.id == renamingID }) {
                                    Task { await viewModel.deleteTag(tag) }
                                }
                            }
                            .disabled(viewModel.isSavingTag)
                        }
                    }
                } footer: {
                    Text(
                        viewModel.renamingTagID == nil
                            ? "Tap a tag to rename or delete. Tags stay on this device."
                            : "Edit the name, then Save — or Delete to remove the tag."
                    )
                }
            }
            .navigationTitle("Tags")
            .dismissKeyboardOnEmptyTap()
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isComposingTag = false
                        viewModel.showManageTags = false
                    }
                }
            }
            .onAppear {
                isComposingTag = false
            }
        }
        .presentationDetents([.medium, .large])
    }
}
