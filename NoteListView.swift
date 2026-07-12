import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct NoteListView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var newNoteContent = ""
    @State private var showArchived = false
    @State private var isExportingBackup = false
    @State private var backupFolderDocument: NoteFolderDocument?
    @State private var saveErrorMessage: String?
    @AppStorage("noteTextSizeV2") private var textSizeRaw: Int = NoteTextSize.standard.rawValue
    @FocusState private var isInputFocused: Bool
    @ObservedObject private var deepLinkRouter = DeepLinkRouter.shared
    @ObservedObject private var syncStatus = SyncStatus.shared

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var selectedNote: Note?   // iPad master/detail selection
    @State private var isSearchVisible = false        // iPhone: reveal search on tap
    @FocusState private var isSearchFocused: Bool
    #endif

    private var textSize: NoteTextSize { NoteTextSize(rawValue: textSizeRaw) ?? .standard }

    // The compose field fills half the screen on iPhone, but stays a fixed height
    // in the narrower iPad sidebar (and the macOS HUD).
    private var composeExpands: Bool {
        #if os(iOS)
        return hSizeClass != .regular
        #else
        return false
        #endif
    }

    private var composeEditorHeightRange: (min: CGFloat, max: CGFloat) {
        #if os(iOS)
        return hSizeClass == .regular ? (140, 140) : (90, .infinity)
        #else
        return (90, 90)
        #endif
    }

    // A whisper of warmth behind the content: near-white fading to a faint indigo tint.
    private var appBackgroundGradient: LinearGradient {
        LinearGradient(
            colors: [Color.white, Color.indigo.opacity(0.06)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        content
            .environment(\.noteTextScale, textSize.scale)
            .preferredColorScheme(.light)
            // Keeps the widget's App Group snapshot in sync with pinned notes.
            .background(PinnedSnapshotSync())
            .onAppear {
                if let id = deepLinkRouter.pendingNoteID { handleDeepLink(id) }
            }
            .onChange(of: deepLinkRouter.pendingNoteID) { _, newID in
                if let newID { handleDeepLink(newID) }
            }
            // Warn when the store isn't syncing, so "local only" is never a silent surprise.
            .safeAreaInset(edge: .top) { syncBanner }
    }

    @ViewBuilder
    private var syncBanner: some View {
        if syncStatus.needsAttention {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.icloud")
                Text(syncStatus.label)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color(red: 0.72, green: 0.45, blue: 0.0))
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.16))
        }
    }

    /// Resolves a widget deep link. On the iPad two-pane layout this opens the
    /// note in the detail editor and clears the pending id. On iPhone and macOS
    /// the matching `NoteRowView` opens its own edit sheet instead (it clears the
    /// pending id itself), so we leave it untouched here.
    private func handleDeepLink(_ id: UUID) {
        #if os(iOS)
        if hSizeClass == .regular {
            var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let note = try? modelContext.fetch(descriptor).first {
                selectedNote = note
            }
            deepLinkRouter.pendingNoteID = nil
        }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        if hSizeClass == .regular {
            iPadBody       // wide iPad: list + editor
        } else {
            iPhoneBody     // iPhone, or iPad in a narrow split
        }
        #else
        macOSBody
        #endif
    }

    #if os(iOS)
    // iPhone (and compact iPad): single column, tap a note to edit in a sheet.
    private var iPhoneBody: some View {
        NavigationStack {
            listColumn {
                VStack(spacing: 0) {
                    if isSearchVisible {
                        iPhoneSearchBar
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    quickInputArea
                    Divider()
                    FilteredNotesList(searchText: searchText, showArchived: showArchived)
                        .scrollDismissesKeyboard(.immediately)
                }
            }
        }
        // The compose field should never grab focus (and pop the keyboard) on
        // launch — that's macOS HUD behavior, not iPhone.
        .onAppear { isInputFocused = false }
    }

    // A search field that slides in from the top when the toolbar's magnifying
    // glass is tapped. Kept above the compose field so the keyboard never hides
    // it. Styled to match the macOS search bar.
    private var iPhoneSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search notes...", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            Button {
                searchText = ""
                isSearchFocused = false
                withAnimation(.easeInOut(duration: 0.2)) { isSearchVisible = false }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .scaledFont(.body)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.06))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // iPad: two-pane master/detail — the note list on the left, editor on the right.
    private var iPadBody: some View {
        NavigationSplitView {
            listColumn {
                VStack(spacing: 0) {
                    quickInputArea
                    Divider()
                    FilteredNotesList(searchText: searchText, showArchived: showArchived, selection: $selectedNote)
                }
            }
            // iPad keeps the standard always-visible search field in the sidebar.
            .searchable(text: $searchText, prompt: "Search notes...")
        } detail: {
            NavigationStack {
                if let selectedNote {
                    NoteEditorPane(note: selectedNote) { self.selectedNote = nil }
                        .id(selectedNote.id)
                } else {
                    editorPlaceholder
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // Shared decoration for the list column (title, search, toolbar, exporters).
    @ViewBuilder
    private func listColumn<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .background(appBackgroundGradient.ignoresSafeArea())
            .navigationTitle("QuickNote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { listToolbarContent }
            .saveErrorAlert(message: $saveErrorMessage)
            .fileExporter(
                isPresented: $isExportingBackup,
                document: backupFolderDocument,
                contentType: .folder,
                defaultFilename: "QuickNotesBackup"
            ) { result in
                switch result {
                case .success(let url): print("Exported notes successfully to \(url)")
                case .failure(let error): print("Failed to export notes: \(error)")
                }
            }
    }

    @ToolbarContentBuilder
    private var listToolbarContent: some ToolbarContent {
        // iPhone reveals search on demand; iPad has the always-visible field.
        if hSizeClass != .regular {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isSearchVisible = true }
                    isSearchFocused = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.primary)
                }
                .help("Search notes")
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            // Baseline alignment keeps the icons' bottoms on a shared line, so
            // the taller square.and.arrow.up glyph no longer sits low. All three
            // share one color (green only when the archive filter is active).
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Button(action: { showArchived.toggle() }) {
                    Image(systemName: showArchived ? "archivebox.fill" : "archivebox")
                        .foregroundStyle(showArchived ? Color.green : Color.primary)
                }
                .help(showArchived ? "Show Active Notes" : "Show Archived Notes")

                Button(action: exportAllNotes) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(Color.primary)
                }
                .help("Export all notes...")

                Menu {
                    Picker("Text Size", selection: $textSizeRaw) {
                        ForEach(NoteTextSize.allCases) { size in
                            Text(size.label).tag(size.rawValue)
                        }
                    }
                } label: {
                    Image(systemName: "textformat.size")
                        .foregroundStyle(Color.primary)
                }
            }
            .font(.body)
            .imageScale(.large)
        }
    }

    private var editorPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 44))
                .foregroundStyle(
                    LinearGradient(colors: [.indigo.opacity(0.5), .purple.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                )
            Text("Select a note to edit")
                .scaledFont(.headline)
                .foregroundColor(.secondary)
            Text("or jot a new one on the left")
                .scaledFont(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appBackgroundGradient.ignoresSafeArea())
    }
    #endif

    #if os(macOS)
    // macOS HUD Layout
    private var macOSBody: some View {
        VStack(spacing: 0) {
            macOSHeader
            quickInputArea
            Divider()
            FilteredNotesList(searchText: searchText, showArchived: showArchived)
        }
        .onAppear {
            isInputFocused = true
        }
        .frame(minWidth: 500, minHeight: 350)
        .saveErrorAlert(message: $saveErrorMessage)
        .fileExporter(
            isPresented: $isExportingBackup,
            document: backupFolderDocument,
            contentType: .folder,
            defaultFilename: "QuickNotesBackup"
        ) { result in
            switch result {
            case .success(let url): print("Exported notes successfully to \(url)")
            case .failure(let error): print("Failed to export notes: \(error)")
            }
        }
    }
    #endif
    
    private func saveNewNote() {
        let content = newNoteContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        let newNote = Note(content: content)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            modelContext.insert(newNote)
        }
        do {
            try modelContext.save()
            newNoteContent = "" // Only clear the field once the note is safely saved.
        } catch {
            saveErrorMessage = "Your note couldn't be saved: \(error.localizedDescription)"
        }
    }

    /// Fetches every note on demand for the "Export all" action, so the view
    /// doesn't need to keep a second live query of the entire store in memory.
    private func exportAllNotes() {
        let descriptor = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let notes = (try? modelContext.fetch(descriptor)) ?? []
        backupFolderDocument = NoteFolderDocument(notes: notes)
        isExportingBackup = true
    }
    
    // Shared Input Area
    private var quickInputArea: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                if newNoteContent.isEmpty {
                    #if os(macOS)
                    Text("Jot down something quick... (Cmd+Enter to save, Esc to close)")
                        .scaledFont(.body)
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                    #else
                    Text("Jot down something quick...")
                        .scaledFont(.body)
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                    #endif
                }
                
                TextEditor(text: $newNoteContent)
                    .scaledFont(.body)
                    .focused($isInputFocused)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(minHeight: composeEditorHeightRange.min, maxHeight: composeEditorHeightRange.max)
                    #if os(iOS)
                    // Give the on-screen keyboard an explicit way to close.
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { isInputFocused = false }
                        }
                    }
                    #endif
            }
            .background(Color.white)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isInputFocused ? AnyShapeStyle(LinearGradient.brand) : AnyShapeStyle(Color.primary.opacity(0.1)),
                        lineWidth: isInputFocused ? 1.5 : 1
                    )
            )
            .shadow(
                color: isInputFocused ? Color.indigo.opacity(0.22) : Color.black.opacity(0.05),
                radius: isInputFocused ? 7 : 3, x: 0, y: 2
            )
            .animation(.easeInOut(duration: 0.2), value: isInputFocused)
            
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
                    .background(LinearGradient.brand)
                    .cornerRadius(8)
                    .shadow(color: Color.indigo.opacity(0.35), radius: 5, x: 0, y: 3)
                    .opacity(newNoteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(newNoteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .animation(.easeInOut(duration: 0.2), value: newNoteContent.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(16)
        // On iPhone, claim roughly half the height for a comfortably tall entry
        // field; on iPad/macOS it stays a fixed height (see composeEditorHeightRange).
        .frame(maxHeight: composeExpands ? .infinity : nil)
        .background(Color.primary.opacity(0.01))
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
            Button(action: exportAllNotes) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(.title3, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.trailing, 6)
            }
            .buttonStyle(.plain)
            .help("Export all notes...")

            // Text Size Menu
            Menu {
                Picker("Text Size", selection: $textSizeRaw) {
                    ForEach(NoteTextSize.allCases) { size in
                        Text(size.label).tag(size.rawValue)
                    }
                }
            } label: {
                Image(systemName: "textformat.size")
                    .font(.system(.title3, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.trailing, 6)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Adjust text size")

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

extension UTType {
    /// Markdown content type for single-note exports. Conforms to plain text so
    /// it remains a valid text file, while carrying the `.md` extension the
    /// exported content actually uses.
    static let quickNoteMarkdown = UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
}

// Helper Document struct for native File Exporter support (Single file)
struct NoteDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.quickNoteMarkdown] }
    
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

// A plain, Sendable snapshot of the fields we export, so the document can be
// serialized off the main actor without touching MainActor-isolated `Note`.
struct NoteExportItem: Sendable {
    let content: String
    let createdAt: Date
}

// Helper Document struct for exporting all notes into a single directory folder
struct NoteFolderDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }

    var items: [NoteExportItem]

    init(notes: [Note]) {
        // Snapshot model values here (on the caller's main actor) so the
        // `fileWrapper(configuration:)` serialization can safely run off-main.
        self.items = notes.map { NoteExportItem(content: $0.content, createdAt: $0.createdAt) }
    }

    init(configuration: ReadConfiguration) throws {
        self.items = []
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        var fileWrappers: [String: FileWrapper] = [:]

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"

        for (index, note) in items.enumerated() {
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
            // Include the note's index so notes created within the same second
            // (or with identical previews) never collide and overwrite each other.
            let indexString = String(format: "%03d", index + 1)
            let filename = "Note_\(dateString)_\(indexString)\(suffix).md"

            fileWrappers[filename] = noteFileWrapper
        }
        
        return FileWrapper(directoryWithFileWrappers: fileWrappers)
    }
}

