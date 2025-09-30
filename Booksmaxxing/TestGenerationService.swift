import Foundation
import SwiftData
import OSLog

// MARK: - Test Generation Service

@MainActor
class TestGenerationService {
    private let logger = Logger(subsystem: "com.booksmaxxing.app", category: "TestGeneration")
    // Helper function to randomize options and update correct answer index
    private func randomizeOptions(_ options: [String], correctIndices: [Int]) -> (options: [String], correctIndices: [Int]) {
        // Create array of indices paired with options
        let indexedOptions = Array(options.enumerated())
        
        // Shuffle the indexed options
        let shuffled = indexedOptions.shuffled()
        
        // Extract the new options order
        let newOptions = shuffled.map { $0.element }
        
        // Map old correct indices to new positions
        let newCorrectIndices = correctIndices.map { oldIndex in
            shuffled.firstIndex(where: { $0.offset == oldIndex }) ?? 0
        }
        
        return (newOptions, newCorrectIndices)
    }

    // Normalize MCQ option verbosity: keep options parallel and similar length
    // If disparity is high, ask the model to rewrite options concisely while preserving order and correctness.
    private func normalizeOptionLengthsIfNeeded(options: [String], correctIndex: Int, difficulty: QuestionDifficulty, contextQuestion: String) async -> [String] {
        // Heuristics for disparity thresholds by difficulty
        let lengths = options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).count }
        guard let maxLen = lengths.max(), let minLen = lengths.min() else { return options }
        let avg = max(1, lengths.reduce(0, +) / max(1, lengths.count))
        let ratio = Double(maxLen) / Double(max(minLen, 1))

        let absGapThreshold: Int
        switch difficulty {
        case .easy:   absGapThreshold = 25
        case .medium: absGapThreshold = 35
        case .hard:   absGapThreshold = 45
        }

        let isCorrectLongest = lengths.enumerated().max(by: { $0.element < $1.element })?.offset == correctIndex
        let hasLargeGap = (maxLen - minLen) > absGapThreshold || Double(maxLen) > Double(avg) * 1.35 || ratio > 1.6
        guard hasLargeGap || isCorrectLongest else { return options }

        // Target word ranges by difficulty to keep options concise and comparable.
        let wordRange: String
        switch difficulty {
        case .easy:   wordRange = "6-10"
        case .medium: wordRange = "8-14"
        case .hard:   wordRange = "10-16"
        }

        let optionsJSON = options.enumerated().map { "\"\($0.offset)\": \"\($0.element.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ", ")
        let systemPrompt = """
        You are a precise exam editor. Rewrite four multiple-choice options to be parallel, concise, and of similar length.
        Maintain the same order and keep the same option as correct. Do not change meanings.
        Constraints:
        - Target \(wordRange) words per option
        - No added hedges or caveats unless mirrored across options
        - Keep order fixed; do NOT reorder
        - Preserve the correct option semantically
        Output ONLY JSON: { "options": ["...","...","...","..."] }
        """

        let userPrompt = """
        Question: \(contextQuestion)
        Current options (by index): { \(optionsJSON) }
        Correct index: \(correctIndex)
        Rewrite to meet the constraints while preserving correctness and order.
        """

        do {
            let response = try await openAI.chat(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                model: "gpt-4.1-mini",
                temperature: 0.2,
                maxTokens: 220
            )
            if let data = response.data(using: .utf8),
               let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rewritten = json["options"] as? [String], rewritten.count == 4 {
                // Quick sanity: keep them non-empty and not duplicates
                let trimmed = rewritten.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                let unique = Set(trimmed.map { $0.lowercased() })
                if trimmed.allSatisfy({ !$0.isEmpty }) && unique.count == 4 {
                    logger.debug("Normalized MCQ option lengths via rewrite")
                    return trimmed
                }
            }
        } catch {
            logger.debug("Option normalization skipped due to error: \(error.localizedDescription)")
        }
        return options
    }
    
    private let openAI: OpenAIService
    private let modelContext: ModelContext
    
    init(openAI: OpenAIService, modelContext: ModelContext) {
        self.openAI = openAI
        self.modelContext = modelContext
    }
    
    // MARK: - Test Retrieval
    
    func getTest(for idea: Idea, testType: String = "initial") -> Test? {
        let ideaId = idea.id
        let descriptor = FetchDescriptor<Test>(
            predicate: #Predicate<Test> { test in
                test.ideaId == ideaId && test.testType == testType
            }
        )
        
        do {
            let tests = try modelContext.fetch(descriptor)
            // Return the most recent test for this idea and type
            let sorted = tests.sorted { $0.createdAt > $1.createdAt }
            if let candidate = sorted.first {
                let minCount = (testType == "review") ? 1 : 8
                let qs = candidate.questions ?? []
                let hasMin = qs.count >= minCount
                let hasValidOptions = isValid(candidate)
                if hasMin && hasValidOptions {
                    return candidate
                }
                // Delete incomplete/invalid test to avoid getting stuck with partial/migrated data
                logger.debug("Discarding invalid existing test (count=\(qs.count), validOptions=\(hasValidOptions)) ; regenerating…")
                modelContext.delete(candidate)
                try? modelContext.save()
            }
            return nil
        } catch {
            logger.error("Error fetching test: \(String(describing: error))")
            return nil
        }
    }

    // MARK: - Validation Helpers
    func isValid(_ test: Test) -> Bool {
        let qs = test.questions ?? []
        return qs.allSatisfy { q in
            switch q.type {
            case .openEnded:
                return true
            case .mcq, .msq:
                guard let opts = q.options, let correct = q.correctAnswers else { return false }
                return opts.count == 4 && !correct.isEmpty
            }
        }
    }
    
    func ensureValidTest(for idea: Idea, testType: String = "initial") async throws -> Test {
        if let existing = getTest(for: idea, testType: testType), isValid(existing) {
            return existing
        }
        return try await generateTest(for: idea, testType: testType)
    }
    
    // MARK: - Main Test Generation
    
    func generateTest(for idea: Idea, testType: String = "initial", previousMistakes: [QuestionResponse]? = nil) async throws -> Test {
        logger.debug("Checking for existing \(testType, privacy: .public) test for idea: \(idea.title, privacy: .public)")
        
        // Check if test already exists
        if let existingTest = getTest(for: idea, testType: testType) {
            logger.debug("Found existing test with \((existingTest.questions ?? []).count) questions, created at \(existingTest.createdAt, privacy: .public)")
            
            // Log the order of questions in the existing test
            logger.debug("Existing test question order:")
            for (index, q) in existingTest.orderedQuestions.enumerated() {
                logger.debug("  Q\(index + 1): \(q.bloomCategory.rawValue) - \(q.type.rawValue) - orderIndex: \(q.orderIndex)")
            }
            
            return existingTest
        }
        
        logger.debug("No existing test found, generating new \(testType, privacy: .public) test for idea: \(idea.title, privacy: .public)")
        
        // Create test container
        let test = Test(
            ideaId: idea.id,
            ideaTitle: idea.title,
            bookTitle: idea.bookTitle,
            testType: testType
        )
        
        // Generate questions based on test type
        let questions: [Question]
        if testType == "review" && previousMistakes != nil {
            questions = try await generateReviewQuestions(for: idea, mistakes: previousMistakes!)
        } else {
            questions = try await generateInitialQuestions(for: idea)
        }
        
        // Add questions to test (ensure they're sorted by orderIndex)
        test.questions = questions.sorted { $0.orderIndex < $1.orderIndex }
        questions.forEach { $0.test = test }
        
        // Save to database
        modelContext.insert(test)
        try modelContext.save()
        
        return test
    }
    
    // MARK: - Refresh Test (Force Regeneration)
    
    func refreshTest(for idea: Idea, testType: String = "initial") async throws -> Test {
        logger.debug("Refreshing \(testType, privacy: .public) test for idea: \(idea.title, privacy: .public)")
        
        // Delete existing test if it exists
        if let existingTest = getTest(for: idea, testType: testType) {
            logger.debug("Deleting existing test created at \(existingTest.createdAt, privacy: .public)")
            modelContext.delete(existingTest)
            try modelContext.save()
        }
        
        // Generate new test (will not find existing one since we just deleted it)
        return try await generateTest(for: idea, testType: testType)
    }
    
    // MARK: - Retry Test Generation (focused on incorrect answers)
    
    func generateRetryTest(for idea: Idea, incorrectResponses: [QuestionResponse]) async throws -> Test {
        logger.debug("Generating retry test for idea: \(idea.title, privacy: .public) with \(incorrectResponses.count) incorrect responses")
        
        // Create retry test container
        let test = Test(
            ideaId: idea.id,
            ideaTitle: idea.title,
            bookTitle: idea.bookTitle,
            testType: "retry"
        )
        
        var questions: [Question] = []
        var orderIndex = 0
        
        // Generate new questions targeting the same concepts that were missed
        for incorrectResponse in incorrectResponses {
            guard let originalQuestion = incorrectResponse.question else { continue }
            
            // Generate a new question of the same type/difficulty/bloom category but different content
            let newQuestion = try await generateQuestion(
                for: idea,
                type: originalQuestion.type,
                difficulty: originalQuestion.difficulty,
                bloomCategory: originalQuestion.bloomCategory,
                orderIndex: orderIndex,
                isReview: true
            )
            
            questions.append(newQuestion)
            orderIndex += 1
        }
        
        // Add questions to test (ensure they're sorted by orderIndex)
        test.questions = questions.sorted { $0.orderIndex < $1.orderIndex }
        questions.forEach { $0.test = test }
        
        // Save to database
        modelContext.insert(test)
        try modelContext.save()
        
        return test
    }
    
    // MARK: - Initial Test Generation (8 questions)

    // Batched generation: single call for 8 items with strict validation and fallback
    // legacy single-call batched initial generation removed

    // Per-difficulty batched generation: 3 calls (Easy: 0-1, Medium: 2-5, Hard: 6-7)
    private func generateInitialQuestionsPerDifficultyBatched(for idea: Idea) async throws -> [Question] {
        let start = Date()
        logger.debug("DIFF-BATCH: Starting per-difficulty batched generation for idea: \(idea.title, privacy: .public)")

        struct BatchedItem: Decodable {
            let orderIndex: Int
            let type: String
            let bloom: String
            let difficulty: String
            let question: String
            let options: [String]?
            let correct: [Int]?
        }

        // Helper: mapping per slot using existing fixed config
        func specForSlot(_ i: Int) -> (type: String, bloom: String, difficulty: String) {
            let (bloom, diff, qType) = self.getQuestionConfigForSlot(i)
            let t = (qType == .openEnded) ? "OpenEnded" : "MCQ"
            return (t, bloom.rawValue, diff.rawValue)
        }

        // Helper: normalize/validate an array of BatchedItem for a given index set
        func processBatch(_ items: [BatchedItem], expectedIndices: [Int]) async throws -> [Question] {
            // Basic checks
            let idxSet = Set(items.map { $0.orderIndex })
            guard idxSet == Set(expectedIndices) else {
                throw TestGenerationError.generationFailed("DIFF-BATCH: indices mismatch; expected \(expectedIndices), got \(Array(idxSet).sorted())")
            }

            // Build mapping
            var byIndex: [Int: BatchedItem] = [:]
            for item in items { byIndex[item.orderIndex] = item }

            // Validators reused
            func norm(_ s: String) -> String {
                return s.lowercased()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
            }
            let disallowed = Set(["all of the above", "none of the above", "both a and b", "neither of the above"]) 

            var out: [Question] = []
            for i in expectedIndices.sorted() {
                guard let item = byIndex[i] else { continue }
                let expected = specForSlot(i)
                guard item.type == expected.type && item.bloom == expected.bloom && item.difficulty == expected.difficulty else {
                    throw TestGenerationError.generationFailed("DIFF-BATCH: Slot \(i) spec mismatch")
                }
                guard !item.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw TestGenerationError.generationFailed("DIFF-BATCH: Slot \(i) empty question")
                }
                if expected.type == "MCQ" {
                    guard let options = item.options, let correct = item.correct, options.count == 4, correct.count == 1 else {
                        throw TestGenerationError.generationFailed("DIFF-BATCH: Slot \(i) MCQ shape invalid")
                    }
                    let normalized = options.map { norm($0) }
                    if Set(normalized).count != 4 { throw TestGenerationError.generationFailed("DIFF-BATCH: Slot \(i) duplicate options") }
                    if normalized.contains(where: { disallowed.contains($0) }) { throw TestGenerationError.generationFailed("DIFF-BATCH: Slot \(i) disallowed option") }
                    if !(0...3).contains(correct[0]) { throw TestGenerationError.generationFailed("DIFF-BATCH: Slot \(i) correct index out of range") }
                } else {
                    if item.options != nil || item.correct != nil {
                        throw TestGenerationError.generationFailed("DIFF-BATCH: Slot \(i) OpenEnded must not include options/correct")
                    }
                }

                // Build Question with shuffle and normalization if MCQ
                let type: QuestionType = (item.type == "OpenEnded") ? .openEnded : .mcq
                guard let bloom = BloomCategory(rawValue: item.bloom), let difficulty = QuestionDifficulty(rawValue: item.difficulty) else {
                    throw TestGenerationError.generationFailed("DIFF-BATCH: Slot \(i) unknown enums")
                }
                var options: [String]? = item.options
                var correct: [Int]? = item.correct
                if type != .openEnded, let opts = options, let corr = correct {
                    let (shuffled, newIdx) = self.randomizeOptions(opts, correctIndices: corr)
                    let normalized = await self.normalizeOptionLengthsIfNeeded(options: shuffled, correctIndex: newIdx.first ?? 0, difficulty: difficulty, contextQuestion: item.question)
                    options = normalized
                    correct = newIdx
                }
                if type == .openEnded && bloom == .howWield {
                    self.logger.debug("DIFF-BATCH->Q8: Replacing batched HowWield with situational generator at index \(i)")
                    let q8 = try await self.generateQuestion(
                        for: idea,
                        type: .openEnded,
                        difficulty: difficulty,
                        bloomCategory: .howWield,
                        orderIndex: i
                    )
                    out.append(q8)
                } else {
                    let finalQuestionText = (type == .openEnded && bloom == .reframe) ? "In your own words, explain '\(idea.title)' as if you were telling a friend." : item.question
                    out.append(Question(
                        ideaId: idea.id,
                        type: type,
                        difficulty: difficulty,
                        bloomCategory: bloom,
                        questionText: finalQuestionText,
                        options: options,
                        correctAnswers: correct,
                        orderIndex: i
                    ))
                }
            }
            return out
        }

        // Build shared schema text (same as single-batch path)
        let schemaText = """
        Strictly follow this JSON schema and rules:
        {
          "questions": [
            {
              "orderIndex": 0..7,
              "type": "MCQ" | "OpenEnded",
              "bloom": "Recall|Apply|WhyImportant|WhenUse|Contrast|Reframe|Critique|HowWield",
              "difficulty": "Easy|Medium|Hard",
              "question": "string",
              "options": ["A","B","C","D"],
              "correct": [0]
            }
          ]
        }
        Rules:
        - MCQ must have exactly 4 options and a single correct index (0-3).
        - OpenEnded must omit options and correct.
        - Avoid phrases like "all of the above".
        - Make MCQ options similar length (±20% of average) and parallel; do not reveal correctness via verbosity.
        Output only JSON. No prose.
        """

        func systemPrompt(forDifficulty label: String) -> String {
            switch label {
            case "Easy":
                return """
                You are an expert educational content creator.
                Create high-quality EASY questions for a non-fiction book idea.
                Emphasize clarity, concrete wording, and straightforward stems.
                MCQ options must be concise, plausible, and parallel; avoid trickiness.
                Language: precise, no chain-of-thought or explanations.
                Output only a valid JSON object per schema (no prose before/after).
                """
            case "Medium":
                return """
                You are an expert educational content creator.
                Create high-quality MEDIUM questions for a non-fiction book idea.
                Aim for moderate depth (why/when/contrast/reframe) with realistic scenarios.
                MCQ options should reflect common misconceptions; keep options parallel and concise.
                Special case: if a slot is type=OpenEnded and bloom=Reframe, write a single, one‑sentence prompt that simply invites the learner to restate the idea "in your own words" — no lists, hints, or evaluation criteria.
                Language: precise, no chain-of-thought or explanations.
                Output only a valid JSON object per schema (no prose before/after).
                """
            default: // Hard
                return """
                You are an expert educational content creator.
                Create high-quality HARD questions for a non-fiction book idea.
                Target critique/contrast/how-wield; focus on conceptual precision and subtle distinctions.
                MCQ options must be carefully balanced, parallel, and not misleading.
                Language: precise, no chain-of-thought or explanations.
                Output only a valid JSON object per schema (no prose before/after).
                """
            }
        }

        func userPrompt(for idea: Idea, indices: [Int]) -> String {
            var specLines: [String] = []
            for idx in indices.sorted() {
                let s = specForSlot(idx)
                specLines.append("- orderIndex=\(idx), type=\(s.type), bloom=\(s.bloom), difficulty=\(s.difficulty)")
            }
            return """
            Idea title: \(idea.title)
            Idea description: \(idea.ideaDescription)
            Book: \(idea.bookTitle)

            Create the questions in this exact distribution and order:\n\(specLines.joined(separator: "\n"))

            \(schemaText)
            """
        }

        // Difficulty groups and params
        let easyIdx = [0, 1]
        let medIdx = [2, 3, 4, 5]
        let hardIdx = [6, 7]

        // Model params per difficulty
        struct GenParams { let temperature: Double; let maxTokens: Int }
        let easyParams = GenParams(temperature: 0.6, maxTokens: 350)
        let medParams  = GenParams(temperature: 0.7, maxTokens: 900)
        let hardParams = GenParams(temperature: 0.75, maxTokens: 500)

        // Perform the three calls (possibly in parallel)
        let easyCall = { () async throws -> [BatchedItem] in
            let resp = try await self.openAI.chat(
                systemPrompt: systemPrompt(forDifficulty: "Easy"),
                userPrompt: userPrompt(for: idea, indices: easyIdx),
                model: "gpt-4.1",
                temperature: easyParams.temperature,
                maxTokens: easyParams.maxTokens
            )
            let json = SharedUtils.extractJSONObjectString(resp)
            struct Wrap: Decodable { let questions: [BatchedItem] }
            guard let d = json.data(using: .utf8) else { throw TestGenerationError.generationFailed("DIFF-BATCH: Easy invalid JSON string") }
            let decoded = try JSONDecoder().decode(Wrap.self, from: d)
            return decoded.questions
        }
        let medCall = { () async throws -> [BatchedItem] in
            let resp = try await self.openAI.chat(
                systemPrompt: systemPrompt(forDifficulty: "Medium"),
                userPrompt: userPrompt(for: idea, indices: medIdx),
                model: "gpt-4.1",
                temperature: medParams.temperature,
                maxTokens: medParams.maxTokens
            )
            let json = SharedUtils.extractJSONObjectString(resp)
            struct Wrap: Decodable { let questions: [BatchedItem] }
            guard let d = json.data(using: .utf8) else { throw TestGenerationError.generationFailed("DIFF-BATCH: Medium invalid JSON string") }
            let decoded = try JSONDecoder().decode(Wrap.self, from: d)
            return decoded.questions
        }
        let hardCall = { () async throws -> [BatchedItem] in
            let resp = try await self.openAI.chat(
                systemPrompt: systemPrompt(forDifficulty: "Hard"),
                userPrompt: userPrompt(for: idea, indices: hardIdx),
                model: "gpt-4.1",
                temperature: hardParams.temperature,
                maxTokens: hardParams.maxTokens
            )
            let json = SharedUtils.extractJSONObjectString(resp)
            struct Wrap: Decodable { let questions: [BatchedItem] }
            guard let d = json.data(using: .utf8) else { throw TestGenerationError.generationFailed("DIFF-BATCH: Hard invalid JSON string") }
            let decoded = try JSONDecoder().decode(Wrap.self, from: d)
            return decoded.questions
        }

        // Execute sequentially; parallelism enabled by connection cap + potential async grouping if needed
        // Here we use async let to allow true concurrency when HTTP pool allows >1.
        async let e = easyCall()
        async let m = medCall()
        async let h = hardCall()

        var easyItems: [BatchedItem] = []
        var medItems: [BatchedItem] = []
        var hardItems: [BatchedItem] = []
        do {
            (easyItems, medItems, hardItems) = try await (e, m, h)
        } catch {
            logger.debug("DIFF-BATCH: One or more difficulty calls failed; attempting partial fallbacks")
            // Try each independently, falling back to per-question for failed ones
            // Easy
            if easyItems.isEmpty {
                do { easyItems = try await e } catch { logger.debug("DIFF-BATCH: Easy retry failed; will fallback per-question") }
            }
            // Medium
            if medItems.isEmpty {
                do { medItems = try await m } catch { logger.debug("DIFF-BATCH: Medium retry failed; will fallback per-question") }
            }
            // Hard
            if hardItems.isEmpty {
                do { hardItems = try await h } catch { logger.debug("DIFF-BATCH: Hard retry failed; will fallback per-question") }
            }
        }

        // Process batches into Questions; fallback missing slots to legacy per-question generation
        var out: [Question] = []
        var haveEasy = false, haveMed = false, haveHard = false
        do {
            let qs = try await processBatch(easyItems, expectedIndices: easyIdx)
            out.append(contentsOf: qs)
            haveEasy = true
        } catch {
            logger.debug("DIFF-BATCH: Easy batch invalid; falling back to per-question for slots 0-1")
            for i in easyIdx { let (b, d, t) = getQuestionConfigForSlot(i); let q = try await generateQuestion(for: idea, type: t, difficulty: d, bloomCategory: b, orderIndex: i); out.append(q) }
        }
        do {
            let qs = try await processBatch(medItems, expectedIndices: medIdx)
            out.append(contentsOf: qs)
            haveMed = true
        } catch {
            logger.debug("DIFF-BATCH: Medium batch invalid; falling back to per-question for slots 2-5")
            for i in medIdx { let (b, d, t) = getQuestionConfigForSlot(i); let q = try await generateQuestion(for: idea, type: t, difficulty: d, bloomCategory: b, orderIndex: i); out.append(q) }
        }
        do {
            let qs = try await processBatch(hardItems, expectedIndices: hardIdx)
            out.append(contentsOf: qs)
            haveHard = true
        } catch {
            logger.debug("DIFF-BATCH: Hard batch invalid; falling back to per-question for slots 6-7")
            for i in hardIdx { let (b, d, t) = getQuestionConfigForSlot(i); let q = try await generateQuestion(for: idea, type: t, difficulty: d, bloomCategory: b, orderIndex: i); out.append(q) }
        }

        let elapsed = Date().timeIntervalSince(start)
        logger.debug("DIFF-BATCH: Completed per-difficulty batches (E=\(haveEasy) M=\(haveMed) H=\(haveHard)) in \(String(format: "%.2f", elapsed))s")
        return out.sorted { $0.orderIndex < $1.orderIndex }
    }

    private func generateInitialQuestions(for idea: Idea) async throws -> [Question] {
        logger.debug("GEN-PATH: Flags — per-difficulty=\(DebugFlags.usePerDifficultyBatchedInitialGeneration, privacy: .public), single-call removed=true")
        // Try per-difficulty batched path first when flag is enabled
        if DebugFlags.usePerDifficultyBatchedInitialGeneration {
            do {
                let split = try await generateInitialQuestionsPerDifficultyBatched(for: idea)
                if let q8 = split.first(where: { $0.orderIndex == 7 }) {
                    let hasInline = q8.howWieldInlineCard != nil || q8.howWieldPayload != nil
                    logger.debug("Q8 summary — category=\(q8.bloomCategory.rawValue, privacy: .public), hasHWFields=\(hasInline, privacy: .public), text='\(q8.questionText.prefix(120))…'")
                    if let hw = q8.howWieldInlineCard {
                        logger.debug("Q8 Inline — role='\(hw.role, privacy: .public)', goal='\(hw.goal, privacy: .public)', time='\(hw.timebox, privacy: .public)', dataCount=\(hw.data.count, privacy: .public)")
                    }
                }
                return split
            } catch {
                logger.debug("DIFF-BATCH: Falling back due to: \(error.localizedDescription)")
            }
        }

        // Single-call batched path removed
        var questions: [Question] = []
        
        // Fixed order with specific question types and difficulties:
        // Q1: Recall (Easy, MCQ)
        // Q2: Apply (Easy, MCQ)  
        // Q3: WhyImportant (Medium, MCQ)
        // Q4: WhenUse (Medium, MCQ)
        // Q5: Contrast (Medium, MCQ)
        // Q6: Reframe (Medium, Open-ended)
        // Q7: Critique (Hard, MCQ)
        // Q8: HowWield (Hard, Open-ended)
        
        let categoryDistribution: [(BloomCategory, QuestionDifficulty, QuestionType)] = [
            (.recall, .easy, .mcq),           // Q1
            (.apply, .easy, .mcq),            // Q2
            (.whyImportant, .medium, .mcq),   // Q3
            (.whenUse, .medium, .mcq),        // Q4
            (.contrast, .medium, .mcq),       // Q5
            (.reframe, .medium, .openEnded),  // Q6 - Open-ended for reframing
            (.critique, .hard, .mcq),         // Q7
            (.howWield, .hard, .openEnded)    // Q8 - Open-ended for how to wield
        ]
        
        // Generate questions in the fixed order
        for (index, (category, difficulty, type)) in categoryDistribution.enumerated() {
            let question = try await generateQuestion(
                for: idea,
                type: type,
                difficulty: difficulty,
                bloomCategory: category,
                orderIndex: index
            )
            questions.append(question)
            logger.debug("Generated Q\(index + 1): \(category.rawValue) - \(type.rawValue) - orderIndex: \(index)")
        }
        
        // Verify order before returning
        logger.debug("Final question order:")
        for (index, q) in questions.enumerated() {
            logger.debug("  Q\(index + 1): \(q.bloomCategory.rawValue) - \(q.type.rawValue) - orderIndex: \(q.orderIndex)")
        }
        if let q8 = questions.first(where: { $0.orderIndex == 7 }) {
            let hasInline = q8.howWieldInlineCard != nil || q8.howWieldPayload != nil
            logger.debug("Q8 summary — category=\(q8.bloomCategory.rawValue, privacy: .public), hasHWFields=\(hasInline, privacy: .public), text='\(q8.questionText.prefix(120))…'")
            if let hw = q8.howWieldInlineCard {
                logger.debug("Q8 Inline — role='\(hw.role, privacy: .public)', goal='\(hw.goal, privacy: .public)', time='\(hw.timebox, privacy: .public)', dataCount=\(hw.data.count, privacy: .public)")
            }
        }
        
        return questions
    }
    
    // MARK: - Review Question Generation from Queue
    
    func generateReviewQuestionsFromQueue(_ queueItems: [ReviewQueueItem]) async throws -> [Question] {
        var questions: [Question] = []
        var orderIndex = 0
        
        for item in queueItems {
            // Curveball path: always generate an open-ended retrieval prompt via LLM
            if item.isCurveball {
                let question = try await generateCurveballQuestion(
                    from: item,
                    orderIndex: orderIndex
                )
                questions.append(question)
                orderIndex += 1
                continue
            }

            // Spaced follow-up path: open-ended retrieval prompt with stored bloom/difficulty
            if item.isSpacedFollowUp {
                let question = try await generateSpacedFollowUpQuestion(from: item, orderIndex: orderIndex)
                questions.append(question)
                orderIndex += 1
                continue
            }

            // Generate a similar question testing the same concept for non-curveball items
            let question = try await generateSimilarQuestion(
                from: item,
                orderIndex: orderIndex
            )
            questions.append(question)
            orderIndex += 1
        }
        
        return questions
    }

    private func generateSpacedFollowUpQuestion(from queueItem: ReviewQueueItem, orderIndex: Int) async throws -> Question {
        let targetIdeaId = queueItem.ideaId
        let descriptor = FetchDescriptor<Idea>(
            predicate: #Predicate<Idea> { idea in
                idea.id == targetIdeaId
            }
        )
        guard let idea = try modelContext.fetch(descriptor).first else {
            throw TestGenerationError.generationFailed("Idea not found")
        }

        // Use situational HowWield for review-time if category is HowWield
        if queueItem.bloomCategory == .howWield {
            return try await generateHowWieldQuestion(for: idea, difficulty: queueItem.difficulty, orderIndex: orderIndex)
        }

        // Short, invitational retrieval prompt (same style family as curveball but per stored bloom)
        let systemPrompt = """
        You are a learning‑science coach. Write a single open‑ended retrieval prompt for the learner about the idea titled '\(idea.title)'.
        Requirements:
        - 1–2 sentences maximum
        - Warm, invitational tone
        - Explicitly include the phrases "from memory" and "in your own words"
        - Keep focus aligned with Bloom: \(queueItem.bloomCategory.rawValue)
        - Do NOT enumerate lists, angles, or sub‑questions
        - Do NOT reveal definitions, examples, or hints in the prompt
        Output ONLY a JSON object: { "question": "..." }
        """

        let shortDesc: String = {
            let text = idea.ideaDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.count <= 220 { return text }
            let idx = text.index(text.startIndex, offsetBy: 220)
            return String(text[..<idx]) + "…"
        }()
        let userPrompt = """
        Idea title: \(idea.title)
        Optional context for the model (do not include in the prompt): \(shortDesc)
        Generate the prompt.
        """

        let response = try await openAI.complete(
            prompt: "\(systemPrompt)\n\n\(userPrompt)",
            model: "gpt-4.1",
            temperature: 0.6,
            maxTokens: 200
        )
        let (questionText, _, _) = try parseQuestionResponse(response, type: .openEnded)

        return Question(
            ideaId: queueItem.ideaId,
            type: .openEnded,
            difficulty: queueItem.difficulty,
            bloomCategory: queueItem.bloomCategory,
            questionText: questionText,
            options: nil,
            correctAnswers: nil,
            orderIndex: orderIndex,
            isCurveball: false,
            isSpacedFollowUp: true,
            sourceQueueItemId: queueItem.id
        )
    }

    private func generateCurveballQuestion(from queueItem: ReviewQueueItem, orderIndex: Int) async throws -> Question {
        // Fetch the idea for context
        let targetIdeaId = queueItem.ideaId
        let descriptor = FetchDescriptor<Idea>(
            predicate: #Predicate<Idea> { idea in
                idea.id == targetIdeaId
            }
        )
        
        guard let idea = try modelContext.fetch(descriptor).first else {
            throw TestGenerationError.generationFailed("Idea not found")
        }
        
        // System prompt: craft a single warm retrieval invitation
        let systemPrompt = """
        You are a learning‑science coach. Write a single open‑ended retrieval prompt for the learner about the idea titled '\(idea.title)'.
        Requirements:
        - 1–2 sentences maximum
        - Warm, invitational tone
        - Explicitly include the phrases "from memory" and "in your own words"
        - Gently nudge depth (e.g., "follow your train of thought" or "go as deep as you can")
        - Do NOT enumerate lists, angles, or sub‑questions
        - Do NOT reveal definitions, examples, or hints in the prompt
        - Avoid multi‑part questions and avoid bullet points
        Output ONLY a JSON object: { "question": "..." }
        """
        
        // User prompt: provide minimal context; do not echo it into the prompt
        let shortDesc: String = {
            let text = idea.ideaDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.count <= 220 { return text }
            let idx = text.index(text.startIndex, offsetBy: 220)
            return String(text[..<idx]) + "…"
        }()
        let userPrompt = """
        Idea title: \(idea.title)
        Optional context for the model (do not include in the prompt): \(shortDesc)
        Generate the prompt.
        """
        
        let response = try await openAI.complete(
            prompt: "\(systemPrompt)\n\n\(userPrompt)",
            model: "gpt-4.1",
            temperature: 0.6,
            maxTokens: 200
        )
        
        // Parse minimal JSON containing just the question text
        let (questionText, _, _) = try parseQuestionResponse(response, type: .openEnded)
        
        return Question(
            ideaId: queueItem.ideaId,
            type: .openEnded,
            difficulty: .hard,
            bloomCategory: .reframe,
            questionText: questionText,
            options: nil,
            correctAnswers: nil,
            orderIndex: orderIndex,
            isCurveball: true,
            sourceQueueItemId: queueItem.id
        )
    }
    
    private func generateSimilarQuestion(from queueItem: ReviewQueueItem, orderIndex: Int) async throws -> Question {
        // Fetch the idea for context
        let targetIdeaId = queueItem.ideaId
        let descriptor = FetchDescriptor<Idea>(
            predicate: #Predicate<Idea> { idea in
                idea.id == targetIdeaId
            }
        )
        
        guard let idea = try modelContext.fetch(descriptor).first else {
            throw TestGenerationError.generationFailed("Idea not found")
        }

        // If the original was HowWield OpenEnded, use the situational generator for review as well
        if queueItem.bloomCategory == .howWield && queueItem.questionType == .openEnded {
            return try await generateHowWieldQuestion(for: idea, difficulty: queueItem.difficulty, orderIndex: orderIndex)
        }
        
        // Generate a similar question with the same parameters but different content
        let systemPrompt = """
        You are an expert educational content creator. Generate a NEW question that tests the SAME concept as the original question below, but with DIFFERENT content/examples.
        
        Original Question: \(queueItem.originalQuestionText)
        Question Type: \(queueItem.questionType.rawValue)
        Difficulty: \(queueItem.difficulty.rawValue)
        Bloom's Level: \(queueItem.bloomCategory.rawValue)
        
        Requirements:
        - Test the SAME underlying concept
        - Use DIFFERENT examples or scenarios
        - Keep the same difficulty level
        - Keep the same question type (\(queueItem.questionType.rawValue))
        
        \(formatRequirements(for: queueItem.questionType, difficulty: queueItem.difficulty))
        
        Output Format:
        Return ONLY a JSON object with this structure:
        {
            "question": "The new question text",
            "options": ["Option 1", "Option 2", "Option 3", "Option 4"],  // Only for MCQ
            "correct": [0]  // Index of correct answer (0-based)
        }
        
        For open-ended questions, omit options and correct fields.
        """
        
        let userPrompt = """
        Generate a similar but different question for:
        
        Idea: \(idea.title)
        Description: \(idea.ideaDescription)
        
        The question should test the same concept as the original but with fresh content.
        """
        
        let response = try await openAI.complete(
            prompt: "\(systemPrompt)\n\n\(userPrompt)",
            model: "gpt-4.1",
            temperature: 0.8,  // Slightly higher for variety
            maxTokens: 500
        )
        
        let (questionText, options, correctAnswers) = try parseQuestionResponse(response, type: queueItem.questionType)
        
        // Randomize options if they exist
        let finalOptions: [String]?
        let finalCorrectAnswers: [Int]?
        if let opts = options, let correct = correctAnswers {
            let (shuffled, newCorrect) = randomizeOptions(opts, correctIndices: correct)
            finalOptions = shuffled
            finalCorrectAnswers = newCorrect
        } else {
            finalOptions = options
            finalCorrectAnswers = correctAnswers
        }
        
        return Question(
            ideaId: queueItem.ideaId,
            type: queueItem.questionType,
            difficulty: queueItem.difficulty,
            bloomCategory: queueItem.bloomCategory,
            questionText: questionText,
            options: finalOptions,
            correctAnswers: finalCorrectAnswers,
            orderIndex: orderIndex,
            isCurveball: queueItem.isCurveball,
            sourceQueueItemId: queueItem.id
        )
    }
    
    // MARK: - Review Test Generation (focused on mistakes)
    
    private func generateReviewQuestions(for idea: Idea, mistakes: [QuestionResponse]) async throws -> [Question] {
        var questions: [Question] = []
        var orderIndex = 0
        
        // Group mistakes by Bloom category to understand gaps
        let mistakeCategories = analyzeMistakePatterns(mistakes)
        
        // Generate targeted questions for each mistake pattern
        for (category, count) in mistakeCategories {
            // Generate 1-2 questions targeting this specific gap
            let numQuestions = min(count, 2)
            for _ in 0..<numQuestions {
                let difficulty = determineDifficultyForReview(category)
                let questionType = [QuestionType.mcq, .msq, .openEnded].randomElement()!
                
                questions.append(try await generateQuestion(
                    for: idea,
                    type: questionType,
                    difficulty: difficulty,
                    bloomCategory: category,
                    orderIndex: orderIndex,
                    isReview: true
                ))
                orderIndex += 1
            }
        }
        
        // Fill remaining slots with new questions following the same pattern
        while questions.count < 8 {
            let (category, difficulty, type) = getQuestionConfigForSlot(questions.count)
            
            questions.append(try await generateQuestion(
                for: idea,
                type: type,
                difficulty: difficulty,
                bloomCategory: category,
                orderIndex: orderIndex
            ))
            orderIndex += 1
        }
        
        return questions
    }
    
    // MARK: - Individual Question Generation
    
    private func generateQuestion(
        for idea: Idea,
        type: QuestionType,
        difficulty: QuestionDifficulty,
        bloomCategory: BloomCategory,
        orderIndex: Int,
        isReview: Bool = false
    ) async throws -> Question {
        // Special-case: Q8 HowWield situational apply (boss-simple)
        if type == .openEnded && bloomCategory == .howWield {
            logger.debug("HOWWIELD: Using situational generator for Q8 (orderIndex=\(orderIndex))")
            return try await generateHowWieldQuestion(for: idea, difficulty: difficulty, orderIndex: orderIndex)
        }
        // Minimal handling for Reframe Q6: no LLM, just a simple invite
        if type == .openEnded && bloomCategory == .reframe {
            return Question(
                ideaId: idea.id,
                type: type,
                difficulty: difficulty,
                bloomCategory: bloomCategory,
                questionText: "In your own words, explain '\(idea.title)' as if you were telling a friend.",
                options: nil,
                correctAnswers: nil,
                orderIndex: orderIndex
            )
        }

        let systemPrompt = createSystemPrompt(for: type, difficulty: difficulty, bloomCategory: bloomCategory)
        let userPrompt = createUserPrompt(for: idea, type: type, bloomCategory: bloomCategory, isReview: isReview)
        
        let response = try await openAI.complete(
            prompt: "\(systemPrompt)\n\n\(userPrompt)",
            model: "gpt-4.1",
            temperature: 0.7,
            maxTokens: 500
        )
        
        // Parse the response based on question type
        let (questionText, options, correctAnswers) = try parseQuestionResponse(response, type: type)
        
        // Randomize options if they exist (MCQ and MSQ)
        let finalOptions: [String]?
        let finalCorrectAnswers: [Int]?
        if let opts = options, let correct = correctAnswers {
            let (shuffled, newCorrect) = randomizeOptions(opts, correctIndices: correct)
            let normalized = await normalizeOptionLengthsIfNeeded(options: shuffled, correctIndex: newCorrect.first ?? 0, difficulty: difficulty, contextQuestion: questionText)
            finalOptions = normalized
            finalCorrectAnswers = newCorrect
        } else {
            finalOptions = options
            finalCorrectAnswers = correctAnswers
        }
        
        return Question(
            ideaId: idea.id,
            type: type,
            difficulty: difficulty,
            bloomCategory: bloomCategory,
            questionText: questionText,
            options: finalOptions,
            correctAnswers: finalCorrectAnswers,
            orderIndex: orderIndex
        )
    }
    
    // MARK: - Prompt Creation

    // MARK: - Q8 HowWield (Self-Reflection Apply) Prompt

    private func createHowWieldSystemPrompt() -> String {
        return """
        Q8 = HowWield (Self-Reflection Apply).

        Write a short prompt (1–3 sentences). No labels.

        Focus:
        - Talk directly to the learner as "you".
        - Start by nudging them to recall a recent situation, project, or challenge connected to the idea. Do not invent personas, names, or backstories.
        - Give one clear micro-task that asks for 2–3 moves (e.g., "list 2 ways", "compare 3 options", "pick 1 approach") tied to that situation.
        - End with the exact phrase "and say why in one sentence."

        Rules:
        - Plain English, zero jargon. No semicolons (;), no parentheses (). Dead simple language.
        - Ban words: evaluate, assess, consider, explore, leverage, optimize, stakeholders, methodology, qualitative, quantitative.
        - Include ≥1 exact term from the Idea text.
        - Make it answerable with only the given info.
        - Make the situation, constraints, and task unmistakable (crystal clear) even without labels.
        - The question length does not matter, but keep it clear.

        Return only the prompt text (no JSON, no bullets, no extra lines).
        """
    }

    private func createHowWieldUserPrompt(idea: Idea) -> String {
        return """
        Create ONE HowWield reflection question for this idea as a short prompt (1–3 sentences, no labels).

        Requirements:
        - Speak to the learner as "you" and reference their own recent experience connected to the idea (no invented personas or names).
        - Ask them to recall a challenge, task, or decision they handled that ties to the idea.
        - Give one concrete action (choose/pick/list/write/draw/rank/mark/decide/calc) that needs 2–3 responses, and end with the phrase "and say why in one sentence."

        Title: \(idea.title)
        Idea: \(idea.ideaDescription)
        Book: \(idea.bookTitle)

        Use at least one exact term from the Idea. Dead simple language. No jargon or banned words.
        """
    }
    
    private func createSystemPrompt(for type: QuestionType, difficulty: QuestionDifficulty, bloomCategory: BloomCategory) -> String {
        // Special-case: Reframe should be a minimal, single-sentence invitation
        if type == .openEnded && bloomCategory == .reframe {
            return """
            Write a single, simple prompt that asks the learner to explain the idea in their own words.
            Requirements:
            - Exactly 1 sentence
            - Must include the phrase "in your own words"
            - No lists, hints, sub‑questions, or evaluation criteria
            Output ONLY a JSON object: { "question": "..." }
            """
        }

        return """
        You are an expert educational content creator specializing in creating questions based on Bloom's Taxonomy.
        
        Create a \(type.rawValue) question at the \(bloomCategory.rawValue) level.
        Difficulty: \(difficulty.rawValue)
        
        Question Requirements:
        - \(bloomCategory.rawValue): \(bloomDescription(for: bloomCategory))
        - Difficulty appropriate for \(difficulty.bloomLevel)
        - Clear and unambiguous wording
        - Tests deep understanding, not memorization
        
        \(formatRequirements(for: type, difficulty: difficulty))
        
        Output Format:
        Return ONLY a JSON object with this structure:
        {
            "question": "The question text",
            "options": ["Option 1", "Option 2", "Option 3", "Option 4"],  // Only for MCQ/MSQ
            "correct": [0]  // Indices of correct answers (0-based)
        }
        
        For open-ended questions, omit options and correct fields.
        """
    }

    // MARK: - Q8 HowWield Validator & Parser

    private func validateAndParseHowWield(response: String, idea: Idea) -> (String?, [String]) {
        var failures: [String] = []
        let text = response.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        // Must address the learner directly
        let secondPersonRegex = try! NSRegularExpression(pattern: #"\b(you|your|yours)\b"#, options: [.caseInsensitive])
        if secondPersonRegex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length)) == nil {
            failures.append("must speak to the learner as 'you'")
        }

        // Avoid fabricated first-person personas
        let personaRegex = try! NSRegularExpression(pattern: #"\bI\s*(?:am|['’]m)\b"#, options: [.caseInsensitive])
        if personaRegex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length)) != nil {
            failures.append("should not use first-person persona")
        }

        // Must contain the phrase “and say why”
        if !text.lowercased().contains("and say why") { failures.append("must include 'and say why'") }

        // No labels and no jargon — basic checks
        let disallowLabels = ["Role:", "Goal:", "Constraints:", "Data:", "Tools:", "Task:"]
        if disallowLabels.contains(where: { text.contains($0) }) { failures.append("no labels allowed") }
        let banned = ["evaluate","assess","consider","explore","leverage","optimize","stakeholders","methodology","qualitative","quantitative"]
        if banned.contains(where: { text.lowercased().contains($0) }) { failures.append("contains banned words") }

        // No semicolons/parentheses
        if text.contains(";") || text.contains("(") || text.contains(")") { failures.append("no ; or ()") }

        // Must include at least one exact idea term
        let ideaText = (idea.title + " " + idea.ideaDescription).lowercased()
        let tokens = ideaText.split { !$0.isLetter && !$0.isNumber && $0 != "-" }
        let containsIdeaToken = tokens.contains { token in text.lowercased().contains(token) && token.count >= 4 }
        if !containsIdeaToken { failures.append("missing idea term") }

        return failures.isEmpty ? (text, []) : (nil, failures)
    }

    // Helper: run HowWield situational generation + validation
    private func generateHowWieldQuestion(for idea: Idea, difficulty: QuestionDifficulty, orderIndex: Int) async throws -> Question {
        let systemPrompt = createHowWieldSystemPrompt()
        let userPrompt = createHowWieldUserPrompt(idea: idea)

        var response = try await openAI.complete(
            prompt: "\(systemPrompt)\n\n\(userPrompt)",
            model: "gpt-4.1",
            temperature: 0.3,
            maxTokens: 500,
            topP: 1
        )

        var (paragraph, failures) = validateAndParseHowWield(response: response, idea: idea)
        if !failures.isEmpty {
            logger.debug("HOWWIELD: Validation failed on first attempt (\(failures.joined(separator: ", "))). Retrying once.")
            let retryPrompt = "\(systemPrompt)\n\n\(userPrompt)\n\nRegenerate the prompt. Fix: \(failures.joined(separator: ", ")). Keep all rules."
            response = try await openAI.complete(
                prompt: retryPrompt,
                model: "gpt-4.1",
                temperature: 0.3,
                maxTokens: 500,
                topP: 1
            )
            (paragraph, failures) = validateAndParseHowWield(response: response, idea: idea)
            if !failures.isEmpty {
                logger.notice("HOWWIELD: Second attempt still failing validator (\(failures.joined(separator: ", "))). Accepting best-effort output.")
            }
        }

        let question = Question(
            ideaId: idea.id,
            type: .openEnded,
            difficulty: difficulty,
            bloomCategory: .howWield,
            questionText: paragraph ?? "Think about your last sprint at QuickCart when conversion stayed at 1.6% and three complaints kept surfacing. List 3 options you could try to fix the top complaint, pick 1 to prioritize, and say why in one sentence.",
            options: nil,
            correctAnswers: nil,
            orderIndex: orderIndex
        )
        // Lite format stores raw text only
        return question
    }
    
    private func createUserPrompt(for idea: Idea, type: QuestionType, bloomCategory: BloomCategory, isReview: Bool) -> String {
        // Special-case: keep the Reframe prompt context minimal to avoid over‑constraining the model
        if type == .openEnded && bloomCategory == .reframe {
            let shortDesc: String = {
                let text = idea.ideaDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.count <= 220 { return text }
                let idx = text.index(text.startIndex, offsetBy: 220)
                return String(text[..<idx]) + "…"
            }()
            return """
            Idea title: \(idea.title)
            Optional context for the model (do not include in the prompt): \(shortDesc)
            Generate the prompt.
            """
        }

        let reviewContext = isReview ? "\nThis is a REVIEW question. Create a variation that tests the same concept from a different angle." : ""
        
        return """
        Create a \(type.rawValue) question for this idea:
        
        Title: \(idea.title)
        Description: \(idea.ideaDescription)
        Book: \(idea.bookTitle)
        
        Bloom's Level: \(bloomCategory.rawValue) - \(bloomDescription(for: bloomCategory))
        \(reviewContext)
        
        Generate a question that specifically tests the \(bloomCategory.rawValue) level of understanding.
        """
    }
    
    private func formatRequirements(for type: QuestionType, difficulty: QuestionDifficulty) -> String {
        let characterLimits = getCharacterLimits(for: difficulty)
        
        switch type {
        case .mcq:
            return """
            MCQ Requirements:
            - Exactly 4 options
            - Only 1 correct answer
            - Distractors should be plausible but clearly wrong
            - Avoid "all of the above" or "none of the above"
            - Question length: \(characterLimits.question) characters max
            - Each option: \(characterLimits.option) characters max
            - Options must be parallel in structure and similar in length (±20% of average); do not make the correct answer longer than others
            """
        case .msq:
            return """
            MSQ Requirements:
            - Exactly 4 options
            - 2-3 correct answers
            - Each option should be independently evaluable
            - Clear indication that multiple answers are expected
            - Question length: \(characterLimits.question) characters max
            - Each option: \(characterLimits.option) characters max
            - Options must be parallel in structure and similar in length (±20% of average)
            """
        case .openEnded:
            return """
            Open-Ended Requirements:
            - Requires 2-4 sentences to answer properly
            - Cannot be answered with yes/no
            - Has clear evaluation criteria
            - Encourages explanation and reasoning
            - Question length: \(characterLimits.question) characters max
            """
        }
    }
    
    private func getCharacterLimits(for difficulty: QuestionDifficulty) -> (question: Int, option: Int) {
        switch difficulty {
        case .easy:
            return (question: 120, option: 60)    // Short and simple
        case .medium:
            return (question: 200, option: 100)   // Moderate length
        case .hard:
            return (question: 280, option: 140)   // More complex, detailed
        }
    }
    
    // MARK: - Helper Methods
    
    private func bloomDescription(for category: BloomCategory) -> String {
        switch category {
        case .recall:
            return "Recognize or identify key aspects of the idea"
        case .reframe:
            return "Explain the idea in your own words"
        case .apply:
            return "Use the idea in a real-life context or scenario"
        case .contrast:
            return "Compare this idea with other related concepts"
        case .critique:
            return "Evaluate the flaws, limitations, or edge cases"
        case .whyImportant:
            return "Understand why this idea matters and its significance"
        case .whenUse:
            return "Identify when and where to apply this idea effectively"
        case .howWield:
            return "Master how to use this idea skillfully and effectively"
        }
    }
    
    private func parseQuestionResponse(_ response: String, type: QuestionType) throws -> (String, [String]?, [Int]?) {
        guard let data = response.data(using: .utf8) else {
            throw TestGenerationError.invalidResponse
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let question = json?["question"] as? String else {
            throw TestGenerationError.missingQuestionText
        }
        
        if type == .openEnded {
            return (question, nil, nil)
        }
        
        guard let options = json?["options"] as? [String],
              options.count == 4 else {
            throw TestGenerationError.invalidOptions
        }
        
        guard let correct = json?["correct"] as? [Int] else {
            throw TestGenerationError.missingCorrectAnswers
        }
        
        // Validate correct answers
        if type == .mcq && correct.count != 1 {
            throw TestGenerationError.invalidCorrectAnswerCount
        }
        if type == .msq && (correct.count < 2 || correct.count > 3) {
            throw TestGenerationError.invalidCorrectAnswerCount
        }
        
        return (question, options, correct)
    }
    
    private func analyzeMistakePatterns(_ mistakes: [QuestionResponse]) -> [BloomCategory: Int] {
        var patterns: [BloomCategory: Int] = [:]
        
        for mistake in mistakes {
            if let question = mistake.question {
                patterns[question.bloomCategory, default: 0] += 1
            }
        }
        
        return patterns
    }
    
    private func determineDifficultyForReview(_ category: BloomCategory) -> QuestionDifficulty {
        switch category {
        case .recall, .reframe, .whyImportant:
            return .easy
        case .apply, .whenUse:
            return .medium
        case .contrast, .critique, .howWield:
            return .hard
        }
    }
    
    private func getQuestionTypeForSlot(_ slotIndex: Int) -> QuestionType {
        // Only Q6 (index 5) and Q8 (index 7) are open-ended
        // All others are MCQ
        if slotIndex == 5 || slotIndex == 7 {
            return .openEnded
        } else {
            return .mcq
        }
    }
    
    private func getQuestionConfigForSlot(_ slotIndex: Int) -> (BloomCategory, QuestionDifficulty, QuestionType) {
        // Fixed configuration for each slot
        switch slotIndex {
        case 0: return (.recall, .easy, .mcq)           // Q1
        case 1: return (.apply, .easy, .mcq)            // Q2
        case 2: return (.whyImportant, .medium, .mcq)   // Q3
        case 3: return (.whenUse, .medium, .mcq)        // Q4
        case 4: return (.contrast, .medium, .mcq)       // Q5
        case 5: return (.reframe, .medium, .openEnded)  // Q6
        case 6: return (.critique, .hard, .mcq)         // Q7
        case 7: return (.howWield, .hard, .openEnded)   // Q8
        default: return (.recall, .easy, .mcq)          // Fallback
        }
    }
    
    private func bloomCategoryForDifficulty(_ difficulty: QuestionDifficulty) -> BloomCategory {
        switch difficulty {
        case .easy:
            return [.recall, .reframe, .whyImportant].randomElement()!
        case .medium:
            return [.apply, .whenUse].randomElement()!
        case .hard:
            return [.contrast, .critique, .howWield].randomElement()!
        }
    }
}

// MARK: - Test Generation Errors

enum TestGenerationError: Error {
    case invalidResponse
    case missingQuestionText
    case invalidOptions
    case missingCorrectAnswers
    case invalidCorrectAnswerCount
    case generationFailed(String)
    
    var localizedDescription: String {
        switch self {
        case .invalidResponse:
            return "Invalid response format from AI"
        case .missingQuestionText:
            return "Question text is missing"
        case .invalidOptions:
            return "Invalid or missing answer options"
        case .missingCorrectAnswers:
            return "Correct answer indices are missing"
        case .invalidCorrectAnswerCount:
            return "Invalid number of correct answers"
        case .generationFailed(let reason):
            return "Failed to generate question: \(reason)"
        }
    }
}
