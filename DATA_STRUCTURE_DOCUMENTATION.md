# Deepread iOS - Complete Data Structure Documentation

## Overview
This document provides a comprehensive overview of all data models used in the Deepread iOS application, including their purpose, fields, and current usage status.

---

## 📚 Book Model
**Purpose**: Stores information about books that users are reading and learning from.

| Field | Type | Layman Explanation | Usage Status |
|-------|------|-------------------|--------------|
| `id` | UUID | Unique identifier for each book | ✅ **Used** - Primary key |
| `title` | String | The name of the book (e.g., "Atomic Habits") | ✅ **Used** - Displayed throughout app |
| `author` | String? | Who wrote the book | ✅ **Used** - Shown in book views |
| `bookNumber` | Int | Sequential number (1st book, 2nd book, etc.) | ✅ **Used** - For generating idea IDs |
| `createdAt` | Date | When the book was added to the app | ✅ **Used** - For sorting |
| `lastAccessed` | Date | Last time you opened this book | ✅ **Used** - For recent books |
| `ideas` | [Idea] | List of key concepts from this book | ✅ **Used** - Core functionality |
| **Google Books Metadata** | | | |
| `googleBooksId` | String? | Google's ID for this book | ✅ **Used** - For fetching metadata |
| `subtitle` | String? | Book's subtitle if it has one | ⚠️ **Fetched but not displayed** |
| `publisher` | String? | Company that published the book | ⚠️ **Fetched but not displayed** |
| `language` | String? | Language the book is written in | ⚠️ **Fetched but not displayed** |
| `categories` | String? | Book genres (e.g., "Self-Help, Psychology") | ⚠️ **Fetched but not displayed** |
| `thumbnailUrl` | String? | Small book cover image URL | ✅ **Used** - For cover display |
| `coverImageUrl` | String? | Large book cover image URL | ✅ **Used** - For cover display |
| `averageRating` | Double? | Average star rating from Google Books | ⚠️ **Fetched but not displayed** |
| `ratingsCount` | Int? | Number of people who rated the book | ⚠️ **Fetched but not displayed** |
| `previewLink` | String? | Link to preview the book online | ⚠️ **Fetched but not displayed** |
| `infoLink` | String? | Link to book information page | ⚠️ **Fetched but not displayed** |

---

## 💡 Idea Model
**Purpose**: Represents key concepts or ideas extracted from books that users want to learn and master.

| Field | Type | Layman Explanation | Usage Status |
|-------|------|-------------------|--------------|
| `id` | String | Unique code like "b1i1" (Book 1, Idea 1) | ✅ **Used** - Primary identifier |
| `title` | String | Name of the concept (e.g., "Habit Stacking") | ✅ **Used** - Displayed everywhere |
| `ideaDescription` | String | Brief explanation of what this idea means | ✅ **Used** - Shown in views |
| `bookTitle` | String | Which book this idea came from | ✅ **Used** - For context |
| `depthTarget` | Int | How deep to learn (1=Basic, 2=Intermediate, 3=Advanced) | ✅ **Used** - Learning progression |
| `masteryLevel` | Int | Your current mastery (0=Not started, 3=Mastered) | ✅ **Used** - Progress tracking |
| `lastPracticed` | Date? | When you last studied this idea | ✅ **Used** - For spaced repetition |
| `currentLevel` | Int? | Where you left off in your learning journey | ✅ **Used** - Resume functionality |
| `importance` | ImportanceLevel? | How crucial this idea is (Foundation/Building Block/Enhancement) | ✅ **Used** - Visual indicators |
| `book` | Book? | Link back to the parent book | ✅ **Used** - Navigation |
| `progress` | [Progress] | Your learning history for this idea | ✅ **Used** - Track attempts |

---

## 📈 Progress Model
**Purpose**: Tracks each learning session and attempt for an idea.

