import SwiftUI
import Photos

struct SwipeCleanerView: View {
    @EnvironmentObject private var swipeStore: SwipeStore
    @StateObject private var session = SwipeSession()

    @State private var dragOffset: CGSize = .zero
    @State private var isAnimatingOut = false
    @State private var showFilters = false
    @State private var showReview = false
    @State private var loadedOnce = false

    private let swipeThreshold: CGFloat = 110

    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 14) {
                progressHeader
                ZStack {
                    if session.isLoading {
                        ProgressView("Loading your camera roll…")
                    } else if session.isFinished {
                        finishedView
                    } else {
                        deck
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                controls
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .navigationTitle("Swipe Cleaner")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showFilters = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showReview = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("\(swipeStore.markedForDeletion.count)")
                            .monospacedDigit()
                    }
                }
            }
        }
        .sheet(isPresented: $showFilters) {
            FilterSheet(filter: session.filter) { newFilter in
                session.filter = newFilter
                Task { await session.load(store: swipeStore) }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showReview, onDismiss: {
            Task { await session.load(store: swipeStore) }
        }) {
            DeletionReviewView()
        }
        .task {
            guard !loadedOnce else { return }
            loadedOnce = true
            await session.load(store: swipeStore)
        }
    }

    // MARK: Header

    private var progressHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Text(session.filter.summary)
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.card, in: Capsule())
                Spacer()
                Text("\(min(session.index, session.deck.count).grouped) / \(session.deck.count.grouped)")
                    .font(.subheadline.monospacedDigit().bold())
            }
            ProgressView(value: session.progress)
                .tint(Theme.accent)
            HStack(spacing: 16) {
                stat("\(session.sessionKept)", "kept", Theme.keep)
                stat("\(session.sessionDeleted)", "to delete", Theme.delete)
                stat("\(session.sessionSkipped)", "skipped", Theme.skip)
                Spacer()
            }
        }
        .padding(.top, 6)
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(value).font(.caption.monospacedDigit().bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Deck

    private var deck: some View {
        GeometryReader { geo in
            ZStack {
                if let next = session.next {
                    SwipeCard(asset: next)
                        .id(next.localIdentifier)
                        .scaleEffect(0.94)
                        .opacity(0.6)
                }
                if let current = session.current {
                    SwipeCard(asset: current)
                        .id(current.localIdentifier)
                        .overlay { stamp }
                        .offset(dragOffset)
                        .rotationEffect(.degrees(Double(dragOffset.width / 22)))
                        .gesture(dragGesture)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    @ViewBuilder
    private var stamp: some View {
        let x = dragOffset.width
        let y = dragOffset.height
        if x < -30 && abs(x) > abs(y) {
            StampLabel(text: "DELETE", color: Theme.delete, angle: 14)
                .opacity(min(1, Double(-x / swipeThreshold)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(24)
        } else if x > 30 && abs(x) > abs(y) {
            StampLabel(text: "KEEP", color: Theme.keep, angle: -14)
                .opacity(min(1, Double(x / swipeThreshold)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)
        } else if y < -30 {
            StampLabel(text: "SKIP", color: Theme.skip, angle: 0)
                .opacity(min(1, Double(-y / swipeThreshold)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(40)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isAnimatingOut else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard !isAnimatingOut else { return }
                let x = value.translation.width
                let y = value.translation.height
                let px = value.predictedEndTranslation.width
                let py = value.predictedEndTranslation.height
                if (x < -swipeThreshold || px < -swipeThreshold * 2.5) && abs(x) >= abs(y) {
                    commit(.delete)
                } else if (x > swipeThreshold || px > swipeThreshold * 2.5) && abs(x) >= abs(y) {
                    commit(.keep)
                } else if y < -swipeThreshold || py < -swipeThreshold * 2.5 {
                    commit(.skip)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        dragOffset = .zero
                    }
                }
            }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 18) {
            CircleButton(icon: "arrow.uturn.backward", color: .white, size: 52) {
                undo()
            }
            .disabled(session.history.isEmpty || isAnimatingOut)
            .opacity(session.history.isEmpty ? 0.4 : 1)

            CircleButton(icon: "xmark", color: Theme.delete, size: 68) {
                commit(.delete)
            }
            CircleButton(icon: "arrow.up", color: Theme.skip, size: 52) {
                commit(.skip)
            }
            CircleButton(icon: "heart.fill", color: Theme.keep, size: 68) {
                commit(.keep)
            }
            CircleButton(icon: "trash.fill", color: .white, size: 52) {
                showReview = true
            }
        }
        .disabled(session.isLoading)
        .padding(.vertical, 6)
    }

    private var finishedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundStyle(Theme.keep)
            Text(session.deck.isEmpty ? "Nothing to review here" : "All caught up!")
                .font(.title2.bold())
            Text(session.deck.isEmpty
                 ? "Try a different date range in Filters, or turn off \"Hide already reviewed\"."
                 : "\(swipeStore.markedForDeletion.count.grouped) item(s) are marked for deletion.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if !swipeStore.markedForDeletion.isEmpty {
                Button {
                    showReview = true
                } label: {
                    Text("Review & Delete").bold().frame(width: 220)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.delete)
            }
        }
        .padding()
    }

    // MARK: Actions

    private func commit(_ action: SwipeAction) {
        guard !isAnimatingOut, session.current != nil else { return }
        isAnimatingOut = true

        var target = dragOffset
        switch action {
        case .delete: target = CGSize(width: -700, height: dragOffset.height)
        case .keep: target = CGSize(width: 700, height: dragOffset.height)
        case .skip: target = CGSize(width: dragOffset.width, height: -1000)
        }
        switch action {
        case .delete: Haptics.warning()
        default: Haptics.tap()
        }
        withAnimation(.easeIn(duration: 0.2)) {
            dragOffset = target
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            session.apply(action, store: swipeStore)
            dragOffset = .zero
            isAnimatingOut = false
        }
    }

    private func undo() {
        guard !isAnimatingOut else { return }
        Haptics.tap()
        session.undo(store: swipeStore)
        dragOffset = .zero
    }
}

// MARK: - Pieces

struct SwipeCard: View {
    let asset: PHAsset

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(white: 0.09))
            AssetImage(asset: asset, fill: false, targetSize: CGSize(width: 1200, height: 1200))
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            info
        }
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .stroke(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
    }

    private var info: some View {
        HStack(spacing: 8) {
            if asset.mediaType == .video {
                Label(AssetGridCell.duration(asset.duration), systemImage: "video.fill")
            }
            if let date = asset.creationDate {
                Text(date.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .font(.caption.bold())
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.black.opacity(0.55), in: Capsule())
        .padding(14)
    }
}

struct StampLabel: View {
    let text: String
    let color: Color
    let angle: Double

    var body: some View {
        Text(text)
            .font(.system(size: 34, weight: .black, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 4))
            .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            .rotationEffect(.degrees(angle))
    }
}

struct CircleButton: View {
    let icon: String
    let color: Color
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(Theme.card, in: Circle())
                .overlay(Circle().stroke(color.opacity(0.35), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}
