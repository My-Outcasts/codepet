// codepet/Models/Plan.swift
import Foundation

/// Static plan copy for the Settings billing card. No live usage tracking (no billing
/// backend yet); mirrors the credits pricing (Trial → Pro).
enum Plan: CaseIterable {
    case trial, pro

    func title(_ lang: AppLanguage) -> String {
        switch self {
        case .trial: return lang == .vi ? "Dùng thử" : "Trial"
        case .pro:   return "Pro"
        }
    }
    func priceLine(_ lang: AppLanguage) -> String {
        switch self {
        case .trial: return lang == .vi ? "Miễn phí · 7 ngày" : "Free · 7 days"
        case .pro:   return lang == .vi ? "$20/tháng" : "$20/mo"
        }
    }
    func creditsLine(_ lang: AppLanguage) -> String {
        switch self {
        case .trial: return lang == .vi ? "~150 tín dụng" : "~150 credits"
        case .pro:   return lang == .vi ? "800 tín dụng/tháng · vượt mức $0.05/tín dụng"
                                        : "800 credits/mo · overage $0.05/credit"
        }
    }
}