| Field | Type | Layman Explanation | Usage Status |
|-------|------|-------------------|--------------|
| `id` | UUID | Unique identifier for this progress record | ✅ **Used** - Primary key |
| `ideaId` | String | Which idea this progress belongs to | ✅ **Used** - Linking |
| `level` | Int | Which difficulty level was attempted | ✅ **Used** - Progress tracking |
| `score` | Int | Points earned in this attempt | ✅ **Used** - Performance metric |
| `masteryLevel` | Int | Mastery achieved after this attempt | ✅ **Used** - Progression |
| `timestamp` | Date | When this learning session happened | ✅ **Used** - History |
| `idea` | Idea? | Link back to the idea | ✅ **Used** - Relationship |

---

## 📖 Primer Model
**Purpose**: Detailed explanations and learning materials for each idea.

| Field | Type | Layman Explanation | Usage Status |
|-------|------|-------------------|--------------|
| `id` | UUID | Unique identifier | ✅ **Used** - Primary key |
| `ideaId` | String | Which idea this primer explains | ✅ **Used** - Linking |
| **Active Content Fields** | | | |
| `thesis` | String | The main point in one sentence | ✅ **Used** - Core explanation |
| `story` | String | A story or example that illustrates the idea | ✅ **Used** - Narrative learning |
| `useItWhen` | [String] | Situations where you'd apply this idea | ✅ **Used** - Practical application |
| `howToApply` | [String] | Step-by-step instructions to use this idea | ✅ **Used** - Implementation guide |
| `edgesAndLimits` | [String] | When this idea doesn't work or has limitations | ✅ **Used** - Critical thinking |
| `oneLineRecall` | String | Quick memory trigger phrase | ✅ **Used** - Quick review |
| `furtherLearning` | [PrimerLink] | Links to videos, articles for deeper learning | ✅ **Used** - Extended learning |
| **Legacy Fields (Deprecated)** | | | |
| `overview` | String | Old format for main explanation | ❌ **Deprecated** - Migrated to thesis |
| `keyNuances` | [String] | Old format for details | ❌ **Deprecated** - Split into other fields |
| `digDeeperLinks` | [PrimerLink] | Old format for links | ❌ **Deprecated** - Migrated to furtherLearning |
| `createdAt` | Date | When this primer was created | ✅ **Used** - Metadata |
| `lastAccessed` | Date? | When you last viewed this primer | ⚠️ **Stored but not actively used** |
| `idea` | Idea? | Link back to the idea | ✅ **Used** - Relationship |

---

## 📝 Test Model
**Purpose**: Container for quizzes that test your understanding of ideas.

| Field | Type | Layman Explanation | Usage Status |
|-------|------|-------------------|--------------|
| `id` | UUID | Unique test identifier | ✅ **Used** - Primary key |
| `ideaId` | String | Which idea is being tested | ✅ **Used** - Linking |
| `ideaTitle` | String | Name of the idea being tested | ✅ **Used** - Display |
| `bookTitle` | String | Which book this test relates to | ✅ **Used** - Context |
| `testType` | String | "initial" (first test) or "review" (spaced repetition) | ✅ **Used** - Test flow |
| `createdAt` | Date | When this test was created | ✅ **Used** - Metadata |
| `scheduledFor` | Date? | When a review test should be taken | ✅ **Used** - Spaced repetition |
| `questions` | [Question] | The actual quiz questions | ✅ **Used** - Core functionality |
| `attempts` | [TestAttempt] | All times users tried this test | ✅ **Used** - History tracking |
| `idea` | Idea? | Link back to the idea | ✅ **Used** - Navigation |

---

## ❓ Question Model
**Purpose**: Individual questions within a test.

