import SwiftUI
import CashFlowKit

struct AssistantProposalCard: View {
    @Bindable var viewModel: AssistantViewModel
    let proposal: AssistantProposal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(proposal.summary)
                .font(.body.weight(.semibold))
            Text(proposal.conditionSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Text("\(proposal.affectedCount) affected")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(proposal.isLargeSet ? .orange : .primary)
                if proposal.isLargeSet {
                    Text("Large set")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            if !proposal.warnings.isEmpty {
                ForEach(proposal.warnings, id: \.self) { warning in
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !proposal.samples.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Examples")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(proposal.samples) { sample in
                        Text("• \(sample.title) — \(sample.detail)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if proposal.appliesCategory || !proposal.tagNames.isEmpty {
                Toggle(
                    "Save Rule",
                    isOn: Binding(
                        get: { viewModel.pendingProposal?.saveAsRule ?? proposal.saveAsRule },
                        set: { viewModel.setSaveAsRule($0) }
                    )
                )
                .font(.subheadline)
            }

            HStack {
                Button("Discard") {
                    viewModel.discardPendingProposal()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isExecuting)

                Spacer()

                Button {
                    Task { await viewModel.executePendingProposal() }
                } label: {
                    if viewModel.isExecuting {
                        ProgressView()
                    } else {
                        Text("Run")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isExecuting || proposal.affectedCount == 0)
                .accessibilityIdentifier("assistant.run")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
