// EvaluationPrompts.swift
import Foundation

enum EvalLevel: String { case L1, L2, L3 }

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
        case .L1: return "L1: Why it matters - user must understand the significance and core importance of the idea."
        case .L2: return "L2: When to use - user must identify triggers and application contexts for the idea."
        case .L3: return "L3: How to wield - user must demonstrate creative or critical extension of the idea."
        }
    }
} 