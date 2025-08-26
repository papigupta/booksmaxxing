# Old Evaluation System Documentation

## Overview
This document preserves ALL prompts, structures, and logic of the old evaluation system that was replaced by the multi-question test system. This serves as a reference for potential future use of specific components and contains all the battle-tested prompts that were refined through extensive use.

## System Architecture

### Core Models

#### UserResponse Model
- **Purpose**: Stored user's responses to idea prompts
- **Key Fields**:
  - `ideaId`: Reference to the idea being evaluated
  - `level`: 1, 2, or 3 (corresponding to different depth levels)
  - `prompt`: The original question asked
  - `response`: User's text response
  - `evaluationData`: JSON encoded evaluation results
  - `evaluationVersion`: Schema version tracking

#### Progress Model
- **Purpose**: Tracked user progress through levels
- **Key Fields**:
  - `ideaId`: Reference to idea
  - `currentLevel`: Current level (1-3)
  - `levelScores`: Array of scores for each level
  - `completed`: Boolean for completion status

#### EvaluationResult Structure
```swift
struct EvaluationResult {
    let level: String        // "L1", "L2", "L3"
    let starScore: Int       // 1-3 stars
    let starDescription: String // "Getting There", "Solid Grasp", "Aha! Moment"
    let pass: Bool           // starScore >= 2
    let insightCompass: WisdomFeedback // Combined wisdom feedback
    let idealAnswer: String? // 3-star reference answer
    let keyGap: String?      // Fatal flaw explanation
    let hasRealityCheck: Bool // UI flag
    let mastery: Bool        // starScore == 3
}
```

## Level System

### Three-Level Progression

#### Level 1: "Why Care" / "Use"
- **Focus**: Understanding significance and real-world importance
- **Evaluation Criteria**:
  - Application to practical situations
  - Understanding of basic concept
  - Effectiveness of use
  - Clarity of expression
- **Scoring**: Must explain significance with concrete examples

#### Level 2: "When Use" / "Think With"
- **Focus**: Identifying triggers and application contexts
- **Evaluation Criteria**:
  - Critical thinking as a tool
  - Problem-solving effectiveness
  - Insight generation
  - Depth of exploration
- **Scoring**: Must identify specific scenarios for application

#### Level 3: "How Wield" / "Build With"
- **Focus**: Creative/critical extension of the idea
- **Evaluation Criteria**:
  - Creation of new concepts
  - Innovation and originality
  - Synthesis with other ideas
  - Sophisticated development
- **Scoring**: Must demonstrate original applications

## Evaluation Prompts

### Core Evaluation Prompt Template
```
You are the author evaluating the reader's response about "[ideaTitle]".

SOURCE (verbatim, no external info):
[ideaDescription]

READER RESPONSE:
[userResponse]

TASK:
Return strict JSON with this shape:
{
  "score": 0-10,
  "silver_bullet": "1-2 sentence author-voice insight",
  "strengths": ["short bullets"],
  "gaps": ["short bullets"],
  "next_action": "1 sentence on what to do next",
  "pass": true/false,
  "mastery": true/false
}

SCORING GUARDRAILS:
- Judge ONLY against the SOURCE.
- [Level-specific rule]
- If response is vague, reduce score and include a concrete gap.
- Keep "silver_bullet" specific to THIS response.

STYLE:
- Authorial voice, concise, no fluff.
- No markdown. JSON only.
```

### Star-Based Evaluation System

#### Star Scoring Criteria
- **⭐ (1) Getting There**: 
  - Basic engagement but significant gaps
  - Missing key connections
  - Needs substantial work
  
- **⭐⭐ (2) Solid Grasp**: 
  - Good understanding with minor gaps
  - Makes relevant connections
  - Ready to advance
  
- **⭐⭐⭐ (3) Aha! Moment**: 
  - Deep insight achieved
  - Breakthrough thinking
  - Mastery-level understanding

## Feedback Systems

### 1. Author Feedback Structure
```json
{
  "rubric": ["definition_accuracy", "interplay", "application_example"],
  "verdict": "Met X/Y: [met items]; Missed: [missed items]",
  "oneBigThing": "Surgical improvement or misconception",
  "evidence": ["Direct quotes from response"],
  "upgrade": "Rewritten weak sentence",
  "transferCue": "If [trigger], then [action]",
  "microDrill": "60-90 second concrete exercise",
  "memoryHook": "5-7 word memorable phrase",
  "edgeOrTrap": "Optional boundary or confusion point"
}
```

