import Foundation
import SwiftData
import SwiftUI

// MARK: - Persistence Diagnostic Tools

class PersistenceDiagnostic {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Database Health Check
    
    func runHealthCheck() -> PersistenceHealthReport {
        var report = PersistenceHealthReport()
        
        do {
            // Check Books
            let books = try modelContext.fetch(FetchDescriptor<Book>())
            report.bookCount = books.count
            report.booksWithIdeas = books.filter { !($0.ideas ?? []).isEmpty }.count
            
            // Check Ideas
            let ideas = try modelContext.fetch(FetchDescriptor<Idea>())
            report.ideaCount = ideas.count
            report.ideasWithValidIds = ideas.filter { $0.id.hasPrefix("b") }.count
            
            // Check Progress
            let progress = try modelContext.fetch(FetchDescriptor<Progress>())
            report.progressCount = progress.count
            
            // Check Primers
            let primers = try modelContext.fetch(FetchDescriptor<Primer>())
            report.primerCount = primers.count
            
            // Check for orphaned data
            let orphanedProgress = progress.filter { $0.idea == nil }
            report.orphanedProgressCount = orphanedProgress.count
            
            // Overall health
            report.isHealthy = report.orphanedProgressCount == 0
            
            print("📊 PERSISTENCE HEALTH REPORT:")
            print("   Books: \(report.bookCount) (\(report.booksWithIdeas) with ideas)")
            print("   Ideas: \(report.ideaCount) (\(report.ideasWithValidIds) with valid IDs)")
            print("   Progress: \(report.progressCount)")
            print("   Primers: \(report.primerCount)")
            print("   Orphaned Progress: \(report.orphanedProgressCount)")
            print("   Overall Health: \(report.isHealthy ? "✅ HEALTHY" : "⚠️ NEEDS ATTENTION")")
            
        } catch {
            print("❌ Health check failed: \(error)")
            report.error = error.localizedDescription
        }
        
        return report
    }
    
    // MARK: - Data Integrity Repair
    
    func repairDataIntegrity() async throws {
        print("🔧 Starting data integrity repair...")
        
        // 1. Fix orphaned responses
        // Fix orphaned progress
        let orphanedProgress = try modelContext.fetch(FetchDescriptor<Progress>(
            predicate: #Predicate { $0.idea == nil }
        ))
        
        for progress in orphanedProgress {
            // Try to link to existing idea
            let progressIdeaId = progress.ideaId
            let ideaDescriptor = FetchDescriptor<Idea>(
                predicate: #Predicate<Idea> { idea in
                    idea.id == progressIdeaId
                }
            )
            
            if let idea = try modelContext.fetch(ideaDescriptor).first {
                progress.idea = idea
                if idea.progress == nil { idea.progress = [] }
                idea.progress?.append(progress)
                print("🔗 Linked orphaned progress to idea: \(idea.title)")
            } else {
                print("🗑️ Deleting orphaned progress for non-existent idea: \(progress.ideaId)")
                modelContext.delete(progress)
            }
        }
        
        // 3. Ensure all ideas have proper book relationships
        let ideas = try modelContext.fetch(FetchDescriptor<Idea>())
        for idea in ideas {
            if idea.book == nil {
                // Try to find the book based on bookTitle
                let ideaBookTitle = idea.bookTitle
                let bookDescriptor = FetchDescriptor<Book>(
                    predicate: #Predicate<Book> { book in
                        book.title.localizedStandardContains(ideaBookTitle)
                    }
                )
                
                if let book = try modelContext.fetch(bookDescriptor).first {
                    idea.book = book
                    if !(book.ideas ?? []).contains(idea) {
                        if book.ideas == nil { book.ideas = [] }
                        book.ideas?.append(idea)
                    }
                    print("🔗 Linked orphaned idea to book: \(book.title)")
                }
            }
        }
        
        try modelContext.save()
        print("✅ Data integrity repair completed")
    }
    
    // MARK: - Database Reset
    
    func resetDatabase() throws {
        print("🔄 Resetting database...")
        
        // Delete all data in correct order (relationships first)
        let progress = try modelContext.fetch(FetchDescriptor<Progress>())
        progress.forEach { modelContext.delete($0) }
        
        let primers = try modelContext.fetch(FetchDescriptor<Primer>())
        primers.forEach { modelContext.delete($0) }
        
        let ideas = try modelContext.fetch(FetchDescriptor<Idea>())
        ideas.forEach { modelContext.delete($0) }
        
        let books = try modelContext.fetch(FetchDescriptor<Book>())
        books.forEach { modelContext.delete($0) }
        
        try modelContext.save()
        print("✅ Database reset completed")
    }
}

// MARK: - Health Report Structure

struct PersistenceHealthReport {
    var bookCount: Int = 0
    var booksWithIdeas: Int = 0
    var ideaCount: Int = 0
    var ideasWithValidIds: Int = 0
    var progressCount: Int = 0
    var primerCount: Int = 0
    var orphanedProgressCount: Int = 0
    var isHealthy: Bool = false
    var error: String?
}

// MARK: - SwiftUI Debug View

struct PersistenceDebugView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var report: PersistenceHealthReport?
    @State private var isRunningRepair = false
    @State private var isResetting = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let report = report {
                    healthReportView(report)
                } else {
                    Button("Run Health Check") {
                        runHealthCheck()
                    }
                    .dsPrimaryButton()
                }
                
                if report?.isHealthy == false {
                    Button("Repair Data Integrity") {
                        repairData()
                    }
                    .dsSecondaryButton()
                    .disabled(isRunningRepair)
                }
                
                Button("Reset Database") {
                    resetDatabase()
                }
                .dsSecondaryButton()
                .foregroundStyle(DS.Colors.black)
                .disabled(isResetting)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Persistence Debug")
        }
    }
    
    private func healthReportView(_ report: PersistenceHealthReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Database Health Report")
                .font(.headline)
            
            Group {
                Text("Books: \(report.bookCount) (\(report.booksWithIdeas) with ideas)")
                Text("Ideas: \(report.ideaCount) (\(report.ideasWithValidIds) with valid IDs)")
                Text("Progress Records: \(report.progressCount)")
                Text("Primers: \(report.primerCount)")
                Text("Orphaned Progress: \(report.orphanedProgressCount)")
            }
            .font(.body)
            
            Text("Status: \(report.isHealthy ? "✅ Healthy" : "⚠️ Needs Attention")")
                .font(.headline)
                .foregroundStyle(report.isHealthy ? DS.Colors.black : DS.Colors.black)
        }
        .padding()
        .background(DS.Colors.gray100)
        .cornerRadius(8)
    }
    
    private func runHealthCheck() {
        let diagnostic = PersistenceDiagnostic(modelContext: modelContext)
        report = diagnostic.runHealthCheck()
    }
    
    private func repairData() {
        isRunningRepair = true
        Task {
            do {
                let diagnostic = PersistenceDiagnostic(modelContext: modelContext)
                try await diagnostic.repairDataIntegrity()
                await MainActor.run {
                    runHealthCheck()
                    isRunningRepair = false
                }
            } catch {
                print("Repair failed: \(error)")
                await MainActor.run {
                    isRunningRepair = false
                }
            }
        }
    }
    
    private func resetDatabase() {
        isResetting = true
        do {
            let diagnostic = PersistenceDiagnostic(modelContext: modelContext)
            try diagnostic.resetDatabase()
            runHealthCheck()
            isResetting = false
        } catch {
            print("Reset failed: \(error)")
            isResetting = false
        }
    }
}
