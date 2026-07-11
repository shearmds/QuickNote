import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct NoteListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.createdAt, order: .reverse) private var allNotes: [Note]
    
    @State private var searchText = ""
    @State private var newNoteContent = ""
    @State private var showArchived = false
    @State private var isExportingBackup = false
    @State private var backupFolderDocument: NoteFolderDocument?
    @FocusState private var isInputFocused: Bool
    
    // Filtered notes based on search text (searches both active & archived) or folder toggle
    var filteredNotes: [Note] {
        if searchText.isEmpty {
            return allNotes.filter { $0.isArchived == showArchived }
        } else {
            return allNotes.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        #if os(iOS)
        NavigationStack {
            VStack(spacing: 0) {
                quickInputArea
                Divider()
                notesList
            }
            .navigationTitle("QuickNote")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search notes...")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button(action: { showArchived.toggle() }) {
                            Image(systemName: showArchived ? "archivebox.fill" : "archivebox")
                                .foregroundColor(showArchived ? .green : .secondary)
                        }
                        .help(showArchived ? "Show Active Notes" : "Show Archived Notes")
                        
                        Button(action: {
                            backupFolderDocument = NoteFolderDocument(notes: allNotes)
                            isExportingBackup = true
                        }) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .help("Export all notes...")
                    }
                }
            }
            .fileExporter(
                isPresented: $isExportingBackup,
                document: backupFolderDocument,
                contentType: .folder,
                defaultFilename: "QuickNotesBackup"
            ) { result in
                switch result {
                case .success(let url):
                    print("Exported notes successfully to \(url)")
                case .failure(let error):
                    print("Failed to export notes: \(error)")
                }
            }
        }
        #else
        // macOS HUD Layout
        VStack(spacing: 0) {
            macOSHeader
            quickInputArea
            Divider()
            notesList
        }
        .onAppear {
            isInputFocused = true
        }
        .frame(minWidth: 500, minHeight: 350)
        .fileExporter(
            isPresented: $isExportingBackup,
            document: backupFolderDocument,
            contentType: .folder,
            defaultFilename: "QuickNotesBackup"
        ) { result in
            switch result {
            case .success(let url):
                print("Exported notes successfully to \(url)")
            case .failure(let error):
                print("Failed to export notes: \(error)")
            }
        }
        #endif
    }
    
    private func saveNewNote() {
        let content = newNoteContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        
        let newNote = Note(content: content)
        modelContext.insert(newNote)
        try? modelContext.save() // Explicitly save SwiftData context
        newNoteContent = ""
        

    }
    
    // Shared Input Area
    private var quickInputArea: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                if newNoteContent.isEmpty {
                    #if os(macOS)
                    Text("Jot down something quick... (Cmd+Enter to save, Esc to close)")
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                    #else
                    Text("Jot down something quick...")
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                    #endif
                }
                
                TextEditor(text: $newNoteContent)
                    .font(.system(.body, design: .rounded))
                    .focused($isInputFocused)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(height: 90)
            }
            #if os(macOS)
            .background(Color.white)
            #else
            .background(Color.primary.opacity(0.03))
            #endif
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            
            HStack {
                Spacer()
                
                Button(action: saveNewNote) {
                    HStack(spacing: 4) {
                        #if os(macOS)
                        Text("Save")
                        Text("⌘⏎")
                            .font(.system(.caption, design: .rounded))
                            .opacity(0.6)
                        #else
                        Text("Add Note")
                        #endif
                    }
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(newNoteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.01))
    }
    
    // Shared Notes List
    private var notesList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if filteredNotes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: searchText.isEmpty ? (showArchived ? "archivebox" : "note.text") : "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(searchText.isEmpty ? (showArchived ? "No archived notes yet." : "No active notes. Jot one down!") : "No notes matching your search.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 40)
                } else {
                    ForEach(filteredNotes) { note in
                        NoteRowView(note: note)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
            }
            .padding(16)
        }
    }
    
    // macOS Header
    #if os(macOS)
    private var macOSHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.and.pencil")
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(.linearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            
            Text("QuickNote")
                .font(.system(.headline, design: .rounded))
                .fontWeight(.bold)
            
            Spacer()
            
            // Archive Toggle Button
            Button(action: { showArchived.toggle() }) {
                Image(systemName: showArchived ? "archivebox.fill" : "archivebox")
                    .font(.system(.title3, design: .rounded))
                    .foregroundColor(showArchived ? .green : .secondary)
                    .padding(.trailing, 4)
            }
            .buttonStyle(.plain)
            .help(showArchived ? "Show Active Notes" : "Show Archived Notes")
            
            // Bulk Export Button
            Button(action: {
                backupFolderDocument = NoteFolderDocument(notes: allNotes)
                isExportingBackup = true
            }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(.title3, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.trailing, 6)
            }
            .buttonStyle(.plain)
            .help("Export all notes...")
            
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Search notes...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .rounded))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(8)
            .frame(width: 220)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }
    #endif
}

// Helper Document struct for native File Exporter support (Single file)
struct NoteDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    
    var text: String
    
    init(text: String) {
        self.text = text
    }
    
    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let string = String(data: data, encoding: .utf8) {
            text = string
        } else {
            text = ""
        }
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
}

// Helper Document struct for exporting all notes into a single directory folder
struct NoteFolderDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }
    
    var notes: [Note]
    
    init(notes: [Note]) {
        self.notes = notes
    }
    
    init(configuration: ReadConfiguration) throws {
        self.notes = []
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        var fileWrappers: [String: FileWrapper] = [:]
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        
        for (index, note) in notes.enumerated() {
            let noteContent = """
            # Note - \(note.createdAt.formatted())
            
            \(note.content)
            """
            
            let data = noteContent.data(using: .utf8) ?? Data()
            let noteFileWrapper = FileWrapper(regularFileWithContents: data)
            
            let dateString = formatter.string(from: note.createdAt)
            
            // Clean up content to create a short preview name (first 25 characters)
            let cleanPreview = note.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
                .prefix(25)
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: "_")
            
            let suffix = cleanPreview.isEmpty ? "" : "_\(cleanPreview)"
            let filename = "Note_\(dateString)\(suffix).md"
            
            fileWrappers[filename] = noteFileWrapper
        }
        
        return FileWrapper(directoryWithFileWrappers: fileWrappers)
    }
}


