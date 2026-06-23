import SwiftUI

// MARK: - Pixel Art Icon Shapes

/// A small pixel-art trophy drawn with rectangles
struct PixelTrophy: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        let p = size / 9
        Canvas { ctx, _ in
            // Cup top rim
            ctx.fill(Path(CGRect(x: p, y: 0, width: p * 7, height: p)), with: .color(color))
            // Cup body
            ctx.fill(Path(CGRect(x: p, y: p, width: p * 7, height: p * 3)), with: .color(color))
            // Handles
            ctx.fill(Path(CGRect(x: 0, y: p, width: p, height: p * 2)), with: .color(color))
            ctx.fill(Path(CGRect(x: p * 8, y: p, width: p, height: p * 2)), with: .color(color))
            // Taper
            ctx.fill(Path(CGRect(x: p * 2, y: p * 4, width: p * 5, height: p)), with: .color(color))
            // Stem
            ctx.fill(Path(CGRect(x: p * 3, y: p * 5, width: p * 3, height: p * 2)), with: .color(color))
            // Base
            ctx.fill(Path(CGRect(x: p * 2, y: p * 7, width: p * 5, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: p, y: p * 8, width: p * 7, height: p)), with: .color(color))
        }
        .frame(width: size, height: size)
    }
}

/// A small pixel-art star
struct PixelStar: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        let p = size / 9
        Canvas { ctx, _ in
            ctx.fill(Path(CGRect(x: p * 4, y: 0, width: p, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: p * 3, y: p, width: p * 3, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: p * 2, y: p * 2, width: p * 5, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: 0, y: p * 3, width: p * 9, height: p * 2)), with: .color(color))
            ctx.fill(Path(CGRect(x: p, y: p * 5, width: p * 7, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: p * 2, y: p * 6, width: p * 5, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: p, y: p * 7, width: p * 3, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: p * 5, y: p * 7, width: p * 3, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: 0, y: p * 8, width: p * 2, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: p * 7, y: p * 8, width: p * 2, height: p)), with: .color(color))
        }
        .frame(width: size, height: size)
    }
}

/// A pixel-art flame
struct PixelFlame: View {
    let color: Color
    let tipColor: Color
    let size: CGFloat

    var body: some View {
        let p = size / 9
        Canvas { ctx, _ in
            ctx.fill(Path(CGRect(x: p * 4, y: 0, width: p, height: p)), with: .color(tipColor))
            ctx.fill(Path(CGRect(x: p * 3, y: p, width: p * 3, height: p)), with: .color(tipColor))
            ctx.fill(Path(CGRect(x: p * 3, y: p * 2, width: p * 4, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: p * 2, y: p * 3, width: p * 5, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: p * 2, y: p * 4, width: p * 6, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: p, y: p * 5, width: p * 7, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: p, y: p * 6, width: p * 7, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: p * 2, y: p * 7, width: p * 5, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: p * 3, y: p * 8, width: p * 3, height: p)), with: .color(color))
        }
        .frame(width: size, height: size)
    }
}

/// A pixel-art lightning bolt
struct PixelBolt: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        let p = size / 9
        Canvas { ctx, _ in
            ctx.fill(Path(CGRect(x: p * 4, y: 0, width: p * 3, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: p * 3, y: p, width: p * 3, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: p * 2, y: p * 2, width: p * 3, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: p, y: p * 3, width: p * 6, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: p * 3, y: p * 4, width: p * 5, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: p * 4, y: p * 5, width: p * 3, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: p * 3, y: p * 6, width: p * 3, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: p * 2, y: p * 7, width: p * 3, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: p * 2, y: p * 8, width: p * 2, height: p)), with: .color(color))
        }
        .frame(width: size, height: size)
    }
}

