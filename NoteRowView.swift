import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct NoteRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var note: Note
    
    @State private var isHovering = false
    @State private var showingEditSheet = false
    @State private var editedContent = ""
    @State private var isExportingNote = false
    @State private var noteDocument: NoteDocument?
    
    // Parse Markdown to AttributedString safely
    var parsedContent: AttributedString {
        do {
            return try AttributedString(markdown: note.content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        } catch {
            return AttributedString(note.content)
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Elegant Note Body Card
            VStack(alignment: .leading, spacing: 6) {
                // Markdown Content
                Text(parsedContent)
                    .font(.system(.body, design: .rounded))
                    .lineLimit(3) // Truncate list preview at 3 lines
                    .lineSpacing(3)
                    .foregroundColor(.primary.opacity(0.85))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Timestamp & Status
                HStack(spacing: 8) {
                    Text(note.createdAt, style: .relative)
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.7))
                    Text("ago")
                        .font(.system(.caption, design: .rounded))
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
            .contentShape(Rectangle()) // Makes the whole card area tappable
            .onTapGesture {
                editedContent = note.content
                showingEditSheet = true
            }
            
            // Hover/Quick Actions Column
            HStack(spacing: 8) {
                if isHovering {
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
                    Button(action: {
                        editedContent = note.content
                        showingEditSheet = true
                    }) {
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
                    Button(action: deleteNote) {
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
            .frame(width: 120, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        )
        .contextMenu {
            Button(action: copyToClipboard) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button(action: {
                editedContent = note.content
                showingEditSheet = true
            }) {
                Label("Edit", systemImage: "pencil")
            }
            Button(action: toggleArchive) {
                Label(note.isArchived ? "Unarchive" : "Archive", systemImage: note.isArchived ? "arrow.uturn.backward" : "archivebox")
            }
            Divider()
            Button(role: .destructive, action: deleteNote) {
                Label("Delete Note", systemImage: "trash")
            }
        }
        // Hover state support (macOS)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        // Swipe to archive (iOS)
        #if os(iOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(action: toggleArchive) {
                Label(note.isArchived ? "Unarchive" : "Archive", systemImage: note.isArchived ? "arrow.uturn.backward" : "archivebox")
            }
            .tint(note.isArchived ? .indigo : .green)
            
            Button(action: {
                editedContent = note.content
                showingEditSheet = true
            }) {
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
                        .font(.system(.body, design: .rounded))
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
                        Button("Save") {
                            note.content = editedContent.trimmingCharacters(in: .whitespacesAndNewlines)
                            note.updatedAt = Date()
                            try? modelContext.save()
                            showingEditSheet = false
                        }
                        .fontWeight(.bold)
                    }
                }
                .fileExporter(
                    isPresented: $isExportingNote,
                    document: noteDocument,
                    contentType: .plainText,
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
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                
                TextEditor(text: $editedContent)
                    .font(.system(.body, design: .rounded))
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
                    
                    Button("Save") {
                        note.content = editedContent.trimmingCharacters(in: .whitespacesAndNewlines)
                        note.updatedAt = Date()
                        try? modelContext.save()
                        showingEditSheet = false
                    }
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
                contentType: .plainText,
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
    
    private func toggleArchive() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            note.isArchived.toggle()
            note.updatedAt = Date()
            try? modelContext.save()
        }
    }
    
    private func deleteNote() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            modelContext.delete(note)
            try? modelContext.save()
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
