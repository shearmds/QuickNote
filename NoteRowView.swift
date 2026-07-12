import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct NoteRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var note: Note
    /// On iPad master/detail this drives the selection; when nil (iPhone/macOS),
    /// tapping opens the edit sheet instead.
    var selection: Binding<Note?>? = nil

    @State private var isHovering = false
    @State private var showingEditSheet = false
    @State private var editedContent = ""
    @State private var isExportingNote = false
    @State private var noteDocument: NoteDocument?
    @State private var showingDeleteConfirmation = false
    @State private var saveErrorMessage: String?
    @ObservedObject private var deepLinkRouter = DeepLinkRouter.shared

    private var isSelected: Bool { selection?.wrappedValue?.id == note.id }

    // The note's title: its first non-empty line.
    private var titleLine: String {
        for raw in note.content.split(whereSeparator: \.isNewline) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return "Untitled Note"
    }

    // On iPad, tapping selects the note for the detail editor; elsewhere it
    // opens the edit sheet.
    private func beginEdit() {
        if let selection {
            selection.wrappedValue = note
        } else {
            editedContent = note.content
            showingEditSheet = true
        }
    }

    /// Opens this row's edit sheet if a widget deep link targets this note.
    /// Only the sheet-based layouts (iPhone/macOS, where `selection` is nil)
    /// respond; the iPad detail pane handles deep links via `selection`.
    private func openIfDeepLinked(_ id: UUID?) {
        guard selection == nil, let id, id == note.id else { return }
        editedContent = note.content
        showingEditSheet = true
        deepLinkRouter.pendingNoteID = nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Title (first line of the note) with the time beneath it.
            VStack(alignment: .leading, spacing: 4) {
                Text(titleLine)
                    .scaledFont(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(.primary.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Timestamp & Status
                HStack(spacing: 8) {
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.indigo)
                    }
                    Text(note.createdAt, style: .relative)
                        .scaledFont(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                    Text("ago")
                        .scaledFont(.caption)
                        .foregroundColor(.secondary.opacity(0.5))

                    if note.isArchived {
                        Text("Archived")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.indigo)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.indigo.opacity(0.08))
                            .cornerRadius(4)
                    }

                    Spacer()
                }
            }
            .opacity(note.isArchived ? 0.8 : 1) // Archived notes read as slightly receded

            // Hover/Quick Actions Column (macOS only; iOS uses tap + context menu)
            #if os(macOS)
            HStack(spacing: 8) {
                if isHovering {
                    // Pin Button
                    Button(action: togglePin) {
                        Image(systemName: note.isPinned ? "pin.slash" : "pin")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(note.isPinned ? .indigo : .secondary)
                            .padding(6)
                            .background(note.isPinned ? Color.indigo.opacity(0.12) : Color.primary.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(note.isPinned ? "Unpin note" : "Pin to top")

                    // Copy Button
                    Button(action: copyToClipboard) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(6)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Copy to clipboard")
                    
                    // Edit Button
                    Button(action: beginEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(6)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Edit note")
                    
                    // Archive / Unarchive Button
                    Button(action: toggleArchive) {
                        Image(systemName: note.isArchived ? "arrow.uturn.backward" : "archivebox")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(note.isArchived ? .indigo : .green.opacity(0.8))
                            .padding(6)
                            .background(note.isArchived ? Color.indigo.opacity(0.08) : Color.green.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(note.isArchived ? "Unarchive note" : "Archive note")
                    
                    // Delete Button
                    Button(action: { showingDeleteConfirmation = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.red.opacity(0.8))
                            .padding(6)
                            .background(Color.red.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete note")
                }
            }
            .frame(width: 152, alignment: .trailing) // Fits the five hover actions
            #endif
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(note.isArchived ? Color.primary.opacity(0.04) : Color.white)
        )
        // Accent spine: brand gradient for active notes, muted for archived.
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(note.isArchived ? AnyShapeStyle(Color.secondary.opacity(0.35)) : AnyShapeStyle(LinearGradient.brand))
                .frame(width: 4)
                .padding(.vertical, 12)
                .padding(.leading, 5)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSelected ? Color.indigo.opacity(0.9)
                        : (isHovering ? Color.indigo.opacity(0.35) : Color.primary.opacity(0.06)),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .shadow(
            color: Color.black.opacity(isHovering ? 0.12 : 0.05),
            radius: isHovering ? 9 : 4, x: 0, y: isHovering ? 4 : 2
        )
        .contentShape(Rectangle()) // Whole card (including padding) is tappable
        .onTapGesture(perform: beginEdit)
        // Widget deep link: on iPhone/macOS (no detail pane) the row whose note
        // was tapped opens its own edit sheet. iPad handles deep links via the
        // detail selection instead, so we ignore them when `selection` is set.
        .onAppear { openIfDeepLinked(deepLinkRouter.pendingNoteID) }
        .onChange(of: deepLinkRouter.pendingNoteID) { _, id in openIfDeepLinked(id) }
        .contextMenu {
            Button(action: togglePin) {
                Label(note.isPinned ? "Unpin" : "Pin to Top", systemImage: note.isPinned ? "pin.slash" : "pin")
            }
            Button(action: copyToClipboard) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button(action: beginEdit) {
                Label("Edit", systemImage: "pencil")
            }
            Button(action: toggleArchive) {
                Label(note.isArchived ? "Unarchive" : "Archive", systemImage: note.isArchived ? "arrow.uturn.backward" : "archivebox")
            }
            Divider()
            Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                Label("Delete Note", systemImage: "trash")
            }
        }
        // Hover state support (macOS)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        // Confirm before the (irreversible) delete from the quick actions/menu.
        .confirmationDialog(
            "Delete this note?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: deleteNote)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .saveErrorAlert(message: $saveErrorMessage)
        // Swipe to pin (iOS)
        #if os(iOS)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: togglePin) {
                Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
            }
            .tint(.indigo)
        }
        // Swipe to archive (iOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(action: toggleArchive) {
                Label(note.isArchived ? "Unarchive" : "Archive", systemImage: note.isArchived ? "arrow.uturn.backward" : "archivebox")
            }
            .tint(note.isArchived ? .indigo : .green)
            
            Button(action: beginEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.indigo)
        }
        #endif
        // Edit Dialog/Sheet
        .sheet(isPresented: $showingEditSheet) {
            #if os(iOS)
            NavigationStack {
                VStack(spacing: 16) {
                    TextEditor(text: $editedContent)
                        .scaledFont(.body)
                        .padding(8)
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                        .frame(maxHeight: .infinity)
                    
                    // iOS Quick Actions side-by-side
                    HStack(spacing: 12) {
                        Button(role: .destructive, action: {
                            deleteNote()
                            showingEditSheet = false
                        }) {
                            Label("Delete", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        
                        Button(action: {
                            let text = generateNoteExport()
                            noteDocument = NoteDocument(text: text)
                            isExportingNote = true
                        }) {
                            Label("Export...", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.indigo)
                    }
                }
                .padding(20)
                .navigationTitle("Edit Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            showingEditSheet = false
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save", action: saveEdits)
                        .fontWeight(.bold)
                    }
                }
                .fileExporter(
                    isPresented: $isExportingNote,
                    document: noteDocument,
                    contentType: .quickNoteMarkdown,
                    defaultFilename: "NoteExport.md"
                ) { result in
                    switch result {
                    case .success(let url):
                        print("Exported individual note successfully to \(url)")
                    case .failure(let error):
                        print("Failed to export individual note: \(error)")
                    }
                }
            }
            #else
            // macOS HUD Layout
            VStack(spacing: 16) {
                Text("Edit Note")
                    .scaledFont(.headline)
                    .fontWeight(.bold)
                
                TextEditor(text: $editedContent)
                    .scaledFont(.body)
                    .padding(8)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    .frame(minHeight: 300)
                
                HStack(spacing: 12) {
                    Button(role: .destructive, action: {
                        deleteNote()
                        showingEditSheet = false
                    }) {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    
                    Button("Cancel") {
                        showingEditSheet = false
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    
                    Button(action: {
                        let text = generateNoteExport()
                        noteDocument = NoteDocument(text: text)
                        isExportingNote = true
                    }) {
                        Label("Export...", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Save", action: saveEdits)
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            }
            .padding(20)
            .frame(width: 650, height: 440)
            .fileExporter(
                isPresented: $isExportingNote,
                document: noteDocument,
                contentType: .quickNoteMarkdown,
                defaultFilename: "NoteExport.md"
            ) { result in
                switch result {
                case .success(let url):
                    print("Exported individual note successfully to \(url)")
                case .failure(let error):
                    print("Failed to export individual note: \(error)")
                }
            }
            #endif
        }
    }
    
    private func saveEdits() {
        note.content = editedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        note.updatedAt = Date()
        do {
            try modelContext.save()
            showingEditSheet = false
        } catch {
            saveErrorMessage = "Your changes couldn't be saved: \(error.localizedDescription)"
        }
    }

    private func togglePin() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            note.isPinned.toggle()
            note.updatedAt = Date()
            do {
                try modelContext.save()
            } catch {
                saveErrorMessage = "This change couldn't be saved: \(error.localizedDescription)"
            }
        }
    }

    private func toggleArchive() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            note.isArchived.toggle()
            note.updatedAt = Date()
            do {
                try modelContext.save()
            } catch {
                saveErrorMessage = "This change couldn't be saved: \(error.localizedDescription)"
            }
        }
    }

    private func deleteNote() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            // Clear the iPad detail selection if we're deleting the open note.
            if selection?.wrappedValue?.id == note.id {
                selection?.wrappedValue = nil
            }
            modelContext.delete(note)
            do {
                try modelContext.save()
            } catch {
                saveErrorMessage = "The note couldn't be deleted: \(error.localizedDescription)"
            }
        }
    }
    
    private func generateNoteExport() -> String {
        return """
        # Note - \(note.createdAt.formatted())
        
        \(editedContent)
        """
    }
    
    private func copyToClipboard() {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(note.content, forType: .string)
        #else
        UIPasteboard.general.string = note.content
        #endif
    }
}