### 2. Wisdom Feedback (Insight Compass)
Six perspective-based feedback components:
1. **wisdomOpening**: Philosophical reframing (20-35 words)
2. **rootCause**: Logical gap analysis (20-30 words)
3. **missingFoundation**: Core knowledge gap (25-40 words)
4. **elevatedPerspective**: Expert-level pattern (25-40 words)
5. **nextLevelPrep**: Next learning step (20-35 words)
6. **personalizedWisdom**: Tailored insight (20-30 words)

### 3. Reality Check System
When user scores less than 3 stars:
- **idealAnswer**: Shows a standalone 3-star response
- **keyGap**: Reveals the deeper insight they're missing
- Focus on consequences, stakes, and real-world impact

## Service Architecture

### EvaluationService Features
- **Reliability**:
  - 45s request timeout, 90s resource timeout
  - Network connectivity monitoring
  - Exponential backoff retry (1.5s, 3s delays)
  - HTTP status code specific handling
  
- **Performance**:
  - Connection pooling (5 max per host)
  - HTTP pipelining enabled
  - Fresh data policy (no caching)
  - Waits for connectivity when offline

- **Error Handling**:
  - Network errors (timeout, no connection)
  - Server errors (rate limits, 5xx)
  - Response format errors (JSON parsing)
  - Graceful degradation

### API Configuration
- **Models Used**:
  - Full evaluation: `gpt-4.1`
  - Structured feedback: `gpt-4.1-mini`
  - Wisdom feedback: `gpt-4.1`
  
- **Temperature Settings**:
  - Evaluation: 0.7 (balanced)
  - Structured feedback: 0.1 (deterministic)
  - Wisdom feedback: 0.8 (creative)

## UI Components (Legacy)

### Views Using Old Evaluation System
1. **IdeaPromptView**: Main evaluation interface
2. **EvaluationResultsView**: Displayed evaluation results
3. **ResponseHistoryView**: Showed past responses
4. **LevelLoadingView**: Loading state during evaluation
5. **CelebrationView**: Success celebration
6. **WhatThisMeansView**: Explained evaluation results
7. **ResponseCard**: Individual response display

### User Flow
1. User selects an idea from BookOverviewView
2. System presents prompt based on current level
3. User submits text response
4. EvaluationService evaluates response
5. Results shown with feedback
6. Progress updated, next level unlocked if passed

## Key Algorithms

### Mastery Calculation
- **Basic Mastery**: Score ≥ 7 on level
- **Full Mastery**: Score = 10 or starScore = 3
- **Level Progression**: Must pass (score ≥ 5) to advance

### Retry Logic
```swift
func withRetry<T>(maxAttempts: Int, operation: @escaping () async throws -> T) async throws -> T {
    for attempt in 1...maxAttempts {
        do {
            return try await operation()
        } catch {
            if attempt < maxAttempts {
                let delay = Double(attempt) * 1.5 // Exponential backoff
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }
    throw lastError
}
```

## Prompt Engineering Insights

### Effective Patterns
1. **Quote Anchoring**: Require direct quotes from user response in feedback
2. **Banned Phrases**: List of generic phrases to avoid
3. **Word Limits**: Strict word counts for concise feedback
4. **Regeneration Logic**: If feedback is generic, regenerate with stricter instructions
5. **Author Voice**: Maintain book author's perspective

### Quality Checks
```swift
func isGeneric(_ feedback: AuthorFeedback) -> Bool {
    // Must have quotes in evidence
    // Verdict must contain "Met", "Missed", "because"
    // No hedging words in upgrade
    // Memory hook 2-8 words
}
```

## Migration Considerations

### Data to Preserve
- User response history
- Evaluation scores and feedback
- Progress tracking
- Prompt templates

### Reusable Components
1. **Prompt Templates**: Can adapt for question generation
2. **Evaluation Criteria**: Can inform test difficulty levels
3. **Feedback Generation**: Can enhance test result explanations
4. **Retry Logic**: Already implemented in test system
5. **Author Voice**: Can be used in test feedback

## Lessons Learned

### What Worked Well
- Star-based scoring was intuitive
- Multiple feedback perspectives added depth
- Quote anchoring prevented generic responses
- Reality Check provided concrete improvement paths
- Author voice made feedback personal

