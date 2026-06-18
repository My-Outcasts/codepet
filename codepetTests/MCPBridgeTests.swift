import XCTest

// MARK: - MCP Bridge Data Parsing Tests
// Mirrors: MCPBridgeService.swift Codable structs
// Tests that JSON from ~/.codepet/ is correctly parsed into Swift models

class MCPDailySummaryParsingTests: XCTestCase {

    // Mirror the struct locally (same as MCPBridgeService.swift)
    struct MCPDailySummary: Codable {
        let date: String
        let totalCodingMinutes: Int
        let linesAdded: Int
        let linesRemoved: Int
        let commits: Int
        let aiSessions: Int
        let errorsFixed: Int
        let languageBreakdown: [String: Int]
        let skillsTracked: [String: Int]
        let topFiles: [String]
        let petReaction: String?
    }

    func test_parsesFullSummary() throws {
        let json = """
        {
          "date": "2026-04-07",
          "totalCodingMinutes": 142,
          "linesAdded": 385,
          "linesRemoved": 42,
          "commits": 7,
          "aiSessions": 12,
          "errorsFixed": 3,
          "languageBreakdown": { "Swift": 8, "TypeScript": 4 },
          "skillsTracked": { "prompt-clarity": 24, "error-reading": 35 },
          "topFiles": ["codepet/App/CodePetApp.swift", "codepet-mcp-server/src/index.ts"],
          "petReaction": "Let's BUILD! You made 7 commits today — that's a speedrun!"
        }
        """.data(using: .utf8)!

        let summary = try JSONDecoder().decode(MCPDailySummary.self, from: json)

        XCTAssertEqual(summary.date, "2026-04-07")
        XCTAssertEqual(summary.totalCodingMinutes, 142)
        XCTAssertEqual(summary.linesAdded, 385)
        XCTAssertEqual(summary.linesRemoved, 42)
        XCTAssertEqual(summary.commits, 7)
        XCTAssertEqual(summary.aiSessions, 12)
        XCTAssertEqual(summary.errorsFixed, 3)
        XCTAssertEqual(summary.languageBreakdown["Swift"], 8)
        XCTAssertEqual(summary.languageBreakdown["TypeScript"], 4)
        XCTAssertEqual(summary.skillsTracked["prompt-clarity"], 24)
        XCTAssertEqual(summary.topFiles.count, 2)
        XCTAssertEqual(summary.petReaction, "Let's BUILD! You made 7 commits today — that's a speedrun!")
    }

    func test_parsesEmptyDaySummary() throws {
        let json = """
        {
          "date": "2026-04-06",
          "totalCodingMinutes": 0,
          "linesAdded": 0,
          "linesRemoved": 0,
          "commits": 0,
          "aiSessions": 0,
          "errorsFixed": 0,
          "languageBreakdown": {},
          "skillsTracked": {},
          "topFiles": [],
          "petReaction": "No coding activity today — your pet is napping!"
        }
        """.data(using: .utf8)!

        let summary = try JSONDecoder().decode(MCPDailySummary.self, from: json)

        XCTAssertEqual(summary.totalCodingMinutes, 0)
        XCTAssertEqual(summary.commits, 0)
        XCTAssertTrue(summary.languageBreakdown.isEmpty)
        XCTAssertTrue(summary.topFiles.isEmpty)
    }

    func test_parsesNullPetReaction() throws {
        let json = """
        {
          "date": "2026-04-05",
          "totalCodingMinutes": 30,
          "linesAdded": 50,
          "linesRemoved": 10,
          "commits": 2,
          "aiSessions": 3,
          "errorsFixed": 1,
          "languageBreakdown": { "Python": 3 },
          "skillsTracked": {},
          "topFiles": ["main.py"]
        }
        """.data(using: .utf8)!

        let summary = try JSONDecoder().decode(MCPDailySummary.self, from: json)

        XCTAssertNil(summary.petReaction)
        XCTAssertEqual(summary.commits, 2)
    }
}

// MARK: - MCP Skill Progress Parsing Tests
// Mirrors: MCPSkillProgress struct in MCPBridgeService.swift
// Tests parsing of skill tree data from profile.json

