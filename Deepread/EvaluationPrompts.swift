// EvaluationPrompts.swift
import Foundation

enum EvalLevel: String { case L0, L1, L2, L3 }

struct EvaluationPrompts {
    static func feedbackPrompt(
        ideaTitle: String,
        ideaDescription: String,
        userResponse: String,
        level: EvalLevel
    ) -> String {
        """
        You are the author evaluating the reader's response about "\(ideaTitle)".

        SOURCE (verbatim, no external info):
        \(ideaDescription)

        READER RESPONSE:
        \(userResponse)

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
        - \(levelRule(level))
        - If response is vague, reduce score and include a concrete gap.
        - Keep "silver_bullet" specific to THIS response.

        STYLE:
        - Authorial voice, concise, no fluff.
        - No markdown. JSON only.
        """
    }

    private static func levelRule(_ level: EvalLevel) -> String {
        switch level {
        case .L0: return "L0: Basic understanding: definitions and main claim must be correct."
        case .L1: return "L1: Understanding + why it matters; detect a correct causal link or implication."
        case .L2: return "L2: Application to a new scenario; evaluate if the application is faithful to the idea."
        case .L3: return "L3 (Final Boss): Creative/critical wielding; catch tradeoffs/edge-cases without inventing facts."
        }
    }
} 