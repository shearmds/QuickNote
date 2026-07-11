import Foundation
import SwiftData

@Model
final class Note {
    var id: UUID = UUID()
    var content: String = ""
    var isArchived: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    init(content: String = "", isArchived: Bool = false) {
        self.id = UUID()
        self.content = content
        self.isArchived = isArchived
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
