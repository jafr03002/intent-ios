import Foundation

// Port of formatSplitType from lib/utils.ts (the rest of utils.ts is Tailwind glue).

public enum SplitType {
    /// Display form of a program's splitType: underscores/hyphens become spaces and
    /// all-lowercase words get a capital ("push_pull_legs" -> "Push Pull Legs");
    /// already-cased words ("PPL", "U/L") are left alone.
    ///
    /// NOTE (ported faithfully): a value with no words at all ("", "__") comes back
    /// as the literal string "undefined" - JS's `word[0]?.toUpperCase() + ...` on an
    /// empty word.
    public static func format(_ splitType: String) -> String {
        var replaced = ""
        var inRun = false
        for u in splitType.unicodeScalars {
            if u == "_" || u == "-" {
                if !inRun { replaced.append(" ") }
                inRun = true
            } else {
                replaced.unicodeScalars.append(u)
                inRun = false
            }
        }
        let trimmed = JS.trim(replaced)
        return ExerciseLibrary.splitOnWhitespace(trimmed).map { word -> String in
            guard word == word.lowercased() else { return word }
            // JS `word[0]` is one UTF-16 unit; fine for the BMP letters this sees.
            guard let first = word.unicodeScalars.first else { return "undefined" }
            return String(first).uppercased() + String(String.UnicodeScalarView(word.unicodeScalars.dropFirst()))
        }.joined(separator: " ")
    }
}