class MCPSkillProgressParsingTests: XCTestCase {

    struct MCPSkillProgress: Codable {
        let id: String
        let name: String
        let icon: String
        let kingdom: String
        let tier: Int
        let nodeType: String
        let xp: Int
        let level: Int
        let maxLevel: Int
        let xpProgress: Int
        let xpToNextLevel: Int
    }

    func test_parsesSkillProgressArray() throws {
        let json = """
        [
          {
            "id": "prompt-clarity",
            "name": "Prompt Clarity",
            "icon": "✏️",
            "kingdom": "The Molten Forge",
            "tier": 1,
            "nodeType": "lesson",
            "xp": 48,
            "level": 0,
            "maxLevel": 5,
            "xpProgress": 48,
            "xpToNextLevel": 2
          },
          {
            "id": "error-reading",
            "name": "Error Reading",
            "icon": "🔍",
            "kingdom": "The Molten Forge",
            "tier": 1,
            "nodeType": "lesson",
            "xp": 65,
            "level": 1,
            "maxLevel": 5,
            "xpProgress": 15,
            "xpToNextLevel": 85
          },
          {
            "id": "second-brain",
            "name": "Second Brain",
            "icon": "💡",
            "kingdom": "The Mystic Grove",
            "tier": 4,
            "nodeType": "boss",
            "xp": 0,
            "level": 0,
            "maxLevel": 5,
            "xpProgress": 0,
            "xpToNextLevel": 50
          }
        ]
        """.data(using: .utf8)!

        let skills = try JSONDecoder().decode([MCPSkillProgress].self, from: json)

        XCTAssertEqual(skills.count, 3)

        // First skill: close to leveling up
        XCTAssertEqual(skills[0].id, "prompt-clarity")
        XCTAssertEqual(skills[0].kingdom, "The Molten Forge")
        XCTAssertEqual(skills[0].tier, 1)
        XCTAssertEqual(skills[0].xp, 48)
        XCTAssertEqual(skills[0].level, 0)
        XCTAssertEqual(skills[0].xpToNextLevel, 2)

        // Second skill: already leveled up once
        XCTAssertEqual(skills[1].id, "error-reading")
        XCTAssertEqual(skills[1].level, 1)
        XCTAssertEqual(skills[1].xp, 65)

        // Third skill: untouched boss skill
        XCTAssertEqual(skills[2].id, "second-brain")
        XCTAssertEqual(skills[2].nodeType, "boss")
        XCTAssertEqual(skills[2].xp, 0)
        XCTAssertEqual(skills[2].level, 0)
    }

    func test_totalXPCalculation() throws {
        let json = """
        [
          { "id": "a", "name": "A", "icon": "", "kingdom": "K", "tier": 1, "nodeType": "lesson", "xp": 30, "level": 0, "maxLevel": 5, "xpProgress": 30, "xpToNextLevel": 20 },
          { "id": "b", "name": "B", "icon": "", "kingdom": "K", "tier": 1, "nodeType": "lesson", "xp": 55, "level": 1, "maxLevel": 5, "xpProgress": 5, "xpToNextLevel": 95 },
          { "id": "c", "name": "C", "icon": "", "kingdom": "K", "tier": 1, "nodeType": "boss", "xp": 0, "level": 0, "maxLevel": 5, "xpProgress": 0, "xpToNextLevel": 50 }
        ]
        """.data(using: .utf8)!

        let skills = try JSONDecoder().decode([MCPSkillProgress].self, from: json)
        let totalXP = skills.reduce(0) { $0 + $1.xp }

        XCTAssertEqual(totalXP, 85)
    }
}

// MARK: - MCP Session Event Parsing Tests
// Mirrors: MCPSessionEvent struct in MCPBridgeService.swift

class MCPSessionEventParsingTests: XCTestCase {

    struct MCPSessionEvent: Codable {
        let id: Int
        let timestamp: String
        let type: String
        let action: String
        let project: String?
        let language: String?
        let file: String?
    }

