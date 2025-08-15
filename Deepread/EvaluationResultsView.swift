import SwiftUI

struct EvaluationResultsView: View {
    let idea: Idea
    let userResponse: String
    let prompt: String
    let level: Int
    let onOpenPrimer: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var evaluationResult: EvaluationResult?
    @State private var isLoadingEvaluation = true
    @State private var evaluationError: String?
    @State private var navigateToWhatThisMeans = false
    @State private var isResponseExpanded = false
    @State private var navigateToHome = false
    @State private var showingPrimer = false
    @State private var authorFeedback: AuthorFeedback? = nil
    @State private var isLoadingStructuredFeedback = false
    @State private var structuredFeedbackError: String? = nil
    @State private var wisdomFeedback: WisdomFeedback? = nil
    @State private var isLoadingWisdomFeedback = false
    @State private var wisdomFeedbackError: String? = nil
    @State private var isPromptExpanded = false
    
    private var evaluationService: EvaluationService {
        EvaluationService(apiKey: Secrets.openAIAPIKey)
    }
    
    private var userResponseService: UserResponseService {
        UserResponseService(modelContext: modelContext)
    }
    
    private var truncatedResponse: String {
        let maxLength = 120
        if userResponse.count <= maxLength {
            return userResponse
        }
        let truncated = String(userResponse.prefix(maxLength))
        return truncated + "..."
    }
    
    
    var body: some View {
        ZStack {
            // Background
            DS.Colors.secondaryBackground
                .ignoresSafeArea()
            
            if isLoadingEvaluation {
                loadingView
            } else if let error = evaluationError {
                DSErrorView(
                    title: "Evaluation Error",
                    message: error,
                    retryAction: { loadEvaluation() }
                )
            } else if let result = evaluationResult {
                evaluationContentView(result)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                homeButton
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                primerButton
            }
        }
        .navigationDestination(isPresented: $navigateToWhatThisMeans) {
            if let result = evaluationResult {
                WhatThisMeansView(
                    idea: idea,
                    evaluationResult: result,
                    userResponse: userResponse,
                    level: level,
                    openAIService: OpenAIService(apiKey: Secrets.openAIAPIKey)
                )
            }
        }
        .navigationDestination(isPresented: $navigateToHome) {
            BookOverviewView(bookTitle: idea.bookTitle, openAIService: OpenAIService(apiKey: Secrets.openAIAPIKey), bookService: BookService(modelContext: modelContext))
        }
        .sheet(isPresented: $showingPrimer) {
            PrimerView(idea: idea, openAIService: OpenAIService(apiKey: Secrets.openAIAPIKey))
        }
        .onAppear {
            loadEvaluation()
        }
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: DS.Spacing.xxl) {
            Spacer()
            
            // Animated loading icon
            ZStack {
                Circle()
                    .stroke(DS.Colors.gray300, lineWidth: 4)
                    .frame(width: 80, height: 80)
                
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(DS.Colors.black, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isLoadingEvaluation)
            }
            
            VStack(spacing: DS.Spacing.lg) {
                Text("Analyzing Your Response")
                    .font(DS.Typography.title)
                    .multilineTextAlignment(.center)
                    .foregroundColor(DS.Colors.primaryText)
                
                VStack(spacing: DS.Spacing.lg) {
                    let loadingSteps = [
                        "Scouting for hidden insights",
                        "Weighing depth vs. detail", 
                        "Sorting you onto the mastery ladder"
                    ]
                    
                    ForEach(0..<loadingSteps.count, id: \.self) { index in
                        HStack(spacing: DS.Spacing.md) {
                            Rectangle()
                                .fill(DS.Colors.black)
                                .frame(width: 8, height: 8)
                            
                            Text(loadingSteps[index])
                                .font(DS.Typography.body)
                                .foregroundStyle(DS.Colors.primaryText)
                            
                            Spacer()
                        }
                        .padding(.horizontal, DS.Spacing.xl)
                    }
                }
                
                Text("Almost there—loading challenges that match your power-ups")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.xl)
            }
            
