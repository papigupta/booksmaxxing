# User Analytics Metric Contract

Each snapshot row in `UserAnalyticsSnapshot` represents one Booksmaxxing account (or persistent guest). Below are the plain-language meanings plus the exact hooks that update them.

## Identity & Lifecycle
- `userId` / `userIdentifier`: stable Sign in with Apple id or sticky guest id stored directly on the snapshot (`UserAnalyticsSnapshot.swift:6-13`). The service resolves/updates it whenever auth state changes (`UserAnalyticsService.swift:31-41`).
- `firstSeenAt`: timestamp of the very first app launch. Set once when the snapshot is created in `loadOrCreateSnapshot` (`UserAnalyticsService.swift:174-191`).
- `signedInAt`: first time the user successfully signs in with Apple (guest sessions leave it `nil`). Written the first time `updateAuthState` sees `isSignedIn && !isGuestSession` (`UserAnalyticsService.swift:31-41`, `144-149`).
- `appVersionLastSeen`: the app build last used. Updated on every launch via `refreshAnalyticsServiceContext` (`BooksmaxxingApp.swift:148-160`) which calls `recordAppLaunch` (`UserAnalyticsService.swift:44-47`).
- `createdAt` / `lastUpdatedAt`: automatically stamped when the snapshot row is created and every time `updateSnapshot` runs (`UserAnalyticsSnapshot.swift:9-13`, `UserAnalyticsService.swift:197-201`).

## Contact & Email
- `hasEmail`, `emailStatus`, `emailUpdatedAt`: `true` once the user submits (or shares) any email. All screens funnel into `markEmail` (`UserAnalyticsService.swift:50-57`) triggered from Apple auto-fill (`MainView.swift:293-312`), Email Capture (`EmailCaptureView.swift:247-288`), and manual edits (`ProfileView.swift:96-134`). `emailStatus` mirrors `UserProfile.emailStatus` and `emailUpdatedAt` captures the latest decision.

## Library & Starter Books
- `hasAddedBook`: flips to true once any `Book` exists for the user. `refreshBookStats` computes it (`UserAnalyticsService.swift:59-71`), and that method is run on launch (`BooksmaxxingApp.swift:148-160`), after manual adds (`BookService.swift:58-70`), deletes (`BookService.swift:532-555`), and starter seeding (`StarterBookSeeder.swift:13-20`).
- `starterLessonBookCount`: count of starter-library titles currently in the model. Comes from the same `refreshBookStats` calls above.

## Lesson Funnel
- `startedLesson` / `firstLessonStartedAt`: first time the user actually launches a practice session. All lesson launchers call `markLessonStarted(book:)` (`UserAnalyticsService.swift:73-85`) from `DailyPracticeView` (`DailyPracticeView.swift:131-137`), `DailyPracticeWithReviewView` (`DailyPracticeWithReviewView.swift:148-157`), and the tooltip launcher when a session begins or resumes (`DailyPracticeTooltip.swift:599-626`).
- `usedStarterLesson` / `starterLessonFirstUsedAt`: `markLessonStarted` also flags the moment a starter-library book powers a lesson by checking the seed id set on each starter book (`UserAnalyticsService.swift:73-85`, starter id list built at lines 169-172).
- `finishedLesson` / `firstLessonFinishedAt`: first successful practice completion. Set inside each completion handler right after a test ends (`UserAnalyticsService.swift:87-94`, invoked in `DailyPracticeView.swift:778-791`, `DailyPracticeWithReviewView.swift:663-670`, and `DailyPracticeTooltip.swift:665-671`).

## Results & Supporting Screens
- `resultsViewed` / `resultsLastViewedAt`: toggled whenever the user reaches any results UI—either the review-style summary (`DailyPracticeWithReviewView.swift:820-845`) or the Brain Calories screen (`BrainCaloriesView.swift:40-48`).
- `primerOpened` / `primerFirstOpenedAt`: set when any primer sheet appears (`PrimerView.swift:37-52`).
- `streakPageViewed` / `streakPageLastViewedAt`: marked when the dedicated streak overlay is shown (`StreakView.swift:63-86`).
- `activityRingsViewed` / `activityRingsLastViewedAt`: marked when the Brain Calories / rings view opens (`BrainCaloriesView.swift:40-48`).

## Streaks & Attention Rings
- `currentStreak`, `bestStreak`, `streakLitToday`: sourced straight from `StreakManager`. Every mutation funnels through `notifyAnalytics()` (`StreakManager.swift:187-233`), which calls `updateStreak` (`UserAnalyticsService.swift:126-132`).
- `brainCaloriesRingClosed`, `clarityRingClosed`, `attentionRingClosed`: sticky booleans that remember whether the user has *ever* closed each ring. We evaluate the thresholds (200 BCal / 80% clarity / 80% attention) as soon as a session ends (`DailyPracticeView.swift:940-965`, `DailyPracticeWithReviewView.swift:672-690`, `DailyPracticeTooltip.swift:822-842`) and update the snapshot via `updateRingClosures` (`UserAnalyticsService.swift:134-140`).

## Bookkeeping Pages
- `starterLessonBookCount` (see Library section) plus `starterLessonFirstUsedAt` (lesson funnel) combine to answer “did they actually use the starter path?”
- `activityRingsViewed`/`streakPageViewed` also give you the drop-off point if someone bails before lighting their streak or seeing rings (hooks listed above).

With this mapping, every column in `UserAnalyticsSnapshot` links to a single place in code, so you can trust the CloudKit table when eyeballing onboarding cohorts.