/// A pixel-art book
struct PixelBook: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        let p = size / 9
        Canvas { ctx, _ in
            let spine = color.opacity(0.7)
            ctx.fill(Path(CGRect(x: p, y: 0, width: p * 7, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: 0, y: p, width: p * 8, height: p * 6)), with: .color(color))
            ctx.fill(Path(CGRect(x: 0, y: p, width: p, height: p * 6)), with: .color(spine))
            ctx.fill(Path(CGRect(x: p, y: p * 7, width: p * 7, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: 0, y: p * 8, width: p * 8, height: p)), with: .color(spine))
        }
        .frame(width: size, height: size)
    }
}

/// A pixel-art crosshair/target
struct PixelTarget: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        let p = size / 9
        Canvas { ctx, _ in
            // Outer ring
            ctx.fill(Path(CGRect(x: p * 2, y: 0, width: p * 5, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: p, y: p, width: p * 2, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: p * 6, y: p, width: p * 2, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: 0, y: p * 2, width: p, height: p * 5)), with: .color(color))
            ctx.fill(Path(CGRect(x: p * 8, y: p * 2, width: p, height: p * 5)), with: .color(color))
            ctx.fill(Path(CGRect(x: p, y: p * 7, width: p * 2, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: p * 6, y: p * 7, width: p * 2, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: p * 2, y: p * 8, width: p * 5, height: p)), with: .color(color))
            // Center dot
            ctx.fill(Path(CGRect(x: p * 4, y: p * 4, width: p, height: p)), with: .color(color))
        }
        .frame(width: size, height: size)
    }
}

/// A pixel-art map/scroll icon
struct PixelMap: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        let p = size / 9
        Canvas { ctx, _ in
            ctx.fill(Path(CGRect(x: p, y: 0, width: p * 7, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: 0, y: p, width: p * 9, height: p * 6)), with: .color(color))
            // Path line
            ctx.fill(Path(CGRect(x: p * 2, y: p * 3, width: p, height: p)), with: .color(.white.opacity(0.5)))
            ctx.fill(Path(CGRect(x: p * 3, y: p * 4, width: p * 2, height: p)), with: .color(.white.opacity(0.5)))
            ctx.fill(Path(CGRect(x: p * 5, y: p * 3, width: p, height: p)), with: .color(.white.opacity(0.5)))
            ctx.fill(Path(CGRect(x: p * 6, y: p * 2, width: p, height: p)), with: .color(.white.opacity(0.5)))
            ctx.fill(Path(CGRect(x: p, y: p * 7, width: p * 7, height: p)), with: .color(color))
            ctx.fill(Path(CGRect(x: p * 2, y: p * 8, width: p * 5, height: p)), with: .color(color))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Pixel Card Border Modifier

struct PixelCardStyle: ViewModifier {
    var borderColor: Color = Color(hex: "#E0DBEF")

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Shadow layer (pixel offset)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: "#2D2B3E").opacity(0.06))
                        .offset(x: 2, y: 2)
                    // Card face
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: "#F7F5FC"))
                    // Pixel border
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(borderColor, lineWidth: 1.5)
                }
            )
    }
}

extension View {
    func pixelCard(borderColor: Color = Color(hex: "#E0DBEF")) -> some View {
        modifier(PixelCardStyle(borderColor: borderColor))
    }
}

// MARK: - Color Palette for mixed icons
struct InsightColors {
    static let orange = Color(hex: "#F0922B")
    static let gold = Color(hex: "#ECBA2A")
    static let green = Color(hex: "#5EC26A")
    static let red = Color(hex: "#E06050")
    static let blue = Color(hex: "#4A9FE5")
    static let purple = Color(hex: "#8B7BE8")
    static let teal = Color(hex: "#3DC0B0")
    static let pink = Color(hex: "#E07BAD")
}

// MARK: - Main View

