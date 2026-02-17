//
//  DraftSessionView.swift
//  AutoPrompter
//

import SwiftUI

struct DraftSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draftService = ScriptDraftService()
    @State private var editableTranscript: String = ""
    @State private var phase: Phase = .recording

    /// Called when the user accepts a script (raw or refined).
    var onAccept: (String) -> Void

    enum Phase {
        case recording
        case review
        case refined
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(headerTitle)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if phase == .recording {
                    // Recording indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text("Recording")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Divider()

            // Content
            switch phase {
            case .recording:
                recordingView
            case .review:
                reviewView
            case .refined:
                refinedView
            }

            Divider()

            // Actions
            actionBar
                .padding(12)
        }
        .frame(width: 480)
        .frame(minHeight: 400, maxHeight: 600)
        .background(.ultraThinMaterial)
        .onAppear {
            draftService.startRecording()
        }
        .onDisappear {
            if draftService.isRecording {
                draftService.stopRecording()
            }
        }
        .alert("Error", isPresented: Binding(
            get: { draftService.error != nil },
            set: { if !$0 { draftService.error = nil } }
        )) {
            Button("OK") { draftService.error = nil }
        } message: {
            Text(draftService.error ?? "")
        }
    }

    private var headerTitle: String {
        switch phase {
        case .recording: return "Free Run"
        case .review:    return "Review Transcript"
        case .refined:   return "Refined Script"
        }
    }

    // MARK: - Recording Phase

    private var recordingView: some View {
        VStack(spacing: 12) {
            // Live transcript
            ScrollViewReader { proxy in
                ScrollView {
                    Text(draftService.rawTranscript.isEmpty ? "Start speaking…" : draftService.rawTranscript)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(draftService.rawTranscript.isEmpty ? .tertiary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .id("transcript")
                }
                .onChange(of: draftService.rawTranscript) { _, _ in
                    withAnimation {
                        proxy.scrollTo("transcript", anchor: .bottom)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            // Audio level bars
            HStack(spacing: 2) {
                ForEach(Array(draftService.audioLevels.enumerated()), id: \.offset) { _, level in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.red.opacity(0.7))
                        .frame(width: 3, height: max(2, level * 24))
                }
            }
            .frame(height: 28)
            .animation(.easeOut(duration: 0.1), value: draftService.audioLevels)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Review Phase

    private var reviewView: some View {
        VStack(spacing: 8) {
            Text("Edit your transcript, then use it directly or refine with AI.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            TextEditor(text: $editableTranscript)
                .font(.system(size: 14, design: .rounded))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Refined Phase

    private var refinedView: some View {
        Group {
            if draftService.isRefining {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                        .controlSize(.large)
                    Text("Refining your script…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    Text(draftService.refinedText)
                        .font(.system(size: 14, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack {
            Button("Cancel") {
                draftService.stopRecording()
                dismiss()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)

            Spacer()

            switch phase {
            case .recording:
                Button {
                    draftService.stopRecording()
                    editableTranscript = draftService.rawTranscript
                    withAnimation(.easeInOut(duration: 0.2)) {
                        phase = .review
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10))
                        Text("Stop")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.regular)
                .disabled(draftService.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            case .review:
                HStack(spacing: 8) {
                    Button {
                        onAccept(editableTranscript)
                        dismiss()
                    } label: {
                        Text("Use as Script")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    Button {
                        // Update the service's raw transcript with edits, then refine
                        draftService.rawTranscript = editableTranscript
                        withAnimation(.easeInOut(duration: 0.2)) {
                            phase = .refined
                        }
                        draftService.refine()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                            Text("Refine with AI")
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(editableTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

            case .refined:
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            phase = .review
                        }
                    } label: {
                        Text("Back")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    Button {
                        onAccept(draftService.refinedText)
                        dismiss()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Use This")
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(draftService.isRefining || draftService.refinedText.isEmpty)
                }
            }
        }
    }
}
