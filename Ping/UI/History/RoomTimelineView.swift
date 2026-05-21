import SwiftUI

struct RoomTimelineView: View {
    @ObservedObject var viewModel: HistoryViewModel
    let cacheService: HistoryCacheService
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                ForEach(viewModel.groups) { group in
                    Section(header: dayHeader(group.date)) {
                        ForEach(group.messages, id: \.id) { msg in
                            MessageRowView(
                                message: msg,
                                isMine: msg.senderUid == appState.currentUser?.id,
                                isExpanded: viewModel.expandedMessageId == msg.id,
                                onTap: {
                                    if viewModel.expandedMessageId == msg.id {
                                        viewModel.expandedMessageId = nil
                                    } else {
                                        viewModel.expandedMessageId = msg.id
                                    }
                                },
                                cacheService: cacheService,
                                inlineController: viewModel.inlineController,
                                onSave: {
                                    Task { await viewModel.save(message: msg, cacheService: cacheService, currentUid: appState.currentUser?.id) }
                                },
                                onDelete: {
                                    Task { await viewModel.delete(message: msg, currentUid: appState.currentUser?.id) }
                                }
                            )
                        }
                    }
                }

                if viewModel.isLoading {
                    ProgressView().padding()
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func dayHeader(_ date: Date) -> some View {
        Text(dayLabel(date))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.windowBackgroundColor))
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "오늘" }
        if cal.isDateInYesterday(date) { return "어제" }
        return date.formatted(.dateTime.month().day().weekday(.abbreviated))
    }
}
