import Foundation

/// SM-2 spaced repetition (SPEC §11). Pure and deterministic given a clock.
///
/// Grade → SM-2 quality: again=2 (fail), hard=3, good=4, easy=5.
/// `again` resets the repetition streak and makes the card due immediately;
/// passing grades advance 1 → 6 → round(previousInterval × easeFactor) days.
public enum SM2 {

    private static func quality(_ grade: ReviewGrade) -> Int {
        switch grade {
        case .again: return 2
        case .hard: return 3
        case .good: return 4
        case .easy: return 5
        }
    }

    /// Computes the next interval (in days) and ease factor from the current
    /// values and a grade. Does not touch dates.
    public static func project(easeFactor: Double, interval: Int, reviewCount: Int,
                               grade: ReviewGrade) -> (easeFactor: Double, interval: Int, reviewCount: Int) {
        let q = quality(grade)
        var ef = easeFactor + (0.1 - Double(5 - q) * (0.08 + Double(5 - q) * 0.02))
        if ef < 1.3 { ef = 1.3 }

        if grade == .again {
            return (ef, 0, 0)   // due immediately, streak reset
        }

        let newCount = reviewCount + 1
        let newInterval: Int
        switch newCount {
        case 1: newInterval = 1
        case 2: newInterval = 6
        default: newInterval = max(1, Int((Double(interval) * ef).rounded()))
        }
        return (ef, newInterval, newCount)
    }

    /// Returns the updated `ReviewState` after grading at `now`.
    public static func schedule(_ state: ReviewState, grade: ReviewGrade,
                                now: Date = Date(), calendar: Calendar = .current) -> ReviewState {
        let p = project(easeFactor: state.easeFactor, interval: state.interval,
                        reviewCount: state.reviewCount, grade: grade)
        var updated = state
        updated.easeFactor = p.easeFactor
        updated.interval = p.interval
        updated.reviewCount = p.reviewCount
        updated.lastReview = now
        updated.dueDate = calendar.date(byAdding: .day, value: p.interval, to: now) ?? now
        return updated
    }

    /// Interval (days) that each grade would produce, for button preview labels.
    public static func intervalPreview(_ state: ReviewState) -> [ReviewGrade: Int] {
        var preview: [ReviewGrade: Int] = [:]
        for grade in ReviewGrade.allCases {
            preview[grade] = project(easeFactor: state.easeFactor, interval: state.interval,
                                     reviewCount: state.reviewCount, grade: grade).interval
        }
        return preview
    }
}
