import Foundation

/// Glasses of water logged today. The count starts over each calendar day.
enum WaterLog {
    static let dailyGoal = 8

    private static let countKey = "waterCount"
    private static let dayKey = "waterDay"

    static var today: Int {
        let d = UserDefaults.standard
        return d.string(forKey: dayKey) == dayStamp() ? d.integer(forKey: countKey) : 0
    }

    @discardableResult
    static func addGlass() -> Int {
        let count = today + 1
        UserDefaults.standard.set(dayStamp(), forKey: dayKey)
        UserDefaults.standard.set(count, forKey: countKey)
        return count
    }

    private static func dayStamp(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