### Challenges
- Open-ended responses were hard to evaluate consistently
- Single response format limited assessment types
- Text-heavy interface could be overwhelming
- Linear progression limited flexibility
- Evaluation could be gamed with generic responses

## Complete Prompt Collection

### 1. Idea Extraction Prompt (OpenAIService)
**Purpose**: Extract core ideas from book titles
```
System Prompt:
Your goal is to extract all core, teachable ideas that a user could master one by one to deeply understand and apply the book. Output them as a JSON array of strings.

Book Author: [if provided]

Guidelines:
• Ideas are distinct mental models, frameworks, distinctions, or cause-effect patterns. Make each self-contained with no overlaps.
• Split if truly separate; combine if they form one cohesive idea (e.g., related concepts like 'Affordances and Signifiers' as one if cohesive).
• Adapt to the book's style—e.g., extract practical steps and mindsets from applied books, or theories and models from conceptual ones.
• Be comprehensive: Cover all ideas worth mastering, in the order they appear in the book. Aim for completeness, but if over 50, prioritize the most impactful.
• Be consistent across runs: Prioritize the book's core narrative and key takeaways. Focus on explanatory power and applicability, not trivia or examples unless essential.
• Avoid redundancy. For eg. Don't extract "Strange Loops" and "Strange Loops in Art and Music", instead use either of the two, and aim to teach both with one single idea.
• For each idea: Use format "iX | Title — Description | Importance" where:
  - Title: short and clear, 1 line max
  - Description: 1-2 sentences explaining essence, significance, and application  
  - Importance: "Foundation" (enables understanding of most other concepts), "Building Block" (important, connects to several others), or "Enhancement" (valuable but specialized)

Additional rules for this API call:
• Titles must be unique. Do not output synonyms or sub-variants as separate items.  
• Prepend each concept with an ID in the form **i1, i2, …** so the client can parse it.  

Example output element: "i1 | Anchoring Effect — Initial numbers bias judgments even if irrelevant, leading to flawed decisions in negotiations or estimates. | Foundation"

Return a **JSON array of strings** (no objects, no extra text).
```

### 2. Book Info Extraction Prompt
**Purpose**: Extract and correct book title and author from user input
```
You are an expert at identifying and correcting book titles and authors from user input.

TASK:
Extract the book title and determine the correct author(s) from the user's input. You should be intelligent about both title correction and author identification:

SCENARIOS:
1. NO AUTHOR MENTIONED: If the user only provides a book title, make your best educated guess about the author based on your knowledge of the book.
2. PARTIAL AUTHOR INFO: If the user provides partial author information (e.g., "Kahneman", "Daniel K"), find the correct full name.
3. FULL AUTHOR NAME: If the user provides a complete, correct author name, use it as-is.
4. MULTIPLE AUTHORS: Handle multiple authors correctly (e.g., "John Smith and Jane Doe" or "Smith & Doe")

TITLE CORRECTION RULES:
1. Correct obvious formatting issues (capitalization, punctuation, spelling)
2. Find the most commonly recognized, complete version of the title
3. If the user provides a partial or abbreviated title, find the full title
4. DO NOT change to a completely different book, even if similar
5. If the title is ambiguous or unclear, keep it as provided
6. Use the official, published title when possible

AUTHOR IDENTIFICATION RULES:
1. When no author is provided, make your best guess based on the book title
2. When partial author info is given, find the correct full name
3. Handle multiple authors correctly with proper formatting
4. Clean up formatting (remove extra spaces, proper capitalization)
5. Handle edge cases like "by [Author]" or "[Author]'s [Book]"
6. Be confident in your author identification - if you're not sure, return null for author
7. DO NOT assume a different book than what the user specified
8. If you know of a book with this title, try to identify the author even if not 100% certain

EXAMPLES:
Input: "thinking fast and slow" → Title: "Thinking, Fast and Slow", Author: "Daniel Kahneman"
Input: "thinking fast and slow by kahneman" → Title: "Thinking, Fast and Slow", Author: "Daniel Kahneman"
Input: "atomic habits" → Title: "Atomic Habits", Author: "James Clear"
Input: "charlie's almanack" → Title: "Poor Charlie's Almanack", Author: "Charles T. Munger"

Return ONLY a valid JSON object:
{
  "title": "Corrected Book Title",
  "author": "Author Name" or null
}
```

