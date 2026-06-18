import SwiftUI

// =============================================================================
// MARK: - ExpertContent
// =============================================================================

/// Static content for the Learn tab — experts, case studies, and mentor Q&A.
/// All data is defined inline. No network fetch required.
enum ExpertContent {

    // =========================================================================
    // MARK: - Experts
    // =========================================================================

    static let experts: [Expert] = [
        Expert(
            id: "expert_astro",
            name: "Astro Tran",
            role: "Founder of MURROR \u{00B7} Built 3 shipped products",
            bio: "Learn how to go from idea to shipped product. Real stories from building Codepet, real mistakes, real lessons.",
            avatarColor: "#9538CF",
            initials: "AT"
        )
    ]

    // =========================================================================
    // MARK: - Case Studies
    // =========================================================================

    static let caseStudies: [CaseStudy] = [

        // ---------------------------------------------------------------------
        // Case Study 1 — How I shipped Codepet's MVP in 7 days
        // ---------------------------------------------------------------------
        CaseStudy(
            id: "cs_codepet_mvp",
            expertId: "expert_astro",
            title: "How I shipped Codepet\u{2019}s MVP in 7 days",
            icon: "rocket.fill",
            color: "#1C40CF",
            tags: ["SwiftUI", "Firebase", "App Store"],
            chapters: [

                // Chapter 1
                Chapter(
                    id: "cs_codepet_mvp_ch1",
                    title: "Deciding what to cut",
                    narrative: """
                    I started Codepet with a Notion doc that had 47 features. Cosmetic shops, multiplayer coding battles, an AI tutor that adapts to your learning style, achievement badges, dark mode, sound effects, a compendium of every coding concept \u{2014} the works. I spent two full days just writing feature specs. Then I looked at the calendar: seven days to ship.

                    The hardest part of building a product is not writing the code. It is deleting the ideas you love. I went through that list with a single question: "Can a user open the app, pick a character, finish one lesson, and feel like they accomplished something without this feature?" If the answer was yes, the feature got cut. Forty-seven became eight. No cosmetic shop. No sound effects. No dark mode. Just: onboarding, character selection, four kingdoms of lessons, a pet care system, hearts, coins, and a world map.

                    Saying no felt terrible. Every cut feature was something I had already imagined a user enjoying. But here is the thing nobody tells you: an unshipped app with 47 features helps exactly zero people. A shipped app with 8 features can change someone's morning. I wrote "SHIP > PERFECT" on a sticky note and put it on my monitor. It stayed there the whole week.

                    The key insight was that cutting features is not about lowering your standards. It is about focusing your standards on fewer things so each one actually works. Those 8 features that survived? They got all my attention, all my testing, all my care. And they shipped.
                    """,
                    keyLesson: "A shipped app with 8 features beats an unshipped app with 47.",
                    challenge: "Write down every feature you want in your app. Now cross out everything that is not essential to the core experience. How many survived?",
                    codeSnippet: nil
                ),

                // Chapter 2
                Chapter(
                    id: "cs_codepet_mvp_ch2",
                    title: "Building the core loop first",
                    narrative: """
                    Before I touched any UI polish, I built the core loop: pick a character, start a lesson, answer questions, earn coins. That is it. No animations, no gradients, no pixel art \u{2014} just gray rectangles and system fonts wired to real state. I needed to know whether the loop felt right before I made it look right.

                    In SwiftUI, this meant getting my state architecture solid from day one. I created an AppState class as an ObservableObject and passed it through the environment. Every view that needed to know about the user's progress \u{2014} which lessons were completed, how many coins they had, what character they picked \u{2014} just read from that single source of truth. No passing data through five levels of initializers. One object, injected once, readable everywhere.

                    I made the loop playable within the first 12 hours. It looked awful. The "character select" was a list of text names. The "lesson" was a VStack with a question and two buttons. But I could tap through the entire flow: splash screen, pick "Byte", answer three questions, see my coin count go up. That ugly prototype told me something important \u{2014} the reward moment after completing a lesson felt genuinely satisfying, even without polish. The loop worked.

                    There is a reason game designers talk about "finding the fun" early. If your core loop does not feel good with placeholder art, no amount of polish will save it. But if it does feel good? Then every hour you spend on visuals and animation is amplifying something that already works.
                    """,
                    keyLesson: "Build the core loop with ugly placeholders first. If it feels good without polish, polish will make it great.",
                    challenge: nil,
                    codeSnippet: """
                    // The core state flow that powers everything
                    class AppState: ObservableObject {
                        @Published var selectedCharacter: String = ""
                        @Published var completedLessons: Set<String> = []
                        @Published var coins: Int = 0

                        func completeLesson(_ id: String) {
                            completedLessons.insert(id)
                            coins += 10
                            // That's it. Two lines. The UI updates automatically
                            // because SwiftUI observes @Published properties.
                        }
                    }

                    // Any view can read and react to this state:
                    struct LessonView: View {
                        @EnvironmentObject var appState: AppState

                        var body: some View {
                            Text("Coins: \\(appState.coins)")
                        }
                    }
                    """
                ),

                // Chapter 3
                Chapter(
                    id: "cs_codepet_mvp_ch3",
                    title: "Pixel art on a deadline",
                    narrative: """
                    I am not an artist. I have never taken a drawing class. But Codepet needed characters, and I had no budget to hire an illustrator with three days left on the clock. So I opened a pixel art editor and gave myself one rule: 16 by 16 pixels, four colors per character, no exceptions.

                    Constraints turned out to be a superpower. With only 256 pixels to work with, every single dot matters. You cannot overthink a 16x16 sprite \u{2014} there is literally no room for it. Byte, the first character I made, took 20 minutes. A simple round body, two dot eyes, a tiny highlight on the forehead, and a color accent. He looked like a character. Not a masterpiece, but a character. I made all eight in a single afternoon.

                    The biggest technical lesson was rendering. Pixel art looks terrible if your framework applies bilinear or bicubic interpolation \u{2014} the crisp edges turn into a blurry mess. In SwiftUI, the fix is one line: `.interpolation(.none)`. That tells the renderer to use nearest-neighbor scaling, which keeps every pixel sharp no matter the display size. I added it to every single Image view in the app and the characters went from smudgy blobs to clean, intentional sprites.

                    The honest truth is that pixel art is the most forgiving art style for a developer on a deadline. The low resolution hides your lack of skill. The limited palette means you cannot make ugly color choices. And players associate pixel art with charm, not cheapness. If you are building a side project and you think you cannot do the art \u{2014} try 16x16. You might surprise yourself.
                    """,
                    keyLesson: "Constraints are a superpower. A 16x16 grid with 4 colors forces clarity and ships fast.",
                    challenge: "Open any pixel art tool and design a 16x16 character using only 4 colors. Give it a name. Spend no more than 15 minutes.",
                    codeSnippet: nil
                ),

                // Chapter 4
                Chapter(
                    id: "cs_codepet_mvp_ch4",
                    title: "Firebase in 2 hours",
                    narrative: """
                    Day five. I had a working app with no backend. Everything lived in UserDefaults, which meant progress vanished if you deleted the app or switched machines. I needed cloud sync and user accounts, and I needed them today. Firebase was the obvious choice \u{2014} I had used it before, the Swift SDK is solid, and the free tier covers everything an MVP needs.

                    The setup took about 40 minutes: create a project in the Firebase console, download the GoogleService-Info.plist, add the SPM dependencies, call FirebaseApp.configure() in my app's init. Then I wired up three auth methods. Email and password was straightforward. Google Sign-In required a URL scheme in the Info.plist and a small coordinator for the sign-in flow. But the real unlock was anonymous auth \u{2014} users could start using the app immediately, no sign-up friction at all, and convert to a full account later if they wanted.

                    Firestore was even faster. I created a single collection called "users" where each document is keyed by the Firebase UID. When the user completes a lesson or earns coins, I write the full state to their document. When they reopen the app, I read it back. The entire sync service was about 80 lines of Swift. No complex schema, no migrations, no ORM. Just dictionaries going in and dictionaries coming out.

                    Two hours from "no backend" to "accounts and cloud sync work." That is the power of choosing boring, well-documented tools for your MVP. I could have spent a week building a custom backend with Vapor or evaluating newer platforms. Instead I picked the thing I knew, shipped it, and moved on to the next problem.
                    """,
                    keyLesson: "Pick the tool you know, not the tool that is trendy. Speed of execution beats technical novelty in an MVP.",
                    challenge: nil,
                    codeSnippet: """
                    // Firebase setup — this is literally the entire init
                    import Firebase

                    @main
                    struct CodePetApp: App {
                        init() {
                            FirebaseApp.configure()
                        }

                        var body: some Scene {
                            WindowGroup {
                                ContentView()
                                    .environmentObject(AuthManager())
                                    .environmentObject(AppState())
                            }
                        }
                    }

                    // Anonymous auth — zero friction onboarding
                    func signInAnonymously() async throws {
                        let result = try await Auth.auth().signInAnonymously()
                        // User is now authenticated. No email, no password,
                        // no friction. They can link a real account later.
                        print("Anonymous UID: \\(result.user.uid)")
                    }
                    """
                ),

                // Chapter 5
                Chapter(
                    id: "cs_codepet_mvp_ch5",
                    title: "The launch day panic",
                    narrative: """
                    Day seven. Sunday night. I had been coding for 14 hours straight and the app was ready. All eight lessons worked, pet care was functional, the pixel art looked sharp, cloud sync was stable. I archived the build in Xcode, uploaded it to App Store Connect, and waited for the processing to finish. Then the email arrived: "Invalid Binary."

                    The problem was entitlements. My app had a network access entitlement configured for a sandbox environment that does not exist in production builds. I had copy-pasted a configuration from a tutorial months ago and never cleaned it up. The fix took four minutes \u{2014} delete one line from the entitlements file and re-archive. But finding the problem took an hour of reading Apple's vague error messages and comparing entitlement files character by character. It was 10:47 PM.

                    I uploaded the fixed build, waited another 20 minutes for processing, held my breath, and it went through. TestFlight build available at 11:12 PM. I submitted for App Store review at 11:31 PM. Then I closed my laptop and sat in silence for about five minutes, because the adrenaline crash after a deadline like that is something else entirely.

                    Here is what I wish someone had told me: your first submission will fail. Something will be wrong with the signing, the entitlements, the provisioning profile, or the App Store metadata. Build in buffer time for at least two failed uploads. And more importantly \u{2014} ship it anyway. Ship it imperfect, ship it nervous, ship it at 11 PM on a Sunday. The difference between people who have shipped an app and people who have not is usually just the willingness to hit submit when it does not feel ready. It will never feel ready.
                    """,
                    keyLesson: "Your first upload will fail. Build in buffer time, fix the issue, and ship it anyway. Done beats perfect.",
                    challenge: "If you have a project you have been \"almost finishing\" \u{2014} set a hard deadline this week. Tell someone about it. Deadlines with witnesses actually work.",
                    codeSnippet: nil
                )
            ]
        ),

        // ---------------------------------------------------------------------
        // Placeholder Case Study 2
        // ---------------------------------------------------------------------
        CaseStudy(
            id: "cs_first_100_users",
            expertId: "expert_astro",
            title: "Finding your first 100 users",
            icon: "person.2.fill",
            color: "#029902",
            tags: ["Marketing", "Community", "Feedback"],
            chapters: []
        ),

        // ---------------------------------------------------------------------
        // Placeholder Case Study 3
        // ---------------------------------------------------------------------
        CaseStudy(
            id: "cs_design_non_designer",
            expertId: "expert_astro",
            title: "Designing when you\u{2019}re not a designer",
            icon: "paintpalette.fill",
            color: "#9538CF",
            tags: ["UI patterns", "Pixel art", "Color"],
            chapters: []
        ),

        // ---------------------------------------------------------------------
        // Placeholder Case Study 4
        // ---------------------------------------------------------------------
        CaseStudy(
            id: "cs_five_bugs",
            expertId: "expert_astro",
            title: "The 5 bugs that almost killed my launch",
            icon: "ladybug.fill",
            color: "#E24B4A",
            tags: ["Debugging", "Testing", "Resilience"],
            chapters: []
        )
    ]