struct InsightsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var mcpBridge: MCPBridgeService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("◆ CODEPET")
                        .font(.pixelSystem(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(hex: "#8B7BE8"))
                    Text("Your Progress")
                        .font(.pixelSystem(size: 26, weight: .bold))
                        .foregroundColor(Color(hex: "#2D2B3E"))
                    Text("Track your learning journey — one pixel at a time.")
                        .font(.pixelSystem(size: 13))
                        .foregroundColor(Color(hex: "#2D2B3E").opacity(0.55))
                }

                // Weekly Stats
                PixelWeeklyStats()

                // Streak Calendar
                PixelStreakCalendar()

                // ═══ MCP: Today's Coding Summary ═══
                MCPCodingSummarySection()

                // Statistics Grid
                PixelStatisticsGrid()

                // ═══ MCP: Skill Tree Progress ═══
                MCPSkillTreeSection()

                // Activity Breakdown (enriched with MCP data)
                PixelActivityBreakdown()
            }
            .padding(24)
        }
        .background(Color(hex: "#F0EDF8"))
        .onAppear {
            mcpBridge.refresh()
        }
    }
}

// MARK: - MCP: Today's Coding Summary

struct MCPCodingSummarySection: View {
    @EnvironmentObject var mcpBridge: MCPBridgeService
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section label with source badge
            HStack(spacing: 6) {
                Text("TODAY'S CODING")
                    .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#2D2B3E").opacity(0.4))

                if mcpBridge.dataSource == "extension" {
                    Text("CURSOR")
                        .font(.pixelSystem(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(hex: "#00B4D8"))
                        .cornerRadius(3)
                } else if mcpBridge.dataSource == "local" {
                    Text("MCP")
                        .font(.pixelSystem(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(hex: "#8B7BE8"))
                        .cornerRadius(3)
                }
            }

            // Use real data if available, otherwise show demo
            let displaySummary = mcpBridge.todaySummary ?? Self.demoSummary
            let displayXP = mcpBridge.isConnected ? mcpBridge.totalSkillXP : 515
            let isDemo = mcpBridge.dataSource == "none"

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    MCPStatChip(value: formatMinutes(displaySummary.totalCodingMinutes), label: "Coding Time", color: InsightColors.purple)
                    MCPStatChip(value: "\(displaySummary.linesAdded + displaySummary.linesRemoved)", label: "Lines Changed", color: InsightColors.blue)
                    MCPStatChip(
                        value: "\(displaySummary.commits)",
                        label: mcpBridge.dataSource == "extension" ? "Edits" : "Commits",
                        color: InsightColors.green
                    )
                }

                HStack(spacing: 10) {
                    MCPStatChip(value: "\(displaySummary.errorsFixed)", label: "Bugs Fixed", color: InsightColors.orange)
                    MCPStatChip(
                        value: "\(displaySummary.aiSessions)",
                        label: mcpBridge.dataSource == "extension" ? "Files Edited" : "AI Sessions",
                        color: InsightColors.red
                    )
                    MCPStatChip(value: "+\(displayXP)", label: "Coding XP", color: InsightColors.gold)
                }

                // Language breakdown bar
                if !displaySummary.languageBreakdown.isEmpty {
                    MCPLanguageBar(breakdown: displaySummary.languageBreakdown)
                }

                // Pet reaction
                if let reaction = displaySummary.petReaction {
                    MCPPetReaction(petName: petName, reaction: reaction)
                }

                // Source indicator
                if isDemo {
                    Text("Preview — install the Cursor extension to see live coding data")
                        .font(.pixelSystem(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(hex: "#8B7BE8").opacity(0.6))
                        .padding(.top, 2)
                } else if mcpBridge.dataSource == "extension" {
                    Text("Live from Cursor extension")
                        .font(.pixelSystem(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(hex: "#00B4D8").opacity(0.7))
                        .padding(.top, 2)
                }
            }
            .padding(14)
            .pixelCard(borderColor: InsightColors.purple.opacity(0.3))
        }
    }

    // Demo data shown when MCP server is not connected
    static let demoSummary = MCPDailySummary(
        date: "2026-04-08",
        totalCodingMinutes: 185,
        linesAdded: 1247,
        linesRemoved: 89,
        commits: 4,
        aiSessions: 3,
        errorsFixed: 5,
        languageBreakdown: ["Swift": 65, "TypeScript": 28, "HTML": 7],
        skillsTracked: ["Swift Basics": 180, "Functions": 120, "Data Types": 90],
        topFiles: ["InsightsView.swift", "MCPBridgeService.swift", "extension.ts"],
        petReaction: "You're building something amazing today!"
    )