    func test_parsesEventArray() throws {
        let json = """
        [
          {
            "id": 1,
            "timestamp": "2026-04-07T10:30:00.000Z",
            "type": "server",
            "action": "start",
            "metadata": { "version": "0.3.0" }
          },
          {
            "id": 2,
            "timestamp": "2026-04-07T10:31:00.000Z",
            "type": "tool_call",
            "action": "scan_project",
            "project": "CodePet-Clean"
          },
          {
            "id": 3,
            "timestamp": "2026-04-07T10:32:00.000Z",
            "type": "tool_call",
            "action": "get_file_content",
            "language": "Swift",
            "file": "/Users/dev/codepet/App/CodePetApp.swift"
          },
          {
            "id": 4,
            "timestamp": "2026-04-07T10:33:00.000Z",
            "type": "git",
            "action": "commit",
            "project": "CodePet-Clean"
          },
          {
            "id": 5,
            "timestamp": "2026-04-07T10:34:00.000Z",
            "type": "diagnostic",
            "action": "clean",
            "project": "CodePet-Clean",
            "language": "TypeScript"
          }
        ]
        """.data(using: .utf8)!

        let events = try JSONDecoder().decode([MCPSessionEvent].self, from: json)

        XCTAssertEqual(events.count, 5)

        // Server start event
        XCTAssertEqual(events[0].type, "server")
        XCTAssertEqual(events[0].action, "start")
        XCTAssertNil(events[0].project)

        // Tool call with project
        XCTAssertEqual(events[1].type, "tool_call")
        XCTAssertEqual(events[1].action, "scan_project")
        XCTAssertEqual(events[1].project, "CodePet-Clean")

        // File read with language
        XCTAssertEqual(events[2].language, "Swift")
        XCTAssertNotNil(events[2].file)

        // Git commit
        XCTAssertEqual(events[3].type, "git")

        // Clean diagnostic
        XCTAssertEqual(events[4].action, "clean")
    }

    func test_filtersToolCallEvents() throws {
        let json = """
        [
          { "id": 1, "timestamp": "2026-04-07T10:30:00Z", "type": "server", "action": "start" },
          { "id": 2, "timestamp": "2026-04-07T10:31:00Z", "type": "tool_call", "action": "scan_project" },
          { "id": 3, "timestamp": "2026-04-07T10:32:00Z", "type": "tool_call", "action": "get_file_content" },
          { "id": 4, "timestamp": "2026-04-07T10:33:00Z", "type": "git", "action": "commit" },
          { "id": 5, "timestamp": "2026-04-07T10:34:00Z", "type": "tool_call", "action": "get_diagnostics" }
        ]
        """.data(using: .utf8)!

        let events = try JSONDecoder().decode([MCPSessionEvent].self, from: json)
        let toolCalls = events.filter { $0.type == "tool_call" }

        XCTAssertEqual(toolCalls.count, 3)
    }
}

// MARK: - MCP XP Sync Logic Tests
// Mirrors: AppState.syncFromMCP — high-water mark to prevent double-counting
// XP scale: 10 MCP XP = 1 app XP

class MCPXPSyncLogicTests: XCTestCase {

    /// Mirrors the XP delta logic from AppState.syncFromMCP
    private func computeScaledXP(currentMCPXP: Int, previouslyApplied: Int) -> Int {
        let delta = currentMCPXP - previouslyApplied
        guard delta > 0 else { return 0 }
        return delta / 10
    }

    func test_firstSyncAppliesScaledXP() {
        // First sync: 85 MCP XP, nothing applied yet
        let xp = computeScaledXP(currentMCPXP: 85, previouslyApplied: 0)
        XCTAssertEqual(xp, 8) // 85 / 10 = 8
    }

    func test_subsequentSyncOnlyAppliesDelta() {
        // Second sync: 150 total, 85 already applied
        let xp = computeScaledXP(currentMCPXP: 150, previouslyApplied: 85)
        XCTAssertEqual(xp, 6) // (150 - 85) / 10 = 6
    }

    func test_noXPWhenNoDelta() {
        // Same XP as before — nothing new
        let xp = computeScaledXP(currentMCPXP: 85, previouslyApplied: 85)
        XCTAssertEqual(xp, 0)
    }

