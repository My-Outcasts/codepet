// codepet/Models/ISOTime.swift
import Foundation

/// One canonical UTC ISO-8601 timestamp for stored records. Default
/// `ISO8601DateFormatter` options = UTC `Z`, no fractional seconds — so
/// lexicographic string order equals chronological order (the Library sort relies
/// on this). Use for every `Deliverable.createdAt`.
enum ISOTime {
    private static let formatter = ISO8601DateFormatter()

    static func utc(_ date: Date) -> String {
        formatter.string(from: date)
    }
}