    // =========================================================================
    // MARK: - Mentor Q&A
    // =========================================================================

    static let mentorQAs: [MentorQA] = [

        MentorQA(
            id: "qa_what_to_build_first",
            expertId: "expert_astro",
            question: "How do you decide what to build first?",
            hint: "About prioritization and MVP scope",
            iconName: "lightbulb.fill",
            iconColor: "#1A9E8F",
            answer: """
            I ask one question: "What is the smallest thing a user can do in this app that would make them want to come back tomorrow?" Not the full feature set, not the vision \u{2014} just the single interaction that creates a spark. For Codepet, that was: pick a character, complete one lesson, see your pet react. Everything else \u{2014} the world map, the coin economy, the pet care stats \u{2014} exists to support that moment.

            Once you find that core moment, build backward from it. What is the minimum state you need? What is the shortest path through your UI to reach it? I literally drew the flow on paper: splash \u{2192} character select \u{2192} first lesson \u{2192} reward screen. Four screens. If those four screens do not work, nothing else matters. I spent the first two days making sure that flow felt satisfying with placeholder art before I touched anything else in the app.

            A trap I fell into early on was building "infrastructure" first \u{2014} setting up the database schema, designing the architecture, abstracting things into protocols. It feels productive, but you end up with a beautiful backend serving an app that nobody has used yet. Build the thing the user touches first. Refactor the guts later. Your users will never compliment your architecture, but they will tell you if that first lesson felt fun.
            """,
            followUps: [
                "How do you know when your core loop is working?",
                "What if I have two features and I cannot decide which is more important?",
                "How much architecture planning should I do before writing code?"
            ]
        ),

        MentorQA(
            id: "qa_staying_motivated",
            expertId: "expert_astro",
            question: "How do you stay motivated when stuck?",
            hint: "About momentum and small wins",
            iconName: "clock.fill",
            iconColor: "#7B6BD8",
            answer: """
            I do not rely on motivation. Motivation is a feeling, and feelings are unreliable. What I rely on is momentum, and momentum comes from finishing small things. When I am stuck on a hard problem \u{2014} say, debugging a Firestore sync issue that makes no sense \u{2014} I step away from it and go fix something tiny. Adjust a color value. Align a piece of text. Add a missing accessibility label. Something I can finish in five minutes and commit.

            That small commit breaks the spell. The stuck feeling is usually not about the technical problem; it is about the narrative in your head that says "I am not making progress." One finished task, no matter how small, rewrites that narrative. Suddenly you are a person who is shipping things again. Then you go back to the hard problem with different energy.

            The other thing that saves me is talking out loud. Not to another person \u{2014} just to myself, or to a rubber duck, or to my dog who does not care. I describe the problem as if I am explaining it to someone who has never coded. About half the time, I solve it mid-sentence. The act of organizing your thoughts into words forces you to slow down and examine assumptions you have been glossing over. It sounds silly, but it works more reliably than staring at the screen for another hour.
            """,
            followUps: [
                "How do you break a big task into smaller pieces?",
                "What do you do when you feel like your project is not good enough?",
                "How many hours a day do you actually code?"
            ]
        ),

        MentorQA(
            id: "qa_stop_coding_start_shipping",
            expertId: "expert_astro",
            question: "When should I stop coding and start shipping?",
            hint: "About perfectionism vs done",
            iconName: "chevron.left.forwardslash.chevron.right",
            iconColor: "#E07650",
            answer: """
            Here is my rule: if you are embarrassed by the things that are missing but proud of the things that are there, you are ready to ship. Codepet launched without dark mode, without sound effects, without a cosmetic shop, and without half the lessons I had planned. I was embarrassed about all of that. But the core \u{2014} picking a character, learning to code through interactive lessons, watching your pet grow \u{2014} that part worked and I was proud of it. So I shipped.

            The trap is thinking "just one more feature" will make the difference. It will not. I have never once seen a user review that said "This app would be perfect if only it had one more feature at launch." What users notice is whether the app works, whether it is delightful, and whether it respects their time. You can deliver all three with a focused feature set. You cannot deliver any of them with a bloated, half-finished feature set.

            Set a ship date before you start building and tell someone about it. Not a vague "sometime next month" \u{2014} an actual date on an actual calendar. When that date arrives, the question is not "Is it perfect?" The question is "Does the core experience work?" If yes, submit the build. You can ship updates every week after that. Version 1.0 is not your only chance; it is your first chance. Treat it that way and the pressure drops dramatically.
            """,
            followUps: [
                "How do you handle negative feedback after launching?",
                "What should go in version 1.1 versus version 2.0?",
                "How often should I ship updates after the initial launch?"
            ]
        )
    ]
}