### 3. Primer Generation Prompt (PrimerService)
**Purpose**: Generate comprehensive primers for ideas
```
GOAL: Teach "[idea.title]" (from "[idea.bookTitle]") in one page, ready to use now.

SOURCE: Use only this description; add no outside facts:
[idea.ideaDescription]

Voice: Mirror the author's diction, cadence, and stance in the description. Reuse key terms verbatim. Vary sentence length. No filler. No meta (don't say "in this primer/section").

Output format — use these exact headings:

# Thesis (≤22 words)
A single, sharp claim that captures the idea's essence.

# Story (80–120 words)
Share a compelling narrative or example that illustrates this idea in action. Use concrete details and make it memorable.

# Use it when… (3 bullets, ≤10 words each)
Concrete cues/conditions that signal the idea applies.

# How to apply (3 bullets, ≤12 words each, verb-first)
Actionable steps or checks drawn only from the description.

# Edges & limits (2–3 bullets, ≤12 words)
Boundaries, exceptions, or trade-offs stated or implied in the description.

# One-line recall (≤14 words)
A memorable line in the author's tone.

# Further learning (3–4 links)
- [Official/book page]: https://amazon.com/<book-slug-or-isbn>
- [In-depth article]: https://<reputable-site>/<book-or-idea-slug>
- [Talk/lecture video]: https://youtube.com/results?search_query=<author+idea+book>
- [Review/critique]: https://<quality-blog>/<book-or-idea-review>

Rules: No repetition across sections. No hedging. Don't invent examples; if the description includes one, compress it briefly in Story section. Total length ≤ 240 words.
```

### 4. Dynamic Prompt Generation Templates (OpenAIService)
**Purpose**: Generate level-specific prompts for ideas

#### Level 1 System Prompt:
```
You are an expert educational prompt generator for Level 1.

CONTEXT:
- Book: [idea.bookTitle]
- Author: [idea.book?.author ?? "the author"]
- Idea: [idea.title]

TASK:
Generate one open-ended, writing-based question for Level 1 based on this idea from [bookTitle] by [author]: "[idea.title]". 
The goal is to ensure the user understands why this idea matters, such as its significance, impacts, or value in real-world contexts. Make the question concise so a user can answer it thoughtfully in under 10 minutes (e.g., 1-2 short paragraphs).
If answered correctly and substantively, it should confirm they've met the goal. Be creative with the context to make it engaging.

Return only the question text, nothing else.
```

#### Level 2 System Prompt:
```
You are an expert educational prompt generator for Level 2.

CONTEXT:
- Book: [idea.bookTitle]
- Author: [idea.book?.author ?? "the author"]
- Idea: [idea.title]

TASK:
Generate one open-ended, writing-based question for Level 2 based on this idea from [bookTitle] by [author]: "[idea.title]". 
The goal is to ensure the user can identify when to recall and apply this idea, such as triggers, situations, or practical contexts for using it effectively. Make the question concise so a user can answer it thoughtfully in under 10 minutes (e.g., 1-2 short paragraphs).
If answered correctly and substantively, it should confirm they've met the goal. Be creative with the context to make it engaging.

Return only the prompt text, nothing else.
```

#### Level 3 System Prompt:
```
You are an expert educational prompt generator for Level 3.

CONTEXT:
- Book: [idea.bookTitle]
- Author: [idea.book?.author ?? "the author"]
- Idea: [idea.title]

TASK:
Generate one open-ended, writing-based question for Level 3 based on this idea from [bookTitle] by [author]: "[idea.title]".
The goal is to ensure the user can wield this idea creatively or critically, such as extending it to new applications, innovating with it, or analyzing its limitations. Make the question concise so a user can answer it thoughtfully in under 10 minutes (e.g., 1-2 short paragraphs).
If answered correctly and substantively, it should confirm they've met the goal. Be creative with the context to make it engaging.

Return only the prompt text, nothing else.
```

## Future Integration Possibilities

1. **Hybrid Approach**: Use open-ended questions for Level 3 mastery
2. **Feedback Enhancement**: Apply wisdom feedback to test results
3. **Reality Check**: Show ideal answers for incorrect test responses
4. **Author Voice**: Incorporate in test question narrative
5. **Prompt Templates**: Adapt for generating question explanations
6. **Idea Extraction**: Already being used in current system
7. **Primer Generation**: Still active in the new system

---

*This documentation preserves ALL prompts and evaluation logic from the old system. These prompts were refined through extensive testing and represent valuable intellectual property that can be adapted for future features.*