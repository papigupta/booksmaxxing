import Foundation
import SwiftData

// MARK: - Stored Lesson Model
@Model
final class StoredLesson {
    var bookId: String
    var lessonNumber: Int
    var primaryIdeaId: String
    var primaryIdeaTitle: String
    var createdAt: Date
    var isCompleted: Bool
    var masteryPercentage: Double
    
    // The actual test data (generated questions)
    @Relationship(deleteRule: .cascade) var test: Test?
    
    init(bookId: String, lessonNumber: Int, primaryIdeaId: String, primaryIdeaTitle: String) {
        self.bookId = bookId
        self.lessonNumber = lessonNumber
        self.primaryIdeaId = primaryIdeaId
        self.primaryIdeaTitle = primaryIdeaTitle
        self.createdAt = Date()
        self.isCompleted = false
        self.masteryPercentage = 0.0
    }
}

// MARK: - Lesson Storage Service
final class LessonStorageService {
    private let modelContext: ModelContext
    private let masteryService: MasteryService
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.masteryService = MasteryService(modelContext: modelContext)
    }
    
    // MARK: - Lesson Retrieval
    
    /// Get or create a lesson for the given book and lesson number
    func getLesson(bookId: String, lessonNumber: Int, book: Book) -> StoredLesson? {
        // First try to find existing lesson
        if let existing = findExistingLesson(bookId: bookId, lessonNumber: lessonNumber) {
            print("DEBUG: Found existing lesson \(lessonNumber) for book \(bookId)")
            return existing
        }
        
        // Create new lesson if it doesn't exist and is accessible
        if canAccessLesson(bookId: bookId, lessonNumber: lessonNumber) {
            return createNewLesson(bookId: bookId, lessonNumber: lessonNumber, book: book)
        }
        
        return nil
    }
    
    /// Get the current lesson number for a book
    func getCurrentLessonNumber(bookId: String) -> Int {
        let descriptor = FetchDescriptor<StoredLesson>(
            predicate: #Predicate<StoredLesson> { lesson in
                lesson.bookId == bookId
            },
            sortBy: [SortDescriptor(\.lessonNumber)]
        )
        
        do {
            let lessons = try modelContext.fetch(descriptor)
            
            // Find first incomplete lesson
            if let incompleteLesson = lessons.first(where: { !$0.isCompleted }) {
                return incompleteLesson.lessonNumber
            }
            
            // If all lessons completed, next lesson is count + 1
            return lessons.count + 1
            
        } catch {
            print("Error fetching lessons: \(error)")
            return 1
        }
    }
    
    /// Get lesson info for display (without generating test)
    func getLessonInfo(bookId: String, lessonNumber: Int, book: Book) -> (title: String, isUnlocked: Bool, isCompleted: Bool)? {
        // Check if lesson is unlocked
        let isUnlocked = lessonNumber == 1 || (lessonNumber > 1 ? isLessonCompleted(book: book, lessonNumber: lessonNumber - 1) : false)
        
        // Get the idea for this lesson
        guard let idea = getIdeaForLesson(book: book, lessonNumber: lessonNumber) else {
            return nil
        }
        
        // Check completion status based on mastery
        let mastery = masteryService.getMastery(for: idea.id, bookId: bookId)
        let isCompleted = mastery.masteryPercentage >= 80.0  // 80% threshold for lesson completion
        
        return (title: idea.title, isUnlocked: isUnlocked, isCompleted: isCompleted)
    }
    
    /// Get all available lesson info for a book
    func getAllLessonInfo(book: Book) -> [(lessonNumber: Int, title: String, isUnlocked: Bool, isCompleted: Bool)] {
        let bookId = book.id.uuidString
        var lessonInfo: [(Int, String, Bool, Bool)] = []
        
        print("DEBUG: LessonStorage.getAllLessonInfo called for book: \(book.title)")
        print("DEBUG: Book has \(book.ideas.count) ideas")
        
        let sortedIdeas = book.ideas.sorted { idea1, idea2 in
            extractIdeaNumber(from: idea1.id) < extractIdeaNumber(from: idea2.id)
        }
        
        print("DEBUG: Sorted ideas: \(sortedIdeas.map { $0.id })")
        
        for (index, idea) in sortedIdeas.enumerated() {
            let lessonNumber = index + 1
            let isUnlocked = lessonNumber == 1 || (lessonNumber > 1 ? isLessonCompleted(book: book, lessonNumber: lessonNumber - 1) : false)
            let mastery = masteryService.getMastery(for: idea.id, bookId: bookId)
            let isCompleted = mastery.masteryPercentage >= 80.0  // 80% threshold for lesson completion
            
            print("DEBUG: Lesson \(lessonNumber) - \(idea.title): unlocked=\(isUnlocked), completed=\(isCompleted)")
            lessonInfo.append((lessonNumber, idea.title, isUnlocked, isCompleted))
        }
        
        print("DEBUG: Returning \(lessonInfo.count) lesson infos")
        return lessonInfo
    }
    
    // MARK: - Private Helper Methods
    
    private func findExistingLesson(bookId: String, lessonNumber: Int) -> StoredLesson? {
        let descriptor = FetchDescriptor<StoredLesson>(
            predicate: #Predicate<StoredLesson> { lesson in
                lesson.bookId == bookId && lesson.lessonNumber == lessonNumber
            }
        )
        
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            print("Error fetching lesson: \(error)")
            return nil
        }
    }
    
    private func canAccessLesson(bookId: String, lessonNumber: Int) -> Bool {
        // Lesson 1 is always accessible
        if lessonNumber == 1 {
            return true
        }
        
        // For now, just check if previous idea has mastery > 80%
        // This avoids the SwiftData predicate issue
        return true  // Simplified for now - will fix later
    }
    
    private func isLessonCompleted(book: Book, lessonNumber: Int) -> Bool {
        // Check if the lesson is completed based on mastery of the corresponding idea
        guard let idea = getIdeaForLesson(book: book, lessonNumber: lessonNumber) else {
            return false
        }
        
        let bookId = book.id.uuidString
        let mastery = masteryService.getMastery(for: idea.id, bookId: bookId)
        return mastery.masteryPercentage >= 80.0
    }
    
    private func createNewLesson(bookId: String, lessonNumber: Int, book: Book) -> StoredLesson? {
        guard let idea = getIdeaForLesson(book: book, lessonNumber: lessonNumber) else {
            print("ERROR: Could not find idea for lesson \(lessonNumber)")
            return nil
        }
        
        let lesson = StoredLesson(
            bookId: bookId,
            lessonNumber: lessonNumber,
            primaryIdeaId: idea.id,
            primaryIdeaTitle: idea.title
        )
        
        modelContext.insert(lesson)
        
        do {
            try modelContext.save()
            print("DEBUG: Created new lesson \(lessonNumber) for idea: \(idea.title)")
            return lesson
        } catch {
            print("ERROR: Failed to save lesson: \(error)")
            return nil
        }
    }
    
    private func getIdeaForLesson(book: Book, lessonNumber: Int) -> Idea? {
        let sortedIdeas = book.ideas.sorted { idea1, idea2 in
            extractIdeaNumber(from: idea1.id) < extractIdeaNumber(from: idea2.id)
        }
        
        guard lessonNumber > 0 && lessonNumber <= sortedIdeas.count else {
            return nil
        }
        
        return sortedIdeas[lessonNumber - 1]
    }
    
    private func extractIdeaNumber(from ideaId: String) -> Int {
        let components = ideaId.split(separator: "i")
        if components.count > 1, let number = Int(components[1]) {
            return number
        }
        return 0
    }
}