/// Displays the notes list using a SwiftData `@Query` whose predicate filters in
/// the store itself, rather than fetching every note and filtering in memory.
/// The query is rebuilt whenever the search text or archive toggle changes.
private struct FilteredNotesList: View {
    @Query private var notes: [Note]
    private let searchText: String
    private let showArchived: Bool
    private let selection: Binding<Note?>?   // non-nil on iPad master/detail

    init(searchText: String, showArchived: Bool, selection: Binding<Note?>? = nil) {
        self.searchText = searchText
        self.showArchived = showArchived
        self.selection = selection
        // With no search text, show just the selected tab (active vs. archived).
        // While searching, match content across BOTH active and archived notes.
        let predicate = #Predicate<Note> { note in
            (searchText.isEmpty && note.isArchived == showArchived) ||
            (!searchText.isEmpty && note.content.localizedStandardContains(searchText))
        }
        // Sorted newest-first here; pinned notes are floated to the top in `body`.
        _notes = Query(filter: predicate, sort: \Note.createdAt, order: .reverse)
    }

    // Pinned notes first, then the rest — each group already newest-first from the query.
    private var orderedNotes: [Note] {
        notes.filter(\.isPinned) + notes.filter { !$0.isPinned }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if notes.isEmpty {
                    emptyState
                } else {
                    ForEach(orderedNotes) { note in
                        NoteRowView(note: note, selection: selection)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
            }
            .padding(16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: searchText.isEmpty ? (showArchived ? "archivebox" : "note.text") : "magnifyingglass")
                .font(.system(size: 34))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.indigo.opacity(0.55), .purple.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            Text(searchText.isEmpty ? (showArchived ? "No archived notes yet." : "No active notes. Jot one down!") : "No notes matching your search.")
                .scaledFont(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 40)
    }
}

