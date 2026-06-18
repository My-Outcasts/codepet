import SwiftUI

// Re-export all game system models from Models/GameSystems.swift
// This file serves as the central game systems backend for the CodePet game economy,
// pet care mechanics, collection systems, and character abilities.

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Pet Care System (Tamagotchi Loop)
// ═══════════════════════════════════════════════════════════════════════════════

/// Drives the pet care loop: hunger decays over time, feeding costs coins,
/// mood reacts to care level, and neglect has visible consequences.
public struct PetCare {

    // MARK: - Mood States

    public enum Mood: String, Codable, CaseIterable {
        case ecstatic  = "Ecstatic"    // streak >= 7, energy >= 80, just fed
        case happy     = "Happy"       // energy >= 60, fed today
        case content   = "Content"     // energy 40-59
        case idle      = "Idle"        // default / energy 20-39
        case hungry    = "Hungry"      // hunger < 30
        case sleepy    = "Sleepy"      // away > 12 hours
        case sad       = "Sad"         // streak broken, or energy < 20
        case asleep    = "Asleep"      // away > 3 days

        public var emoji: String {
            switch self {
            case .ecstatic: return "🤩"
            case .happy:    return "😊"
            case .content:  return "🙂"
            case .idle:     return "😐"
            case .hungry:   return "🍕"
            case .sleepy:   return "😴"
            case .sad:      return "😢"
            case .asleep:   return "💤"
            }
        }

        public var description: String {
            switch self {
            case .ecstatic: return "On fire! Can't stop won't stop!"
            case .happy:    return "Feeling great, let's code!"
            case .content:  return "Doing okay. Got any lessons?"
            case .idle:     return "Just chilling here..."
            case .hungry:   return "Could use a snack..."
            case .sleepy:   return "Yawwwn... missed you..."
            case .sad:      return "I miss our coding sessions..."
            case .asleep:   return "Zzz... wake me up..."
            }
        }

        /// Sprite animation multiplier (for breathing/idle speed)
        public var animationSpeed: Double {
            switch self {
            case .ecstatic: return 1.5
            case .happy:    return 1.2
            case .content:  return 1.0
            case .idle:     return 0.8
            case .hungry:   return 0.6
            case .sleepy:   return 0.4
            case .sad:      return 0.5
            case .asleep:   return 0.2
            }
        }
    }

    // MARK: - Mood Calculation

    /// Determine current mood based on all pet stats
    public static func calculateMood(
        energy: Int,
        hunger: Int,
        streak: Int,
        hoursSinceLastVisit: Double,
        justFed: Bool = false
    ) -> Mood {
        // Priority-based: check worst states first
        if hoursSinceLastVisit > 72 { return .asleep }      // 3+ days away
        if energy < 15 && hunger < 20 { return .sad }        // neglected
        if hoursSinceLastVisit > 12 { return .sleepy }       // half day away
        if hunger < 30 { return .hungry }                     // needs food
        if energy < 20 { return .sad }

        // Positive states
        if streak >= 7 && energy >= 80 { return .ecstatic }  // on a roll
        if justFed || (energy >= 60 && hunger >= 60) { return .happy }
        if energy >= 40 { return .content }

        return .idle
    }

    // MARK: - Energy Decay

    /// Energy decays while user is away. Returns new energy value.
    public static func decayEnergy(current: Int, hoursSinceLastVisit: Double) -> Int {
        // Lose 2 energy per hour away, minimum 5
        let loss = Int(hoursSinceLastVisit * 2)
        return max(5, current - loss)
    }