| Field | Type | Layman Explanation | Usage Status |
|-------|------|-------------------|--------------|
| `id` | UUID | Unique question identifier | ✅ **Used** - Primary key |
| `testId` | UUID? | Which test contains this question | ✅ **Used** - Grouping |
| `ideaId` | String | Which idea this question tests | ✅ **Used** - Linking |
| `type` | QuestionType | MCQ (single choice), MSQ (multiple choice), or OpenEnded (write answer) | ✅ **Used** - Question format |
| `difficulty` | QuestionDifficulty | Easy (10pts), Medium (15pts), or Hard (25pts) | ✅ **Used** - Scoring system |
| `bloomCategory` | BloomCategory | Type of thinking required (Recall, Apply, Critique, etc.) | ✅ **Used** - Educational taxonomy |
| `questionText` | String | The actual question being asked | ✅ **Used** - Display |
| `options` | [String]? | Multiple choice options (if applicable) | ✅ **Used** - MCQ/MSQ only |
| `correctAnswers` | [Int]? | Which options are correct (by index) | ✅ **Used** - Grading |
| `orderIndex` | Int | Question position in test (0-8) | ✅ **Used** - Sequencing |
| `createdAt` | Date | When question was created | ✅ **Used** - Metadata |
| `test` | Test? | Link back to parent test | ✅ **Used** - Relationship |

---

## 🎯 TestAttempt Model
**Purpose**: Records each time a user takes a test.

| Field | Type | Layman Explanation | Usage Status |
|-------|------|-------------------|--------------|
| `id` | UUID | Unique attempt identifier | ✅ **Used** - Primary key |
| `testId` | UUID | Which test was attempted | ✅ **Used** - Linking |
| `startedAt` | Date | When user began the test | ✅ **Used** - Timing |
| `completedAt` | Date? | When user finished (if completed) | ✅ **Used** - Completion tracking |
| `score` | Int | Total points earned (out of 150) | ✅ **Used** - Performance |
| `isComplete` | Bool | Whether user finished all questions | ✅ **Used** - State tracking |
| `masteryAchieved` | MasteryType | None, Fragile (needs review), or Solid (mastered) | ✅ **Used** - Progress levels |
| `retryCount` | Int | How many times user retried wrong answers | ✅ **Used** - Retry tracking |
| `currentQuestionIndex` | Int | Where user is if they paused mid-test | ✅ **Used** - Resume feature |
| `responses` | [QuestionResponse] | All answers given | ✅ **Used** - Answer tracking |
| `test` | Test? | Link back to test | ✅ **Used** - Relationship |

---

## ✍️ QuestionResponse Model
**Purpose**: Records a user's answer to a specific question.

| Field | Type | Layman Explanation | Usage Status |
|-------|------|-------------------|--------------|
| `id` | UUID | Unique response identifier | ✅ **Used** - Primary key |
| `attemptId` | UUID | Which test attempt this belongs to | ✅ **Used** - Grouping |
| `questionId` | UUID | Which question was answered | ✅ **Used** - Linking |
| `questionType` | QuestionType | Type of question answered | ✅ **Used** - Processing |
| `userAnswer` | String | What the user answered (JSON encoded) | ✅ **Used** - Storage |
| `isCorrect` | Bool | Whether the answer was right | ✅ **Used** - Grading |
| `pointsEarned` | Int | Points received for this answer | ✅ **Used** - Scoring |
| `answeredAt` | Date | When the answer was submitted | ✅ **Used** - Timestamp |
| `retryNumber` | Int | Which attempt this was (0 = first try) | ✅ **Used** - Retry tracking |
| `evaluationData` | Data? | AI feedback on open-ended answers (JSON) | ✅ **Used** - AI evaluation |
| `attempt` | TestAttempt? | Link back to attempt | ✅ **Used** - Relationship |
| `question` | Question? | Link back to question | ✅ **Used** - Relationship |

---

## 📊 TestProgress Model
**Purpose**: Tracks overall testing performance and schedules reviews.