            Spacer()
        }
        .padding(DS.Spacing.lg)
    }
    
    
    // MARK: - Main Evaluation Content
    private func evaluationContentView(_ result: EvaluationResult) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header Section
                headerSection(result)
                
                // Score Section
                scoreSection(result)
                
                // Reality Check Section (replaces response section for <3 star responses)
                if result.hasRealityCheck {
                    realityCheckSection(result)
                } else {
                    responseSection
                }
                
                // Insight Compass Section (Now built into evaluation)
                wisdomFeedbackSection(result.insightCompass)
                
                // Action Section
                actionSection(result)
            }
        }
        .background(DS.Colors.secondaryBackground)
    }
    
    // MARK: - Header Section
    private func headerSection(_ result: EvaluationResult) -> some View {
        VStack(spacing: DS.Spacing.lg) {
            // Book title
            Text(idea.bookTitle)
                .font(DS.Typography.caption)
                .fontWeight(.medium)
                .foregroundStyle(DS.Colors.secondaryText)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.top, DS.Spacing.lg)
            
            // Idea title
            Text(idea.title)
                .font(DS.Typography.title)
                .multilineTextAlignment(.center)
                .foregroundColor(DS.Colors.primaryText)
                .padding(.horizontal, DS.Spacing.lg)
            
            // Level indicator
            HStack(spacing: DS.Spacing.xs) {
                DSIcon(getLevelIcon(for: level), size: 14)
                
                Text("Level \(level)")
                    .font(DS.Typography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.Colors.secondaryText)
            }
            .dsCard(padding: DS.Spacing.sm)
            
            // Prompt viewer (subtle and collapsible)
            VStack(spacing: DS.Spacing.xs) {
                Button(action: { 
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isPromptExpanded.toggle()
                    }
                }) {
                    HStack(spacing: DS.Spacing.xs) {
                        DSIcon("questionmark.circle", size: 14)
                        
                        Text("View Question")
                            .font(DS.Typography.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(DS.Colors.secondaryText)
                        
                        DSIcon(isPromptExpanded ? "chevron.up" : "chevron.down", size: 12)
                    }
                }
                .dsSmallButton()
                
                if isPromptExpanded {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        HStack {
                            Text("Question")
                                .font(DS.Typography.captionBold)
                                .foregroundStyle(DS.Colors.secondaryText)
                                .textCase(.uppercase)
                                .tracking(0.5)
                            Spacer()
                        }
                        
                        Text(prompt)
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Colors.primaryText)
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)
                            .dsSubtleCard()
                    }
                    .padding(.horizontal, DS.Spacing.xxs)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
                }
            }
            .padding(.top, DS.Spacing.sm)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.lg)
    }
    
    // MARK: - Score Section
    private func scoreSection(_ result: EvaluationResult) -> some View {
        VStack(spacing: DS.Spacing.lg) {
            // Star score display
            VStack(spacing: DS.Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        HStack(spacing: DS.Spacing.xs) {
                            DSIcon(getInsightIcon(for: result.starScore), size: 16)
                            Text("Your Insight Level")
                                .font(DS.Typography.headline)
                                .foregroundStyle(DS.Colors.secondaryText)
                        }
                        
                        Text(result.starDescription)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.Colors.black)
                    }
                    
                    Spacer()
                    
                    // Star badge
                    ZStack {
                        Rectangle()
                            .fill(DS.Colors.black)
                            .frame(width: 80, height: 80)
                        
                        HStack(spacing: 2) {
                            ForEach(1...3, id: \.self) { star in
                                DSIcon(star <= result.starScore ? "star.fill" : "star", size: 12)
                                    .foregroundStyle(DS.Colors.white)
                            }
                        }
                    }
                }
                
                // Star progress display
                HStack(spacing: DS.Spacing.xs) {
                    Text("Insight Progress")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.secondaryText)
                    
                    Spacer()
                    
                    HStack(spacing: DS.Spacing.xxs) {
                        ForEach(1...3, id: \.self) { star in
                            DSIcon(star <= result.starScore ? "star.fill" : "star", size: 14)
                                .foregroundStyle(star <= result.starScore ? DS.Colors.black : DS.Colors.gray300)
                        }
                    }
                }
            }
            
            // Completion status
            HStack(spacing: DS.Spacing.sm) {
                DSIcon(result.pass ? "lightbulb.fill" : "arrow.clockwise", size: 24)
                
                Text(result.pass ? getCompletionText(result.starScore) : "Keep Exploring!")
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Colors.primaryText)
            }
            .dsCard()
        }
        .dsCard()
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.lg)
    }
    
    // MARK: - Response Section
    private var responseSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                Text("Your Response")
                    .font(DS.Typography.headline)
                
                Spacer()
                
                Button(action: { isResponseExpanded.toggle() }) {
                    HStack(spacing: DS.Spacing.xxs) {
                        Text(isResponseExpanded ? "Show Less" : "Show More")
                            .font(DS.Typography.caption)
                            .fontWeight(.medium)
                        
                        DSIcon(isResponseExpanded ? "chevron.up" : "chevron.down", size: 12)
                    }
                    .foregroundStyle(DS.Colors.primaryText)
                }
                .dsTertiaryButton()
            }
            
            Text(isResponseExpanded ? userResponse : truncatedResponse)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.primaryText)
                .dsSubtleCard()
                .animation(.easeInOut(duration: 0.3), value: isResponseExpanded)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.lg)
    }
    
    // MARK: - Reality Check Section
    private func realityCheckSection(_ result: EvaluationResult) -> some View {
        VStack(spacing: DS.Spacing.lg) {
            // Section header
            VStack(spacing: DS.Spacing.xs) {
                Text("Reality Check™")
                    .font(DS.Typography.title)
                    .multilineTextAlignment(.center)
                    .foregroundColor(DS.Colors.primaryText)
                
                Text("See what mastery looks like")
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, DS.Spacing.lg)
            
            // Side-by-side comparison
            VStack(spacing: 0) {
                HStack {
                    // Your Answer section
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        Text("Your Answer")
                            .font(DS.Typography.headline)
                            .foregroundStyle(DS.Colors.primaryText)
                        
                        ScrollView {
                            Text(userResponse)
                                .font(DS.Typography.body)
                                .foregroundStyle(DS.Colors.primaryText)
                                .lineLimit(nil)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 200)
                    }
                    .dsCard()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Ideal Answer section
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        Text("Ideal Answer")
                            .font(DS.Typography.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(DS.Colors.primaryText)
                        
                        ScrollView {
                            Text(result.idealAnswer ?? "")
                                .font(DS.Typography.body)
                                .foregroundStyle(DS.Colors.primaryText)
                                .lineLimit(nil)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 200)
                    }
                    .dsCard(backgroundColor: DS.Colors.secondaryBackground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(
                        Rectangle()
                            .stroke(DS.Colors.black, lineWidth: DS.BorderWidth.medium)
                    )
                }
                .padding(.horizontal, DS.Spacing.lg)
                
                // Key Gap callout
                if let keyGap = result.keyGap, !keyGap.isEmpty {
                    HStack(spacing: DS.Spacing.sm) {
                        DSIcon("exclamationmark.triangle.fill", size: 20)
                            .foregroundStyle(DS.Colors.black)
                        
                        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                            Text("Key Gap")
                                .font(DS.Typography.headline)
                                .fontWeight(.bold)
                                .foregroundStyle(DS.Colors.black)
                            
                            Text(keyGap)
                                .font(DS.Typography.body)
                                .foregroundStyle(DS.Colors.primaryText)
                                .lineLimit(nil)
                        }
                        
                        Spacer()
                    }
                    .dsCard(backgroundColor: DS.Colors.tertiaryBackground)
                    .overlay(
                        Rectangle()
                            .stroke(DS.Colors.black, lineWidth: DS.BorderWidth.medium)
                    )
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.lg)
                }
            }
        }
        .padding(.bottom, DS.Spacing.lg)
    }
    
    // MARK: - Wisdom Feedback Loading Section
    private var wisdomFeedbackLoadingSection: some View {
        VStack(spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: DS.Colors.black))
                    .scaleEffect(0.8)
                
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text("Gathering insights from different perspectives...")
                        .font(DS.Typography.body)
                        .fontWeight(.medium)
                    Text("Your personal Insight Compass")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.secondaryText)
                }
                
                Spacer()
            }
            .dsCard()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.lg)
    }
    
    // MARK: - Traditional Feedback Loading Section
    private var traditionalFeedbackLoadingSection: some View {
        VStack(spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: DS.Colors.black))
                    .scaleEffect(0.8)
                
                Text("Loading detailed analysis...")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.secondaryText)
            }
            .dsSubtleCard()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.md)
    }
    
    // MARK: - Wisdom Feedback Section
    private func wisdomFeedbackSection(_ wisdom: WisdomFeedback) -> some View {
        VStack(spacing: DS.Spacing.lg) {
            // Section header with Insight Compass vibe
            HStack {
                DSIcon("compass.drawing", size: 20)
                    .foregroundStyle(DS.Colors.black)
                
                Text("Insight Compass")
                    .font(DS.Typography.title)
                    .fontWeight(.bold)
                    .foregroundStyle(DS.Colors.primaryText)
                
                Spacer()
                
                // Compass medallion
                ZStack {
                    Rectangle()
                        .fill(DS.Colors.black)
                        .frame(width: 32, height: 32)
                    
                    DSIcon("compass.drawing", size: 12)
                        .foregroundStyle(DS.Colors.white)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            
            // Wisdom cards with special styling
            LazyVStack(spacing: DS.Spacing.lg) {
                // Wise Sage Perspective - Most prominent
                wisdomCard(
                    title: "The Wise Sage",
                    subtitle: "sees the big picture",
                    content: wisdom.wisdomOpening,
                    icon: "lightbulb.fill",
                    isHighlight: true
                )
                
                // Rational Analyst Perspective
                wisdomCard(
                    title: "The Analyst",
                    subtitle: "spots the logical gap",
                    content: wisdom.rootCause,
                    icon: "chart.line.uptrend.xyaxis.circle.fill"
                )
                
                // Caring Teacher Perspective
                wisdomCard(
                    title: "The Teacher",
                    subtitle: "shares what you need to know",
                    content: wisdom.missingFoundation,
                    icon: "book.circle.fill"
                )
                
                // Master Craftsperson Perspective
                wisdomCard(
                    title: "The Expert",
                    subtitle: "reveals the craft",
                    content: wisdom.elevatedPerspective,
                    icon: "hammer.circle.fill"
                )
                
                // Future Coach Perspective
                wisdomCard(
                    title: "The Coach",
                    subtitle: "guides your next step",
                    content: wisdom.nextLevelPrep,
                    icon: "arrow.up.forward.circle.fill"
                )
                
                // Personal Mentor Perspective - Special treatment
                wisdomCard(
                    title: "Your Mentor",
                    subtitle: "knows your style",
                    content: wisdom.personalizedWisdom,
                    icon: "person.crop.circle.fill.badge.checkmark",
                    isPersonalized: true
                )
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
        .padding(.bottom, DS.Spacing.xl)
    }
    
    // MARK: - Traditional Feedback Section (now secondary)
    private func traditionalFeedbackSection(_ feedback: AuthorFeedback) -> some View {
        VStack(spacing: DS.Spacing.lg) {
            // Section header with collapsible style
            HStack {
                DSIcon("doc.text.fill", size: 18)
                    .foregroundStyle(DS.Colors.secondaryText)
                
                Text("Detailed Analysis")
                    .font(DS.Typography.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.Colors.secondaryText)
                
                Spacer()
                
                Text("Author's Breakdown")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.tertiaryText)
                    .dsSubtleCard(padding: DS.Spacing.xs)
            }
            .padding(.horizontal, DS.Spacing.lg)
            
            // Feedback cards
            LazyVStack(spacing: DS.Spacing.md) {
                // Verdict card
                feedbackCard(
                    title: "Verdict",
                    content: feedback.verdict,
                    icon: "checkmark.shield.fill"
                )
                
                // One Big Thing card
                feedbackCard(
                    title: "One Big Thing",
                    content: feedback.oneBigThing,
                    icon: "star.fill"
                )
                
                // Evidence card
                if !feedback.evidence.isEmpty {
                    feedbackCard(
                        title: "Evidence",
                        content: feedback.evidence.joined(separator: "\n\n"),
                        icon: "doc.text.fill"
                    )
                }
                
                // Upgrade card
                if !feedback.upgrade.isEmpty {
                    feedbackCard(
                        title: "Upgrade Suggestion",
                        content: feedback.upgrade,
                        icon: "arrow.up.circle.fill"
                    )
                }
                
                // Transfer Cue card
                if !feedback.transferCue.isEmpty {
                    feedbackCard(
                        title: "Transfer Cue",
                        content: feedback.transferCue,
                        icon: "arrow.triangle.branch"
                    )
                }
                
                // Micro Drill card
                if !feedback.microDrill.isEmpty {
                    feedbackCard(
                        title: "60-Second Drill",
                        content: feedback.microDrill,
                        icon: "timer"
                    )
                }
                
                // Memory Hook card
                if !feedback.memoryHook.isEmpty {
                    feedbackCard(
                        title: "Memory Hook",
                        content: feedback.memoryHook,
                        icon: "brain.head.profile"
                    )
                }
                
                // Edge/Trap card
                if let trap = feedback.edgeOrTrap, !trap.isEmpty {
                    feedbackCard(
                        title: "Edge Case / Trap",
                        content: trap,
                        icon: "exclamationmark.triangle.fill"
                    )
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
        .padding(.bottom, DS.Spacing.lg)
    }
    
    // MARK: - Wisdom Card Helper
    private func wisdomCard(
        title: String,
        subtitle: String = "",
        content: String, 
        icon: String, 
        isHighlight: Bool = false,
        isPersonalized: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                ZStack {
                    Rectangle()
                        .fill(DS.Colors.black)
                        .frame(width: isHighlight ? 40 : 32, height: isHighlight ? 40 : 32)
                    
                    DSIcon(icon, size: isHighlight ? 20 : 16)
                        .foregroundStyle(DS.Colors.white)
                }
                
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(title)
                        .font(isHighlight ? DS.Typography.title : DS.Typography.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(DS.Colors.primaryText)
                    
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.secondaryText)
                    } else if isPersonalized {
                        Text("tailored to your thinking")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.secondaryText)
                    }
                }
                
                Spacer()
            }
            
            Text(content)
                .font(isHighlight ? DS.Typography.body : DS.Typography.body)
                .foregroundStyle(DS.Colors.primaryText)
                .lineLimit(nil)
        }
        .dsCard(
            padding: isHighlight ? DS.Spacing.lg : DS.Spacing.md,
            borderColor: DS.Colors.black,
            backgroundColor: DS.Colors.white
        )
        .overlay(
            Rectangle()
                .stroke(DS.Colors.black, lineWidth: isHighlight ? DS.BorderWidth.medium : DS.BorderWidth.thin)
        )
    }
    
    // MARK: - Feedback Card Helper
    private func feedbackCard(title: String, content: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.xs) {
                DSIcon(icon, size: 18)
                    .foregroundStyle(DS.Colors.black)
                
                Text(title)
                    .font(DS.Typography.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.Colors.primaryText)
                
                Spacer()
            }
            
            Text(content)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.primaryText)
                .lineLimit(nil)
        }
        .dsCard()
    }
    
    // MARK: - Action Section
    private func actionSection(_ result: EvaluationResult) -> some View {
        VStack(spacing: DS.Spacing.lg) {
            // Primer CTA for failed responses
            if !result.pass {
                VStack(spacing: DS.Spacing.md) {
                    HStack(spacing: DS.Spacing.sm) {
                        DSIcon("lightbulb.fill", size: 20)
                            .foregroundStyle(DS.Colors.black)
                        
                        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                            Text("Need a refresher?")
                                .font(DS.Typography.headline)
                                .fontWeight(.semibold)
                                .foregroundStyle(DS.Colors.primaryText)
                            
                            Text("Review the core concepts before continuing")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.secondaryText)
                        }
                        
                        Spacer()
                    }
                    
                    Button(action: { onOpenPrimer() }) {
                        HStack(spacing: DS.Spacing.xs) {
                            DSIcon("lightbulb", size: 18)
                            Text("Open Primer")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .dsSecondaryButton()
                }
                .dsCard(backgroundColor: DS.Colors.tertiaryBackground)
                .padding(.horizontal, DS.Spacing.lg)
            }
            
            // Continue button
            VStack(spacing: DS.Spacing.sm) {
                Button(action: { navigateToWhatThisMeans = true }) {
                    Text("Continue")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .dsPrimaryButton()
                
                Text("Your response and evaluation have been saved")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.secondaryText)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.xl)
        }
    }
    
    // MARK: - Toolbar Buttons
    private var homeButton: some View {
        Button(action: { navigateToHome = true }) {
            DSIcon("text.book.closed", size: 18)
                .foregroundStyle(DS.Colors.primaryText)
        }
        .accessibilityLabel("Go to home")
        .accessibilityHint("Return to all extracted ideas")
    }
    
    private var primerButton: some View {
        Button(action: { showingPrimer = true }) {
            DSIcon("lightbulb", size: 18)
                .foregroundStyle(DS.Colors.primaryText)
        }
        .accessibilityLabel("View Primer")
        .accessibilityHint("Open primer for this idea")
    }
    
    // MARK: - Private Methods
    
    private func loadEvaluation() {
        isLoadingEvaluation = true
        evaluationError = nil
        Task {
            do {
                let result = try await evaluationService.evaluateSubmission(
                    idea: idea,
                    userResponse: userResponse,
                    level: level,
                    prompt: prompt
                )
                
                // Save the response immediately when evaluation is complete
                do {
                    _ = try await userResponseService.saveUserResponseWithEvaluation(
                        ideaId: idea.id,
                        level: level,
                        prompt: prompt,
                        response: userResponse,
                        evaluation: result
                    )
                } catch {
                    print("DEBUG: Failed to save response when feedback loaded: \(error)")
                    // Don't fail the whole flow if saving fails, just log the error
                }
                
                await MainActor.run {
                    self.evaluationResult = result
                    self.isLoadingEvaluation = false
                    // Insight compass is now included in result.insightCompass
                }
            } catch {
                await MainActor.run {
                    let errorMessage = getErrorMessage(for: error)
                    self.evaluationError = errorMessage
                    self.isLoadingEvaluation = false
                }
            }
        }
    }
    
    private func loadWisdomFeedback(result: EvaluationResult) async {
        await MainActor.run {
            self.isLoadingWisdomFeedback = true
        }
        
        do {
            let wisdom = try await evaluationService.generateWisdomFeedback(
                idea: idea,
                userResponse: userResponse,
                level: level,
                evaluationResult: result
            )
            await MainActor.run {
                self.wisdomFeedback = wisdom
                self.isLoadingWisdomFeedback = false
            }
        } catch {
            await MainActor.run {
                self.wisdomFeedbackError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.wisdomFeedback = nil
                self.isLoadingWisdomFeedback = false
            }
        }
    }
    
    private func loadStructuredFeedback(result: EvaluationResult) async {
        await MainActor.run {
            self.isLoadingStructuredFeedback = true
        }
        
        do {
            let fb = try await evaluationService.generateStructuredFeedback(
                idea: idea,
                userResponse: userResponse,
                level: level,
                evaluationResult: result
            )
            await MainActor.run {
                self.authorFeedback = fb
                self.isLoadingStructuredFeedback = false
            }
        } catch {
            await MainActor.run {
                self.structuredFeedbackError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.authorFeedback = nil
                self.isLoadingStructuredFeedback = false
            }
        }
    }
    
    
    // MARK: - Star System Helpers
    
    private func getStarColor(_ starScore: Int) -> Color {
        switch starScore {
        case 1: return DS.Colors.black
        case 2: return DS.Colors.black
        case 3: return DS.Colors.black
        default: return DS.Colors.gray500
        }
    }
    
    private func getCompletionText(_ starScore: Int) -> String {
        switch starScore {
        case 1: return "Keep Going!"
        case 2: return "Well Done!"
        case 3: return "Aha! Moment!"
        default: return "Complete!"
        }
    }
    
    // MARK: - Icon Helpers
    
    private func getLevelIcon(for level: Int) -> String {
        switch level {
        case 1: return "1.circle.fill"
        case 2: return "2.circle.fill" 
        case 3: return "3.circle.fill"
        default: return "circle.fill"
        }
    }
    
    private func getInsightIcon(for starScore: Int) -> String {
        switch starScore {
        case 1: return "lightbulb"
        case 2: return "lightbulb.fill"
        case 3: return "brain.head.profile"
        default: return "lightbulb"
        }
    }
    
    // MARK: - Helper Methods
    
    private func getErrorMessage(for error: Error) -> String {
        if let evaluationError = error as? EvaluationError {
            switch evaluationError {
            case .networkError:
                return "Network connection issue. Please check your internet connection and try again."
            case .timeout:
                return "Request timed out. Please try again - this usually resolves on retry."
            case .rateLimitExceeded:
                return "Service is busy right now. Please wait a moment and try again."
            case .serverError(let code):
                return "Server error (\(code)). Please try again in a moment."
            case .noResponse:
                return "No response received. Please try again."
            case .decodingError:
                return "Response format error. Please try again."
            case .invalidResponse:
                return "Invalid response from server. Please try again."
            case .invalidEvaluationFormat:
                return "Evaluation format error. Please try again."
            }
        }
        
        // Fallback for other errors
        return "Failed to evaluate response: \(error.localizedDescription)"
    }
}

#Preview {
    NavigationStack {
        EvaluationResultsView(
            idea: Idea(
                id: "i1",
                title: "Norman Doors",
                description: "The mind fills in blanks. But what if the blanks are the most important part?",
                bookTitle: "The Design of Everyday Things",
                depthTarget: 2,
                masteryLevel: 0,
                lastPracticed: nil,
                currentLevel: nil
            ),
            userResponse: "This is my response about Norman Doors...",
            prompt: "What is the design principle behind Norman Doors?",
            level: 1,
            onOpenPrimer: {}
        )
    }
}