    /// Hunger decays faster than energy
    public static func decayHunger(current: Int, hoursSinceLastVisit: Double) -> Int {
        let loss = Int(hoursSinceLastVisit * 3)
        return max(0, current - loss)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Hearts System (Duolingo-style Limited Mistakes)
// ═══════════════════════════════════════════════════════════════════════════════

/// Hearts limit mistakes per session. Wrong answers cost hearts.
/// Hearts regenerate over time or can be refilled by feeding your pet.
public struct HeartsSystem {

    public static let maxHearts: Int = 5
    public static let regenIntervalMinutes: Int = 30 // 1 heart every 30 min

    /// Calculate current hearts based on last known state
    public static func currentHearts(
        savedHearts: Int,
        lastHeartLoss: Date?
    ) -> Int {
        guard savedHearts < maxHearts, let lastLoss = lastHeartLoss else {
            return min(savedHearts, maxHearts)
        }

        let minutesSinceLoss = Date().timeIntervalSince(lastLoss) / 60
        let regened = Int(minutesSinceLoss) / regenIntervalMinutes
        return min(maxHearts, savedHearts + regened)
    }

    /// Time until next heart regenerates (in seconds), or nil if full
    public static func timeUntilNextHeart(
        savedHearts: Int,
        lastHeartLoss: Date?
    ) -> TimeInterval? {
        guard savedHearts < maxHearts, let lastLoss = lastHeartLoss else { return nil }
        let minutesSinceLoss = Date().timeIntervalSince(lastLoss) / 60
        let minutesIntoCurrentCycle = minutesSinceLoss.truncatingRemainder(dividingBy: Double(regenIntervalMinutes))
        return Double(regenIntervalMinutes) * 60 - minutesIntoCurrentCycle * 60
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Idle XP System (Passive Learning)
// ═══════════════════════════════════════════════════════════════════════════════

/// While user is away, pet "studies" and earns a small XP trickle.
/// Also generates a fun coding tip to show on return.
public struct IdleXPSystem {

    public static let xpPerHour: Int = 2        // passive XP rate
    public static let maxIdleHours: Int = 24     // cap at 24h of idle XP
    public static let maxIdleXP: Int = 48        // 24h × 2 XP

    /// Calculate XP earned while away
    public static func calculateIdleXP(hoursSinceLastVisit: Double) -> Int {
        let hours = min(hoursSinceLastVisit, Double(maxIdleHours))
        return min(Int(hours) * xpPerHour, maxIdleXP)
    }

    /// What Byte "learned" while you were away
    public static let idleTips: [String] = [
        "I read about optionals — they're like Schrödinger's variable! 📦",
        "Did you know? The first computer bug was an actual moth! 🦋",
        "I practiced loops — for i in 0..<100 { print(\"I miss you\") } 🔁",
        "I learned that Swift was released in 2014. I'm older than I look! 🎂",
        "Fun fact: The average developer mass produces ~100 lines of code per day! 💻",
        "I tried to write a sorting algorithm. Bubble sort is... bubbly? 🫧",
        "I discovered that 'git blame' shows who wrote each line. No pressure! 😅",
        "I found out that Python is named after Monty Python, not the snake! 🐍",
        "I learned about recursion. To understand recursion, see: recursion. 🔄",
        "I read about APIs — they're like menus at a restaurant for code! 🍽️",
        "I studied error handling. try? catch? throw? Sounds like baseball! ⚾",
        "I learned that the first programmer was Ada Lovelace in the 1840s! 👩‍💻",
    ]

    /// Get a random tip for the return screen
    public static func randomTip() -> String {
        idleTips.randomElement() ?? idleTips[0]
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Coins & Economy
// ═══════════════════════════════════════════════════════════════════════════════

/// In-game currency earned from lessons, challenges, streaks.
/// Spent on: feeding pet, cosmetics, streak freezes.
public struct GameEconomy {

    // Earning rates
    public static let coinsPerLesson: Int = 10
    public static let coinsPerChallenge: Int = 25
    public static let coinsPerStreakDay: Int = 5
    public static let coinsPerBossBattle: Int = 50
    public static let coinsPerLevelUp: Int = 20

    // Spending costs
    public static let feedCost: Int = 5           // feed pet once
    public static let premiumFeedCost: Int = 15   // premium food (full energy)
    public static let streakFreezeCost: Int = 30  // protect streak for 1 day
    public static let heartRefillCost: Int = 20   // refill all hearts

    /// Streak milestones — recognized when the user reaches each day count.
    /// Each grants bonus coins and (at bigger rungs) free streak freezes. Cosmetic
    /// unlocks reuse the `unlockedBy: "streak_<day>"` field on CosmeticShop items
    /// (e.g. Fire Aura at 14, Full-Stack Cape at 30).
    public static let streakMilestones: [StreakMilestone] = [
        StreakMilestone(day: 3,   bonusCoins: 25,   freezeReward: 0),
        StreakMilestone(day: 7,   bonusCoins: 75,   freezeReward: 1),
        StreakMilestone(day: 14,  bonusCoins: 150,  freezeReward: 1),
        StreakMilestone(day: 30,  bonusCoins: 300,  freezeReward: 2),
        StreakMilestone(day: 50,  bonusCoins: 500,  freezeReward: 2),
        StreakMilestone(day: 100, bonusCoins: 1000, freezeReward: 3),
    ]
}

/// A streak milestone the user is recognized for reaching.
public struct StreakMilestone: Equatable {
    public let day: Int
    public let bonusCoins: Int
    public let freezeReward: Int
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Pet Food Items
// ═══════════════════════════════════════════════════════════════════════════════

public struct PetFood: Identifiable {
    public let id: String
    public let name: String
    public let emoji: String
    public let energyRestore: Int
    public let hungerRestore: Int
    public let coinCost: Int
    public let description: String

    public init(id: String, name: String, emoji: String,
                energyRestore: Int, hungerRestore: Int, coinCost: Int,
                description: String) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.energyRestore = energyRestore
        self.hungerRestore = hungerRestore
        self.coinCost = coinCost
        self.description = description
    }

    public static let all: [PetFood] = [
        PetFood(id: "byte_snack", name: "Byte Snack", emoji: "🍪",
                energyRestore: 10, hungerRestore: 15, coinCost: 5,
                description: "A quick cookie to keep Byte going"),
        PetFood(id: "code_candy", name: "Code Candy", emoji: "🍬",
                energyRestore: 15, hungerRestore: 20, coinCost: 8,
                description: "Sweet syntax sugar"),
        PetFood(id: "debug_burger", name: "Debug Burger", emoji: "🍔",
                energyRestore: 30, hungerRestore: 40, coinCost: 15,
                description: "A hearty meal that squashes hunger bugs"),
        PetFood(id: "algo_smoothie", name: "Algo Smoothie", emoji: "🧃",
                energyRestore: 20, hungerRestore: 25, coinCost: 12,
                description: "Optimized nutrition in O(1) sips"),
        PetFood(id: "full_stack_feast", name: "Full Stack Feast", emoji: "🍱",
                energyRestore: 50, hungerRestore: 60, coinCost: 25,
                description: "Frontend, backend, and dessert — the complete meal"),
        PetFood(id: "golden_compile", name: "Golden Compile", emoji: "✨",
                energyRestore: 100, hungerRestore: 100, coinCost: 50,
                description: "Legendary food. Fully restores everything."),
    ]
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Compendium (Collectible Code Knowledge)
// ═══════════════════════════════════════════════════════════════════════════════

/// Pokédex-style collection of coding knowledge.
/// Each entry is earned by completing lessons or challenges.
public struct CompendiumEntry: Identifiable, Codable {
    public let id: String
    public let category: CompendiumCategory
    public let name: String
    public let icon: String
    public let description: String
    public let codeExample: String?
    public let unlockedBy: String  // lesson/challenge id that unlocks this

    public enum CompendiumCategory: String, Codable, CaseIterable {
        case concepts    = "Concepts"
        case patterns    = "Patterns"
        case tools       = "Tools"
        case debugging   = "Debugging"
        case trivia      = "Trivia"

        public var emoji: String {
            switch self {
            case .concepts:  return "💡"
            case .patterns:  return "🧩"
            case .tools:     return "🔧"
            case .debugging: return "🐛"
            case .trivia:    return "⭐"
            }
        }

        public var color: String {
            switch self {
            case .concepts:  return "#7B6BD8"
            case .patterns:  return "#6BCB77"
            case .tools:     return "#F5A623"
            case .debugging: return "#E04040"
            case .trivia:    return "#D4960A"
            }
        }
    }

    public init(id: String, category: CompendiumCategory, name: String, icon: String,
                description: String, codeExample: String?, unlockedBy: String) {
        self.id = id
        self.category = category
        self.name = name
        self.icon = icon
        self.description = description
        self.codeExample = codeExample
        self.unlockedBy = unlockedBy
    }
}

public struct Compendium {
    /// All discoverable entries
    public static let all: [CompendiumEntry] = [
        // Concepts
        CompendiumEntry(id: "c_variables", category: .concepts, name: "Variables", icon: "📦",
            description: "Named containers that store values. Like labeled boxes for your data.",
            codeExample: "let name = \"Byte\"\nvar score = 100", unlockedBy: "variables_types"),
        CompendiumEntry(id: "c_functions", category: .concepts, name: "Functions", icon: "⚙️",
            description: "Reusable blocks of code. Write once, call anywhere.",
            codeExample: "func greet(name: String) {\n    print(\"Hello, \\(name)!\")\n}", unlockedBy: "functions"),
        CompendiumEntry(id: "c_loops", category: .concepts, name: "Loops", icon: "🔁",
            description: "Repeat actions without writing the same code over and over.",
            codeExample: "for i in 1...5 {\n    print(\"Attempt \\(i)\")\n}", unlockedBy: "control_flow"),
        CompendiumEntry(id: "c_conditionals", category: .concepts, name: "Conditionals", icon: "🔀",
            description: "Make decisions in code. If this, do that. Otherwise, do something else.",
            codeExample: "if score > 90 {\n    print(\"A+\")\n} else {\n    print(\"Keep going!\")\n}", unlockedBy: "control_flow"),
        CompendiumEntry(id: "c_arrays", category: .concepts, name: "Arrays", icon: "📋",
            description: "Ordered lists of items. Perfect when you have many of the same type.",
            codeExample: "let pets = [\"Byte\", \"Nova\", \"Crash\"]\nprint(pets[0]) // Byte", unlockedBy: "arrays_lists"),
        CompendiumEntry(id: "c_optionals", category: .concepts, name: "Optionals", icon: "❓",
            description: "A value that might exist... or might be nil. Schrödinger's variable.",
            codeExample: "var nickname: String? = nil\nnickname = \"B\" // now it exists!", unlockedBy: "objects"),

        // Patterns
        CompendiumEntry(id: "p_dryrule", category: .patterns, name: "DRY Principle", icon: "🏜️",
            description: "Don't Repeat Yourself. If you copy-paste code, make it a function.",
            codeExample: nil, unlockedBy: "functions"),
        CompendiumEntry(id: "p_naming", category: .patterns, name: "Good Naming", icon: "🏷️",
            description: "Code is read more than it's written. Name things so future-you understands.",
            codeExample: "// Bad: let x = 42\n// Good: let maxRetries = 42", unlockedBy: "prompt_clarity"),
        CompendiumEntry(id: "p_decompose", category: .patterns, name: "Decomposition", icon: "🧱",
            description: "Break big problems into small pieces. Solve each piece, then combine.",
            codeExample: nil, unlockedBy: "scope_mgmt"),

        // Tools
        CompendiumEntry(id: "t_terminal", category: .tools, name: "Terminal", icon: "⌨️",
            description: "The command line — where power users live. Faster than clicking.",
            codeExample: "ls -la    # list files\ncd ~/code # change directory", unlockedBy: "tool_basics"),
        CompendiumEntry(id: "t_git", category: .tools, name: "Git", icon: "🌿",
            description: "Version control. Save checkpoints of your code so you can always go back.",
            codeExample: "git add .\ngit commit -m \"feat: add login\"", unlockedBy: "documentation"),
        CompendiumEntry(id: "t_debugger", category: .tools, name: "Debugger", icon: "🔍",
            description: "Step through code line by line to find where things go wrong.",
            codeExample: nil, unlockedBy: "error_reading"),

        // Debugging
        CompendiumEntry(id: "d_syntax", category: .debugging, name: "Syntax Errors", icon: "🚫",
            description: "Missing semicolons, unclosed brackets — the compiler catches these for you.",
            codeExample: nil, unlockedBy: "error_reading"),
        CompendiumEntry(id: "d_logic", category: .debugging, name: "Logic Bugs", icon: "🧠",
            description: "Code runs fine but does the wrong thing. The sneakiest bugs.",
            codeExample: nil, unlockedBy: "code_judgment"),
        CompendiumEntry(id: "d_rubber_duck", category: .debugging, name: "Rubber Duck Method", icon: "🦆",
            description: "Explain your code to a rubber duck. You'll find the bug while explaining.",
            codeExample: nil, unlockedBy: "prompt_iteration"),

        // Trivia
        CompendiumEntry(id: "x_firstbug", category: .trivia, name: "The First Bug", icon: "🦋",
            description: "In 1947, a moth was found stuck in a Harvard computer. The first literal 'bug'.",
            codeExample: nil, unlockedBy: "hello_world"),
        CompendiumEntry(id: "x_ada", category: .trivia, name: "Ada Lovelace", icon: "👩‍💻",
            description: "The world's first programmer, writing code in the 1840s — before computers existed.",
            codeExample: nil, unlockedBy: "hello_world"),
        CompendiumEntry(id: "x_404", category: .trivia, name: "Why 404?", icon: "🔢",
            description: "The room at CERN where the first web server lived was Room 404.",
            codeExample: nil, unlockedBy: "tool_basics"),
    ]
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Cosmetic Items (Collection System)
// ═══════════════════════════════════════════════════════════════════════════════

public struct CosmeticItem: Identifiable, Codable {
    public let id: String
    public let name: String
    public let emoji: String
    public let category: CosmeticCategory
    public let rarity: Rarity
    public let coinCost: Int?          // nil = not purchasable (achievement only)
    public let unlockedBy: String?     // achievement/milestone that grants it, or nil if shop-only

    public enum CosmeticCategory: String, Codable, CaseIterable {
        case hat        = "Hats"
        case accessory  = "Accessories"
        case background = "Backgrounds"
        case effect     = "Effects"

        public var emoji: String {
            switch self {
            case .hat:        return "🎩"
            case .accessory:  return "✨"
            case .background: return "🖼️"
            case .effect:     return "💫"
            }
        }
    }

    public enum Rarity: String, Codable {
        case common    = "Common"
        case uncommon  = "Uncommon"
        case rare      = "Rare"
        case legendary = "Legendary"

        public var color: String {
            switch self {
            case .common:    return "#999999"
            case .uncommon:  return "#6BCB77"
            case .rare:      return "#7B6BD8"
            case .legendary: return "#D4960A"
            }
        }
    }

    public init(id: String, name: String, emoji: String, category: CosmeticCategory,
                rarity: Rarity, coinCost: Int?, unlockedBy: String?) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.category = category
        self.rarity = rarity
        self.coinCost = coinCost
        self.unlockedBy = unlockedBy
    }
}

public struct CosmeticShop {
    public static let all: [CosmeticItem] = [
        // Hats
        CosmeticItem(id: "hat_none", name: "No Hat", emoji: "➖", category: .hat, rarity: .common, coinCost: 0, unlockedBy: nil),
        CosmeticItem(id: "hat_dev", name: "Dev Beanie", emoji: "🧢", category: .hat, rarity: .common, coinCost: 50, unlockedBy: nil),
        CosmeticItem(id: "hat_wizard", name: "Code Wizard Hat", emoji: "🧙", category: .hat, rarity: .uncommon, coinCost: 100, unlockedBy: nil),
        CosmeticItem(id: "hat_crown", name: "Bug Slayer Crown", emoji: "👑", category: .hat, rarity: .rare, coinCost: nil, unlockedBy: "complete_tier_3"),
        CosmeticItem(id: "hat_halo", name: "Golden Compiler", emoji: "😇", category: .hat, rarity: .legendary, coinCost: nil, unlockedBy: "complete_all_kingdoms"),

        // Accessories
        CosmeticItem(id: "acc_glasses", name: "Debug Glasses", emoji: "🤓", category: .accessory, rarity: .common, coinCost: 40, unlockedBy: nil),
        CosmeticItem(id: "acc_scarf", name: "Terminal Scarf", emoji: "🧣", category: .accessory, rarity: .uncommon, coinCost: 80, unlockedBy: nil),
        CosmeticItem(id: "acc_cape", name: "Full-Stack Cape", emoji: "🦸", category: .accessory, rarity: .rare, coinCost: nil, unlockedBy: "streak_30"),
        CosmeticItem(id: "acc_wings", name: "Pixel Wings", emoji: "🪽", category: .accessory, rarity: .legendary, coinCost: nil, unlockedBy: "prestige_1"),

        // Backgrounds
        CosmeticItem(id: "bg_default", name: "Cream", emoji: "📄", category: .background, rarity: .common, coinCost: 0, unlockedBy: nil),
        CosmeticItem(id: "bg_forest", name: "Code Forest", emoji: "🌲", category: .background, rarity: .common, coinCost: 60, unlockedBy: nil),
        CosmeticItem(id: "bg_space", name: "Digital Space", emoji: "🌌", category: .background, rarity: .uncommon, coinCost: 120, unlockedBy: nil),
        CosmeticItem(id: "bg_matrix", name: "Matrix Rain", emoji: "🟢", category: .background, rarity: .rare, coinCost: nil, unlockedBy: "complete_tier_2"),
        CosmeticItem(id: "bg_golden", name: "Golden Hall", emoji: "🏛️", category: .background, rarity: .legendary, coinCost: nil, unlockedBy: "level_50"),

        // Effects
        CosmeticItem(id: "fx_sparkle", name: "Sparkle Trail", emoji: "✨", category: .effect, rarity: .uncommon, coinCost: 90, unlockedBy: nil),
        CosmeticItem(id: "fx_fire", name: "Fire Aura", emoji: "🔥", category: .effect, rarity: .rare, coinCost: nil, unlockedBy: "streak_14"),
        CosmeticItem(id: "fx_rainbow", name: "Rainbow Glow", emoji: "🌈", category: .effect, rarity: .legendary, coinCost: nil, unlockedBy: "compendium_complete"),
    ]
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Pet Abilities (Character-Specific Powers)
// ═══════════════════════════════════════════════════════════════════════════════

public struct PetAbility: Identifiable {
    public let id: String
    public let characterId: String   // which pet has this ability
    public let name: String
    public let emoji: String
    public let description: String
    public let unlocksAtTier: Int    // evolution stage required

    public init(id: String, characterId: String, name: String, emoji: String,
                description: String, unlocksAtTier: Int) {
        self.id = id
        self.characterId = characterId
        self.name = name
        self.emoji = emoji
        self.description = description
        self.unlocksAtTier = unlocksAtTier
    }

    public static let all: [PetAbility] = [
        // Byte — The Chaotic Core
        PetAbility(id: "byte_hint", characterId: "byte", name: "Memory Leak", emoji: "💧",
            description: "Reveals a subtle hint by 'leaking' the answer format", unlocksAtTier: 2),
        PetAbility(id: "byte_debug", characterId: "byte", name: "Debug Scan", emoji: "🔍",
            description: "Highlights the line with the error in code challenges", unlocksAtTier: 3),
        PetAbility(id: "byte_rewind", characterId: "byte", name: "Stack Rewind", emoji: "⏪",
            description: "Undo a wrong answer without losing a heart", unlocksAtTier: 4),

        // Nova — The Firestarter
        PetAbility(id: "nova_speed", characterId: "nova", name: "Overclock", emoji: "⚡",
            description: "+25% bonus XP for completing lessons under the time target", unlocksAtTier: 2),
        PetAbility(id: "nova_streak", characterId: "nova", name: "Flame Shield", emoji: "🛡️",
            description: "Streak freeze activates automatically once per week", unlocksAtTier: 3),
        PetAbility(id: "nova_double", characterId: "nova", name: "Supernova", emoji: "💥",
            description: "Double XP on the first lesson of each day", unlocksAtTier: 4),

        // Crash — The Brawler Bug
        PetAbility(id: "crash_tough", characterId: "crash", name: "Thick Skin", emoji: "🪨",
            description: "+1 bonus heart (6 total instead of 5)", unlocksAtTier: 2),
        PetAbility(id: "crash_smash", characterId: "crash", name: "Bug Smash", emoji: "🔨",
            description: "Eliminates one wrong answer in multiple-choice", unlocksAtTier: 3),
        PetAbility(id: "crash_rage", characterId: "crash", name: "Rage Mode", emoji: "😤",
            description: "After 3 wrong answers, next answer is auto-correct", unlocksAtTier: 4),

        // Luna — The Creative Builder
        PetAbility(id: "luna_inspire", characterId: "luna", name: "Inspiration", emoji: "💡",
            description: "Shows a creative hint that approaches the problem differently", unlocksAtTier: 2),
        PetAbility(id: "luna_heal", characterId: "luna", name: "Gentle Heal", emoji: "💖",
            description: "Restores 1 heart when you get 3 correct in a row", unlocksAtTier: 3),
        PetAbility(id: "luna_create", characterId: "luna", name: "Creative Flow", emoji: "🎨",
            description: "Unlock bonus creative challenges with extra XP", unlocksAtTier: 4),

        // Sage — The Zen Debugger
        PetAbility(id: "sage_calm", characterId: "sage", name: "Zen Focus", emoji: "🧘",
            description: "Timer pauses for 10 seconds in timed challenges", unlocksAtTier: 2),
        PetAbility(id: "sage_wisdom", characterId: "sage", name: "Ancient Wisdom", emoji: "📜",
            description: "Shows the 'why' behind each answer, even wrong ones", unlocksAtTier: 3),
        PetAbility(id: "sage_foresight", characterId: "sage", name: "Foresight", emoji: "🔮",
            description: "Preview the next question before answering current one", unlocksAtTier: 4),

        // Glitch — The Punk Hacker
        PetAbility(id: "glitch_skip", characterId: "glitch", name: "Backdoor", emoji: "🚪",
            description: "Skip one question per lesson without penalty", unlocksAtTier: 2),
        PetAbility(id: "glitch_hack", characterId: "glitch", name: "Exploit", emoji: "💀",
            description: "Reveal the correct answer once per day (costs double coins)", unlocksAtTier: 3),
        PetAbility(id: "glitch_chaos", characterId: "glitch", name: "Chaos Mode", emoji: "🌀",
            description: "Randomize lesson order for surprise bonus XP", unlocksAtTier: 4),

        // Null — The Chaos Gremlin
        PetAbility(id: "null_random", characterId: "null", name: "Null Pointer", emoji: "❓",
            description: "Random chance (20%) to get double XP on any answer", unlocksAtTier: 2),
        PetAbility(id: "null_joke", characterId: "null", name: "Comedy Hour", emoji: "😂",
            description: "Wrong answers show a funny joke instead of just feedback", unlocksAtTier: 3),
        PetAbility(id: "null_undefined", characterId: "null", name: "Undefined Behavior", emoji: "🎲",
            description: "Once per day, random amazing reward (2x coins, free heart, bonus XP)", unlocksAtTier: 4),
    ]

    /// Get abilities for a specific character
    public static func forCharacter(_ id: String) -> [PetAbility] {
        all.filter { $0.characterId == id }
    }

    /// Get unlocked abilities for a character at a given tier
    public static func unlockedAbilities(characterId: String, tier: Int) -> [PetAbility] {
        all.filter { $0.characterId == characterId && $0.unlocksAtTier <= tier }
    }
}