    private var petName: String {
        PetCharacter.all[appState.activeChar]?.name ?? "Nova"
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
        return "\(minutes)m"
    }
}

// MARK: - MCP Stat Chip

struct MCPStatChip: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.pixelSystem(size: 16, weight: .black, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.pixelSystem(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "#2D2B3E").opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.06))
        .cornerRadius(6)
    }
}

// MARK: - MCP Language Breakdown Bar

struct MCPLanguageBar: View {
    let breakdown: [String: Int]

    private var sortedLanguages: [(String, Int)] {
        breakdown.sorted { $0.value > $1.value }
    }

    private var total: Int {
        breakdown.values.reduce(0, +)
    }

    private let langColors: [String: Color] = [
        "Swift": Color(hex: "#F05138"),
        "TypeScript": Color(hex: "#3178C6"),
        "JavaScript": Color(hex: "#F7DF1E"),
        "Python": Color(hex: "#3776AB"),
        "JSON": Color(hex: "#5BBD6B"),
        "HTML": Color(hex: "#E34F26"),
        "CSS": Color(hex: "#1572B6"),
        "Shell": Color(hex: "#89E051"),
        "Rust": Color(hex: "#DEA584"),
        "Go": Color(hex: "#00ADD8"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Segmented bar
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(sortedLanguages, id: \.0) { lang, count in
                        let fraction = total > 0 ? CGFloat(count) / CGFloat(total) : 0
                        RoundedRectangle(cornerRadius: 2)
                            .fill(langColors[lang] ?? InsightColors.purple)
                            .frame(width: max(4, geo.size.width * fraction))
                    }
                }
            }
            .frame(height: 8)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Legend
            HStack(spacing: 10) {
                ForEach(sortedLanguages.prefix(4), id: \.0) { lang, count in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(langColors[lang] ?? InsightColors.purple)
                            .frame(width: 6, height: 6)
                        Text(lang)
                            .font(.pixelSystem(size: 9, weight: .semibold))
                            .foregroundColor(Color(hex: "#2D2B3E").opacity(0.5))
                        if total > 0 {
                            Text("\(count * 100 / total)%")
                                .font(.pixelSystem(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "#2D2B3E").opacity(0.3))
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - MCP Pet Reaction

struct MCPPetReaction: View {
    let petName: String
    let reaction: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Pet avatar
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: "#8B7BE8"))
                    .frame(width: 36, height: 36)
                Text("⭐")
                    .font(.pixelSystem(size: 18))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(petName) says:")
                    .font(.pixelSystem(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#8B7BE8"))
                Text(reaction)
                    .font(.pixelSystem(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "#2D2B3E").opacity(0.7))
                    .lineLimit(3)
            }
        }
        .padding(10)
        .background(Color(hex: "#8B7BE8").opacity(0.06))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(hex: "#8B7BE8").opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - MCP: Skill Tree Section

struct MCPSkillTreeSection: View {
    @EnvironmentObject var mcpBridge: MCPBridgeService

    // Demo skills shown when MCP is not connected
    static let demoSkills: [MCPSkillProgress] = [
        MCPSkillProgress(id: "swift-basics", name: "Swift Basics", icon: "🔥", kingdom: "The Molten Forge", tier: 1, nodeType: "core", xp: 180, level: 3, maxLevel: 5, xpProgress: 180, xpToNextLevel: 250),
        MCPSkillProgress(id: "functions", name: "Functions", icon: "⚡", kingdom: "The Molten Forge", tier: 1, nodeType: "core", xp: 120, level: 2, maxLevel: 5, xpProgress: 120, xpToNextLevel: 200),
        MCPSkillProgress(id: "data-types", name: "Data Types", icon: "❄️", kingdom: "The Frozen Spire", tier: 2, nodeType: "core", xp: 90, level: 2, maxLevel: 5, xpProgress: 90, xpToNextLevel: 200),
        MCPSkillProgress(id: "arrays", name: "Collections", icon: "❄️", kingdom: "The Frozen Spire", tier: 2, nodeType: "core", xp: 45, level: 1, maxLevel: 5, xpProgress: 45, xpToNextLevel: 150),
        MCPSkillProgress(id: "control-flow", name: "Control Flow", icon: "🌿", kingdom: "The Eternal Garden", tier: 3, nodeType: "core", xp: 60, level: 1, maxLevel: 5, xpProgress: 60, xpToNextLevel: 150),
        MCPSkillProgress(id: "protocols", name: "Protocols", icon: "🔮", kingdom: "The Mystic Grove", tier: 4, nodeType: "advanced", xp: 40, level: 1, maxLevel: 5, xpProgress: 40, xpToNextLevel: 150),
    ]

    private var displaySkills: [MCPSkillProgress] {
        mcpBridge.skillProgress.isEmpty ? Self.demoSkills : mcpBridge.skillProgress
    }

    private var skillsByKingdom: [(String, [MCPSkillProgress])] {
        var grouped: [String: [MCPSkillProgress]] = [:]
        for skill in displaySkills {
            grouped[skill.kingdom, default: []].append(skill)
        }
        // Sort kingdoms by tier
        let order = ["The Molten Forge", "The Frozen Spire", "The Eternal Garden", "The Mystic Grove"]
        return order.compactMap { kingdom in
            guard let skills = grouped[kingdom] else { return nil }
            return (kingdom, skills)
        }
    }

    private let kingdomColors: [String: Color] = [
        "The Molten Forge": Color(hex: "#E85D3A"),
        "The Frozen Spire": Color(hex: "#4FA8D6"),
        "The Eternal Garden": Color(hex: "#5BBD6B"),
        "The Mystic Grove": Color(hex: "#9B6DD7"),
    ]

    private let kingdomIcons: [String: String] = [
        "The Molten Forge": "🔥",
        "The Frozen Spire": "❄️",
        "The Eternal Garden": "🌿",
        "The Mystic Grove": "✨",
    ]

    private let kingdomTiers: [String: String] = [
        "The Molten Forge": "Tier 1 — Foundations",
        "The Frozen Spire": "Tier 2 — Context",
        "The Eternal Garden": "Tier 3 — Advanced",
        "The Mystic Grove": "Tier 4 — Expert",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("SKILL TREE")
                    .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#2D2B3E").opacity(0.4))

                if !mcpBridge.skillProgress.isEmpty {
                    Text(mcpBridge.dataSource == "extension" ? "CURSOR" : "MCP")
                        .font(.pixelSystem(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(mcpBridge.dataSource == "extension" ? Color(hex: "#00B4D8") : Color(hex: "#8B7BE8"))
                        .cornerRadius(3)
                }
            }

            // 2x2 kingdom grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                ForEach(skillsByKingdom, id: \.0) { kingdom, skills in
                    MCPKingdomCard(
                        name: kingdom,
                        icon: kingdomIcons[kingdom] ?? "🏰",
                        tier: kingdomTiers[kingdom] ?? "",
                        color: kingdomColors[kingdom] ?? InsightColors.purple,
                        skills: skills
                    )
                }
            }
        }
    }
}

// MARK: - MCP Kingdom Card

struct MCPKingdomCard: View {
    let name: String
    let icon: String
    let tier: String
    let color: Color
    let skills: [MCPSkillProgress]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Kingdom header
            HStack {
                Text("\(icon) \(name)")
                    .font(.pixelSystem(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "#2D2B3E"))

                Spacer()

                Text(tier)
                    .font(.pixelSystem(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.1))
                    .cornerRadius(3)
            }

