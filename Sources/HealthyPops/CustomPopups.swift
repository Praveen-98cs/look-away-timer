import Foundation
import SwiftUI

/// A user-made reminder that shows as a nudge every `intervalMinutes` of screen time.
struct CustomPopup: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    var message: String
    var symbol: String
    var colorIndex: Int
    var intervalMinutes: Int
    var enabled = true

    static let intervalRange = 5...240
    static let symbols = [
        "bell.fill", "heart.fill", "leaf.fill", "sun.max.fill", "moon.fill", "star.fill",
        "bolt.fill", "brain.head.profile", "lungs.fill", "figure.walk", "figure.mind.and.body",
        "hand.raised.fill", "cup.and.saucer.fill", "fork.knife", "pills.fill", "music.note",
    ]
    static let palettes: [(name: String, colors: [Color])] = [
        ("Pink", [Palette.pink, Palette.peach]),
        ("Mint", [Palette.mint, Palette.teal]),
        ("Blue", [Palette.water, Color(hex: 0x3D7BF5)]),
        ("Violet", [Color(hex: 0xB18CFF), Color(hex: 0x6A4CF0)]),
        ("Sun", [Color(hex: 0xFFD25A), Color(hex: 0xFF8A3D)]),
        ("Green", [Color(hex: 0x9BE15D), Color(hex: 0x2FB67C)]),
    ]

    static func draft() -> CustomPopup {
        CustomPopup(title: "", message: "", symbol: symbols[0], colorIndex: 3, intervalMinutes: 30)
    }

    var colors: [Color] { Self.palettes[min(max(colorIndex, 0), Self.palettes.count - 1)].colors }

    var intervalLabel: String {
        intervalMinutes % 60 == 0 && intervalMinutes >= 60
            ? "every \(intervalMinutes / 60) h"
            : "every \(intervalMinutes) min"
    }
}

/// Saved custom popups (UserDefaults, JSON).
final class CustomPopupStore {
    static let shared = CustomPopupStore()
    private static let key = "customPopups"

    private(set) var popups: [CustomPopup] = []
    var onChange: (() -> Void)?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([CustomPopup].self, from: data) {
            popups = saved
        }
    }

    func popup(id: UUID) -> CustomPopup? { popups.first { $0.id == id } }

    func upsert(_ popup: CustomPopup) {
        if let i = popups.firstIndex(where: { $0.id == popup.id }) {
            popups[i] = popup
        } else {
            popups.append(popup)
        }
        save()
    }

    func remove(id: UUID) {
        popups.removeAll { $0.id == id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(popups) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
        onChange?()
    }
}