| Field | Type | Layman Explanation | Usage Status |
|-------|------|-------------------|--------------|
| `id` | UUID | Unique progress identifier | ✅ **Used** - Primary key |
| `ideaId` | String | Which idea this tracks | ✅ **Used** - Linking |
| `currentTestId` | UUID? | Most recent test taken | ⚠️ **Partially used** |
| `lastTestDate` | Date? | When last test was completed | ✅ **Used** - History |
| `nextReviewDate` | Date? | When next review is scheduled | ✅ **Used** - Spaced repetition |
| `masteryType` | MasteryType | Current mastery level | ✅ **Used** - Progress tracking |
| `totalTestsTaken` | Int | How many tests completed | ✅ **Used** - Statistics |
| `averageScore` | Double | Average performance across all tests | ✅ **Used** - Performance metric |
| `mistakePatterns` | Data? | Analysis of common errors (JSON) | ❌ **Not implemented** - Future feature |
| `idea` | Idea? | Link back to idea | ✅ **Used** - Relationship |

---

## 🔤 Enums and Types

### ImportanceLevel
| Value | Meaning | Visual Indicator |
|-------|---------|-----------------|
| `foundation` | Core concept - must understand | 3 bars |
| `buildingBlock` | Important supporting idea | 2 bars |
| `enhancement` | Nice to know, adds depth | 1 bar |

### QuestionType
| Value | Meaning | User Experience |
|-------|---------|----------------|
| `mcq` | Multiple Choice Question | Select one correct answer |
| `msq` | Multiple Select Question | Select all correct answers |
| `openEnded` | Open-Ended Question | Type your own answer |

### QuestionDifficulty
| Value | Points | Cognitive Level |
|-------|--------|-----------------|
| `easy` | 10 | Recall/Reframe/Why Important |
| `medium` | 15 | Apply/When to Use |
| `hard` | 25 | Contrast/Critique/How to Wield |

### MasteryType
| Value | Meaning | Next Step |
|-------|---------|-----------|
| `none` | Not mastered yet | Keep practicing |
| `fragile` | Basic understanding | Review in 3 days |
| `solid` | Full mastery | Move to next idea |

### BloomCategory (Cognitive Levels)
| Value | Meaning | Example Question Type |
|-------|---------|---------------------|
| `recall` | Remember facts | "What is X?" |
| `reframe` | Explain in own words | "Explain X in simple terms" |
| `apply` | Use in real situation | "How would you use X?" |
| `contrast` | Compare with others | "How does X differ from Y?" |
| `critique` | Evaluate limitations | "What are the weaknesses of X?" |
| `whyImportant` | Understand significance | "Why does X matter?" |
| `whenUse` | Identify applications | "When should you use X?" |
| `howWield` | Master usage | "How do you effectively apply X?" |

---

## 📱 Data Flow Summary

1. **Book Creation**: User adds book → Fetches Google Books metadata → Creates Book record
2. **Idea Extraction**: AI extracts ideas → Creates Idea records with book-specific IDs (b1i1, b1i2, etc.)
3. **Primer Generation**: AI generates detailed explanations → Creates Primer records
4. **Test Creation**: AI generates 9 questions (3 easy, 3 medium, 3 hard) → Creates Test and Question records
5. **Test Taking**: User answers questions → Creates TestAttempt and QuestionResponse records
6. **Progress Tracking**: Scores calculated → Updates Progress and TestProgress records
7. **Spaced Repetition**: System schedules review tests based on mastery level

---

## 🔍 Usage Status Legend

- ✅ **Used**: Actively used in the current implementation
- ⚠️ **Partially Used**: Stored/fetched but not fully utilized
- ❌ **Not Used**: Planned for future or deprecated

---

## 💾 Storage Details

- **Framework**: SwiftData (Apple's modern data persistence framework)
- **Storage Type**: SQLite database (persistent, not in-memory)
- **Deletion Rules**: Cascade delete (removing parent removes all children)
- **Migration**: Automatic schema migration handled by SwiftData