            // Skill bars
            ForEach(skills) { skill in
                HStack(spacing: 8) {
                    Text(skill.name)
                        .font(.pixelSystem(size: 9, weight: .semibold))
                        .foregroundColor(Color(hex: "#2D2B3E").opacity(0.55))
                        .frame(width: 80, alignment: .leading)
                        .lineLimit(1)

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color.opacity(0.1))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color)
                                .frame(width: max(0, geo.size.width * progressFraction(skill)))
                        }
                    }
                    .frame(height: 6)

                    Text("Lv\(skill.level)")
                        .font(.pixelSystem(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#2D2B3E").opacity(0.35))
                        .frame(width: 24, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .pixelCard(borderColor: color.opacity(0.25))
    }

    private func progressFraction(_ skill: MCPSkillProgress) -> CGFloat {
        guard skill.xpToNextLevel > 0 else {
            return skill.level >= skill.maxLevel ? 1.0 : 0.0
        }
        let base = CGFloat(skill.level) / CGFloat(skill.maxLevel)
        let inLevel = CGFloat(skill.xpProgress) / CGFloat(skill.xpToNextLevel) / CGFloat(skill.maxLevel)
        return min(1.0, base + inLevel)
    }
}

// MARK: - Weekly Stats (Pixel Style)

struct PixelWeeklyStats: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THIS WEEK")
                .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "#2D2B3E").opacity(0.4))

            HStack(spacing: 12) {
                PixelStatChip(
                    icon: { PixelTarget(color: InsightColors.blue, size: 20) },
                    value: "\(appState.completedChallenges.count)",
                    label: "Challenges",
                    accentColor: InsightColors.blue
                )

                PixelStatChip(
                    icon: { PixelBook(color: InsightColors.green, size: 20) },
                    value: "\(appState.completedLessons.count)",
                    label: "Skills",
                    accentColor: InsightColors.green
                )

                PixelStatChip(
                    icon: { PixelStar(color: InsightColors.gold, size: 20) },
                    value: "\(appState.totalXP)",
                    label: "XP Earned",
                    accentColor: InsightColors.gold
                )
            }
        }
    }
}