/// User-selectable text size, expressed as a scale multiplier applied on top of
/// each text style's natural size. This works on both iOS and macOS (macOS does
/// not scale text styles via Dynamic Type, so we scale explicitly). At `.standard`
/// (1.0) on iOS this still tracks the system's own text-size setting, because the
/// base sizes come from the platform's preferred fonts.
enum NoteTextSize: Int, CaseIterable, Identifiable {
    case small, standard, large, xLarge, xxLarge

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .small:    return "Small"
        case .standard: return "Default"
        case .large:    return "Large"
        case .xLarge:   return "Extra Large"
        case .xxLarge:  return "Huge"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small:    return 0.85
        case .standard: return 1.0
        case .large:    return 1.2
        case .xLarge:   return 1.4
        case .xxLarge:  return 1.7
        }
    }
}

#if os(iOS)
/// The editor pane shown on the right side of the iPad master/detail layout.
/// Edits the note in place (SwiftData autosaves; we also save on disappear).
private struct NoteEditorPane: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var note: Note
    var onDelete: () -> Void

    @State private var isExportingNote = false
    @State private var noteDocument: NoteDocument?
    @State private var showingDeleteConfirmation = false
    @State private var saveErrorMessage: String?

    var body: some View {
        TextEditor(text: $note.content)
            .scaledFont(.body)
            .scrollContentBackground(.hidden)
            .padding(20)
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: togglePin) {
                        Image(systemName: note.isPinned ? "pin.slash" : "pin")
                            .foregroundColor(note.isPinned ? .indigo : .secondary)
                    }
                    .help(note.isPinned ? "Unpin note" : "Pin to top")

                    Button(action: toggleArchive) {
                        Image(systemName: note.isArchived ? "arrow.uturn.backward" : "archivebox")
                    }
                    .help(note.isArchived ? "Unarchive note" : "Archive note")

                    Button {
                        noteDocument = NoteDocument(text: generateExport())
                        isExportingNote = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help("Export note...")

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete note")
                }
            }
            .onChange(of: note.content) { _, _ in note.updatedAt = Date() }
            .onDisappear { try? modelContext.save() }
            .confirmationDialog(
                "Delete this note?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    modelContext.delete(note)
                    try? modelContext.save()
                    onDelete()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
            .saveErrorAlert(message: $saveErrorMessage)
            .fileExporter(
                isPresented: $isExportingNote,
                document: noteDocument,
                contentType: .quickNoteMarkdown,
                defaultFilename: "NoteExport.md"
            ) { _ in }
    }

    private func togglePin() {
        note.isPinned.toggle()
        note.updatedAt = Date()
        save()
    }

    private func toggleArchive() {
        note.isArchived.toggle()
        note.updatedAt = Date()
        save()
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            saveErrorMessage = "This change couldn't be saved: \(error.localizedDescription)"
        }
    }

    private func generateExport() -> String {
        """
        # Note - \(note.createdAt.formatted())

        \(note.content)
        """
    }
}
#endif

