# Two-Step Sequential Analysis Implementation

## Overview

This implementation provides a two-step, sequential process for analyzing books that maintains 100% compatibility with the existing legacy system. The process uses two AI prompts in sequence to provide better context and more intelligent idea extraction while ensuring the final output remains in the expected string format.

## Implementation Details

### 1. Two Prompt Templates

#### PROMPT_1_TEMPLATE (Blueprint Extraction)
- **Purpose**: Extract the book's central thesis and major structural parts
- **Input**: Book title
- **Output**: JSON object with `central_thesis` and `major_parts` array
- **Role**: Provides context for the second prompt

#### PROMPT_2_TEMPLATE (Idea Deconstruction & Legacy Formatting)
- **Purpose**: Extract teachable ideas and format them according to legacy specifications
- **Input**: Book title + blueprint result from step 1
- **Output**: JSON array of strings in legacy format
- **Role**: Performs the actual idea extraction with blueprint context

### 2. Main Function: `analyzeBookForLegacy(bookTitle: String)`

This function orchestrates the two-step process:

1. **Step 1**: Calls `runBlueprintPrompt()` to get the book's blueprint
2. **Step 2**: Calls `runDeconstructionPrompt()` with the blueprint as context
3. **Returns**: JSON array of strings in legacy format

### 3. Integration with Existing System

- **IdeaExtractionViewModel**: Updated to use `analyzeBookForLegacy()` instead of the old `extractIdeas()`
- **Backward Compatibility**: Maintains the same string format: `"id | title — explanation | depth_target"`
- **Database Integration**: Works seamlessly with existing BookService and data models

## File Changes

### Modified Files:
1. **OpenAIService.swift**
   - Added `PROMPT_1_TEMPLATE` and `PROMPT_2_TEMPLATE` constants
   - Added `analyzeBookForLegacy()` function
   - Added `performAnalyzeBookForLegacy()` helper function
   - Added `runBlueprintPrompt()` and `runDeconstructionPrompt()` methods
   - Added `makeAPIRequest()` helper method
   - Maintained existing `extractIdeas()` method for backward compatibility

2. **IdeaExtractionViewModel.swift**
   - Updated `extractIdeas()` method to call `analyzeBookForLegacy()`
   - Updated debug messages to reflect two-step process
   - Maintained all existing error handling and fallback logic

### New Files:
1. **TestTwoStepAnalysis.swift** - Test file for verification
2. **TWO_STEP_ANALYSIS_IMPLEMENTATION.md** - This documentation

## Usage

The implementation is automatically used when the app analyzes a book. The frontend calls the existing `loadOrExtractIdeas()` method, which now uses the new two-step analysis internally.

### Example Usage:
```swift
let openAIService = OpenAIService(apiKey: "your-api-key")
let ideas = try await openAIService.analyzeBookForLegacy(bookTitle: "Atomic Habits")
// Returns: ["i1 | Habit Stacking — Link new habits to existing ones. | 2", ...]
```

## Benefits

1. **Better Context**: The blueprint provides structural understanding of the book
2. **Improved Quality**: Two-step process leads to more coherent and relevant ideas
3. **Legacy Compatibility**: Maintains exact string format expected by existing system
4. **Error Handling**: Includes retry logic and fallback mechanisms
5. **Debugging**: Comprehensive logging for troubleshooting

## Error Handling

- **Network Errors**: Automatic retry with exponential backoff
- **API Errors**: Proper error propagation with descriptive messages
- **Parsing Errors**: Graceful handling of malformed responses
- **Fallback**: Falls back to existing ideas if analysis fails

## Testing

The implementation includes:
- Debug logging at each step
- Error handling and validation
- Test file for verification
- Maintains existing test coverage

## Future Enhancements

Potential improvements:
1. Cache blueprint results for reuse
2. Add more sophisticated error recovery
3. Implement parallel processing for multiple books
4. Add metrics and analytics for analysis quality

## Conclusion

This implementation successfully provides a more intelligent two-step analysis process while maintaining complete compatibility with the existing system. The frontend will automatically benefit from improved idea extraction without requiring any changes to the UI or data handling logic. 