struct PixelStatChip<Icon: View>: View {
    let icon: () -> Icon
    let value: String
    let label: String
    let accentColor: Color

    var body: some View {
        VStack(spacing: 8) {
            icon()

            Text(value)
                .font(.pixelSystem(size: 22, weight: .black, design: .monospaced))
                .foregroundColor(Color(hex: "#2D2B3E"))

            Text(label)
                .font(.pixelSystem(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(hex: "#2D2B3E").opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .pixelCard(borderColor: accentColor.opacity(0.3))
    }
}

// MARK: - Streak Calendar (Pixel Style)

struct PixelStreakCalendar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("STREAK")
                    .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#2D2B3E").opacity(0.4))

                Spacer()

                HStack(spacing: 6) {
                    PixelFlame(color: InsightColors.orange, tipColor: InsightColors.gold, size: 14)
                    Text("\(appState.streak)")
                        .font(.pixelSystem(size: 16, weight: .black, design: .monospaced))
                        .foregroundColor(InsightColors.orange)
                    Text("days")
                        .font(.pixelSystem(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(hex: "#2D2B3E").opacity(0.4))
                }
            }

            // 7-day grid
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { index in
                    let dayOffset = 6 - index
                    let date = Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date()
                    let dayNum = Calendar.current.component(.day, from: date)
                    let dayName = shortDayName(for: date)
                    let isActive = index >= (7 - min(appState.streak, 7))
                    let isToday = dayOffset == 0

                    VStack(spacing: 4) {
                        Text(dayName)
                            .font(.pixelSystem(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(isToday ? InsightColors.orange : Color(hex: "#2D2B3E").opacity(0.35))

                        ZStack {
                            // Circle shape
                            Circle()
                                .fill(isActive ? streakColor(for: index) : Color(hex: "#E0DBEF"))
                                .frame(width: 34, height: 34)
                            Circle()
                                .stroke(isActive ? streakColor(for: index).opacity(0.6) : Color(hex: "#D0C9E2"), lineWidth: 1)
                                .frame(width: 34, height: 34)

                            if isActive {
                                // Pixel checkmark
                                PixelCheck(size: 12)
                            } else {
                                Text("\(dayNum)")
                                    .font(.pixelSystem(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(hex: "#2D2B3E").opacity(0.3))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(14)
            .pixelCard(borderColor: InsightColors.orange.opacity(0.25))
        }
    }

    private func streakColor(for index: Int) -> Color {
        let colors: [Color] = [
            InsightColors.gold.opacity(0.7),
            InsightColors.gold.opacity(0.8),
            InsightColors.orange.opacity(0.7),
            InsightColors.orange.opacity(0.8),
            InsightColors.orange.opacity(0.9),
            InsightColors.orange,
            InsightColors.red
        ]
        return colors[min(index, colors.count - 1)]
    }

    private func shortDayName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return String(formatter.string(from: date).prefix(2)).uppercased()
    }
}

/// Tiny pixel checkmark
struct PixelCheck: View {
    let size: CGFloat

    var body: some View {
        let p = size / 7
        Canvas { ctx, _ in
            let w = Color.white
            ctx.fill(Path(CGRect(x: p, y: p * 4, width: p, height: p)), with: .color(w))
            ctx.fill(Path(CGRect(x: p * 2, y: p * 5, width: p, height: p)), with: .color(w))
            ctx.fill(Path(CGRect(x: p * 3, y: p * 4, width: p, height: p)), with: .color(w))
            ctx.fill(Path(CGRect(x: p * 4, y: p * 3, width: p, height: p)), with: .color(w))
            ctx.fill(Path(CGRect(x: p * 5, y: p * 2, width: p, height: p)), with: .color(w))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Statistics Grid (Pixel Style)

struct PixelStatisticsGrid: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("STATISTICS")
                .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "#2D2B3E").opacity(0.4))

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                PixelStatBox(
                    icon: { PixelTrophy(color: InsightColors.green, size: 22) },
                    title: "LEVEL",
                    value: "\(appState.userLevel)",
                    accent: InsightColors.green
                )
                PixelStatBox(
                    icon: { PixelStar(color: InsightColors.gold, size: 22) },
                    title: "TOTAL XP",
                    value: "\(appState.totalXP)",
                    accent: InsightColors.gold
                )
                PixelStatBox(
                    icon: { PixelBook(color: InsightColors.purple, size: 22) },
                    title: "LESSONS",
                    value: "\(appState.completedLessons.count)",
                    accent: InsightColors.purple
                )
                PixelStatBox(
                    icon: { PixelTarget(color: InsightColors.blue, size: 22) },
                    title: "CHALLENGES",
                    value: "\(appState.completedChallenges.count)",
                    accent: InsightColors.blue
                )
                PixelStatBox(
                    icon: { PixelFlame(color: InsightColors.orange, tipColor: InsightColors.gold, size: 22) },
                    title: "STREAK",
                    value: "\(appState.streak)",
                    accent: InsightColors.orange
                )
                PixelStatBox(
                    icon: { PixelMap(color: InsightColors.teal, size: 22) },
                    title: "TIER",
                    value: "\(appState.currentTier)",
                    accent: InsightColors.teal
                )
            }
        }
    }
}

struct PixelStatBox<Icon: View>: View {
    let icon: () -> Icon
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(spacing: 8) {
            icon()

            Text(value)
                .font(.pixelSystem(size: 18, weight: .black, design: .monospaced))
                .foregroundColor(Color(hex: "#2D2B3E"))

            Text(title)
                .font(.pixelSystem(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "#2D2B3E").opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .pixelCard(borderColor: accent.opacity(0.25))
    }
}

// MARK: - Activity Breakdown (Pixel Style)

struct PixelActivityBreakdown: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var mcpBridge: MCPBridgeService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACTIVITY")
                .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "#2D2B3E").opacity(0.4))

            VStack(spacing: 0) {
                PixelActivityRow(
                    icon: { PixelBook(color: InsightColors.purple, size: 14) },
                    label: "Skills completed",
                    value: appState.completedLessons.count,
                    maxValue: 16,
                    barColor: InsightColors.purple
                )

                PixelDivider()

                PixelActivityRow(
                    icon: { PixelTarget(color: InsightColors.blue, size: 14) },
                    label: "Challenges done",
                    value: appState.completedChallenges.count,
                    maxValue: 16,
                    barColor: InsightColors.blue
                )

                PixelDivider()

                PixelActivityRow(
                    icon: { PixelMap(color: InsightColors.teal, size: 14) },
                    label: "Current tier",
                    value: appState.currentTier,
                    maxValue: 4,
                    barColor: InsightColors.teal
                )

                // ═══ MCP-enriched activity rows ═══
                if mcpBridge.isConnected {
                    PixelDivider()

                    // Dashed separator label
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color(hex: "#8B7BE8").opacity(0.3))
                            .frame(height: 1)
                        Text(mcpBridge.dataSource == "extension" ? "from Cursor" : "from real coding")
                            .font(.pixelSystem(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "#8B7BE8").opacity(0.5))
                        Rectangle()
                            .fill(Color(hex: "#8B7BE8").opacity(0.3))
                            .frame(height: 1)
                    }
                    .padding(.vertical, 4)

                    if let summary = mcpBridge.todaySummary {
                        PixelActivityRow(
                            icon: { PixelBolt(color: InsightColors.purple, size: 14) },
                            label: "Coding XP earned",
                            value: mcpBridge.totalSkillXP,
                            maxValue: max(mcpBridge.totalSkillXP, 100),
                            barColor: InsightColors.purple
                        )

                        PixelDivider()

                        PixelActivityRow(
                            icon: { PixelTarget(color: InsightColors.green, size: 14) },
                            label: "Bugs fixed today",
                            value: summary.errorsFixed,
                            maxValue: max(summary.errorsFixed, 1),
                            barColor: InsightColors.green
                        )
                    }

                    PixelDivider()

                    PixelActivityRow(
                        icon: { PixelStar(color: InsightColors.gold, size: 14) },
                        label: "Active coding days",
                        value: mcpBridge.activeDaysCount,
                        maxValue: max(mcpBridge.activeDaysCount, 7),
                        barColor: InsightColors.gold
                    )
                }
            }
            .padding(14)
            .pixelCard()
        }
    }
}