    func test_noXPWhenMCPXPDecreases() {
        // Edge case: MCP data reset/corrupted — don't subtract XP
        let xp = computeScaledXP(currentMCPXP: 40, previouslyApplied: 85)
        XCTAssertEqual(xp, 0)
    }

    func test_smallDeltaBelowThreshold() {
        // 9 new MCP XP — not enough for 1 app XP yet
        let xp = computeScaledXP(currentMCPXP: 94, previouslyApplied: 85)
        XCTAssertEqual(xp, 0) // 9 / 10 = 0
    }

    func test_exactlyTenDelta() {
        let xp = computeScaledXP(currentMCPXP: 95, previouslyApplied: 85)
        XCTAssertEqual(xp, 1)
    }

    func test_largeXPAccumulation() {
        // Power user: 1550 MCP XP total, 0 applied
        let xp = computeScaledXP(currentMCPXP: 1550, previouslyApplied: 0)
        XCTAssertEqual(xp, 155)
    }
}

// MARK: - Pet Mood from Summary Tests
// Mirrors: AppState.syncFromMCP mood logic

class PetMoodFromSummaryTests: XCTestCase {

    /// Mirrors mood assignment logic from syncFromMCP
    private func determineMood(totalCodingMinutes: Int) -> String {
        if totalCodingMinutes > 30 {
            return "Happy"
        } else if totalCodingMinutes > 0 {
            return "Content"
        } else {
            return "Idle"
        }
    }

    func test_happyWhenCodingOver30Min() {
        XCTAssertEqual(determineMood(totalCodingMinutes: 142), "Happy")
    }

    func test_contentWhenCodingUnder30Min() {
        XCTAssertEqual(determineMood(totalCodingMinutes: 15), "Content")
    }

    func test_idleWhenNoCoding() {
        XCTAssertEqual(determineMood(totalCodingMinutes: 0), "Idle")
    }

    func test_happyAtExactly31Min() {
        XCTAssertEqual(determineMood(totalCodingMinutes: 31), "Happy")
    }

    func test_contentAtExactly30Min() {
        // 30 is NOT > 30, so it's Content
        XCTAssertEqual(determineMood(totalCodingMinutes: 30), "Content")
    }

    func test_contentAtExactly1Min() {
        XCTAssertEqual(determineMood(totalCodingMinutes: 1), "Content")
    }
}

// MARK: - Profile JSON Extraction Tests
// Mirrors: MCPBridgeService.loadSkillProgress reading nested JSON from profile.json

class ProfileSkillExtractionTests: XCTestCase {

    struct MCPSkillProgress: Codable {
        let id: String
        let xp: Int
        let level: Int
    }

    func test_extractsSkillProgressFromProfile() throws {
        let profileJSON = """
        {
          "user_profile": {
            "petName": "Nova",
            "petCharacter": "nova",
            "level": 1
          },
          "skill_progress": [
            { "id": "prompt-clarity", "xp": 24, "level": 0 },
            { "id": "error-reading", "xp": 65, "level": 1 }
          ],
          "last_project_scan": {
            "name": "CodePet-Clean"
          }
        }
        """.data(using: .utf8)!

        // Mirror the extraction logic from MCPBridgeService
        let profile = try JSONSerialization.jsonObject(with: profileJSON) as! [String: Any]
        let skillData = profile["skill_progress"]!
        let skillJSON = try JSONSerialization.data(withJSONObject: skillData)
        let skills = try JSONDecoder().decode([MCPSkillProgress].self, from: skillJSON)

        XCTAssertEqual(skills.count, 2)
        XCTAssertEqual(skills[0].id, "prompt-clarity")
        XCTAssertEqual(skills[0].xp, 24)
        XCTAssertEqual(skills[1].id, "error-reading")
        XCTAssertEqual(skills[1].level, 1)
    }

    func test_handlesProfileWithNoSkillProgress() throws {
        let profileJSON = """
        {
          "user_profile": {
            "petName": "Nova"
          }
        }
        """.data(using: .utf8)!

        let profile = try JSONSerialization.jsonObject(with: profileJSON) as! [String: Any]
        let skillData = profile["skill_progress"]

        // No skill_progress key — should gracefully return empty
        XCTAssertNil(skillData)
    }
}