extension LinearGradient {
    /// The app's signature indigo→purple accent gradient, reused across the UI.
    static let brand = LinearGradient(
        colors: [.indigo, .purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Gives buttons a subtle press-down response without changing their look.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct NoteTextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    /// Multiplier applied to note text by `scaledFont(_:)`.
    var noteTextScale: CGFloat {
        get { self[NoteTextScaleKey.self] }
        set { self[NoteTextScaleKey.self] = newValue }
    }
}

extension Font.TextStyle {
    /// The natural point size of this text style on the current platform,
    /// which on iOS already reflects the user's system text-size setting.
    var platformPointSize: CGFloat {
        #if os(macOS)
        let nsStyle: NSFont.TextStyle
        switch self {
        case .largeTitle:  nsStyle = .largeTitle
        case .title:       nsStyle = .title1
        case .title2:      nsStyle = .title2
        case .title3:      nsStyle = .title3
        case .headline:    nsStyle = .headline
        case .subheadline: nsStyle = .subheadline
        case .callout:     nsStyle = .callout
        case .footnote:    nsStyle = .footnote
        case .caption:     nsStyle = .caption1
        case .caption2:    nsStyle = .caption2
        default:           nsStyle = .body
        }
        return NSFont.preferredFont(forTextStyle: nsStyle).pointSize
        #else
        let uiStyle: UIFont.TextStyle
        switch self {
        case .largeTitle:  uiStyle = .largeTitle
        case .title:       uiStyle = .title1
        case .title2:      uiStyle = .title2
        case .title3:      uiStyle = .title3
        case .headline:    uiStyle = .headline
        case .subheadline: uiStyle = .subheadline
        case .callout:     uiStyle = .callout
        case .footnote:    uiStyle = .footnote
        case .caption:     uiStyle = .caption1
        case .caption2:    uiStyle = .caption2
        default:           uiStyle = .body
        }
        return UIFont.preferredFont(forTextStyle: uiStyle).pointSize
        #endif
    }
}

private struct ScaledRoundedFont: ViewModifier {
    @Environment(\.noteTextScale) private var scale
    let style: Font.TextStyle

    func body(content: Content) -> some View {
        content.font(.system(size: style.platformPointSize * scale, design: .rounded))
    }
}

extension View {
    /// A rounded font for `style`, scaled by the user's chosen text size.
    /// Use in place of `.font(.system(style, design: .rounded))` on content text.
    func scaledFont(_ style: Font.TextStyle) -> some View {
        modifier(ScaledRoundedFont(style: style))
    }

    /// Presents an alert whenever `message` is non-nil, so silent persistence
    /// failures surface to the user instead of quietly losing data.
    func saveErrorAlert(message: Binding<String?>) -> some View {
        alert(
            "Couldn't Save",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}