struct PixelDivider: View {
    var body: some View {
        // Dashed pixel-style divider
        HStack(spacing: 3) {
            ForEach(0..<30, id: \.self) { _ in
                Rectangle()
                    .fill(Color(hex: "#E0DBEF"))
                    .frame(width: 4, height: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

struct PixelActivityRow<Icon: View>: View {
    let icon: () -> Icon
    let label: String
    let value: Int
    let maxValue: Int
    let barColor: Color

    var body: some View {
        HStack(spacing: 10) {
            icon()
                .frame(width: 18, height: 18)

            Text(label)
                .font(.pixelSystem(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "#2D2B3E"))

            Spacer()

            // Pixel progress bar
            PixelProgressBar(value: value, maxValue: maxValue, color: barColor)
                .frame(maxWidth: 90)

            Text("\(value)/\(maxValue)")
                .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "#2D2B3E").opacity(0.45))
                .frame(width: 36, alignment: .trailing)
        }
    }
}

/// A segmented pixel progress bar
struct PixelProgressBar: View {
    let value: Int
    let maxValue: Int
    let color: Color

    private var segments: Int { min(maxValue, 10) }
    private var filledSegments: Int {
        guard maxValue > 0 else { return 0 }
        return Int(round(Double(value) / Double(maxValue) * Double(segments)))
    }

    var body: some View {
        GeometryReader { geo in
            let segWidth = (geo.size.width - CGFloat(segments - 1) * 2) / CGFloat(segments)
            HStack(spacing: 2) {
                ForEach(0..<segments, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i < filledSegments ? color : Color(hex: "#E0DBEF"))
                        .frame(width: max(2, segWidth), height: 8)
                }
            }
        }
        .frame(height: 8)
    }
}

// MARK: - Preview

#Preview {
    InsightsView()
        .environmentObject(AppState())
        .environmentObject(MCPBridgeService.shared)
}
