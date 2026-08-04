// codepet/Models/DepartmentSectionHeader.swift
import Foundation

/// The "WHAT NEEDS DOING" header on a department page, with the progress count appended only
/// when that count carries information.
///
/// An untouched department reads bare: "1 of 1 left" tells the founder nothing they can't see in
/// the list below it. A department with anything delivered reads "· N of M done" — including a
/// FULLY done one, where dropping the count left the header contradicting both the "All clear"
/// pulse line above it and the delivered rows beneath it.
///
/// Pure and free of view types for the same reason `departmentPulse` is: this string is a
/// product decision with a plural and a translation, and it should be assertable without
/// standing up a `View`.
func departmentSectionHeader(tasks: [RoadmapTask], lang: AppLanguage) -> String {
    let base = (lang == .vi ? "Việc cần làm" : "What needs doing").uppercased()
    let done = tasks.filter(\.done).count
    guard done > 0 else { return base }
    return base + (lang == .vi ? " · \(done)/\(tasks.count) đã xong"
                               : " · \(done) of \(tasks.count) done")
}
