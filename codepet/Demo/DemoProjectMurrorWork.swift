// codepet/Demo/DemoProjectMurrorWork.swift
#if DEBUG
import Foundation

/// What each of Murror's eight pets produces.
///
/// **Eight tasks, eight distinct kinds**, so the demo also walks eight of the twelve viewers
/// without any task having been chosen to fill a slot. The four kinds NOT reachable from a
/// Murror run — `post`, `email`, `calendar`, `text` — are why `-seedLibrary` still has a reason
/// to exist.
///
/// Each body is written in its pet's register rather than one house voice: `crash` (Finance) is
/// blunt, `sage` (Support) is patient, `glitch` (Ops/Legal) is precise about edges, `luna`
/// (Design) talks about how it feels, `nova` (Marketing/Sales) leads with the promise, `byte`
/// (Engineering) is concrete about mechanics. A demo where all eight sound identical would show
/// eight cards and one pet.
///
/// **Keyword order matters.** `deliverable(for:)` takes the first entry with any match, so
/// `"email capture"` sits ahead of anything matching `"email"`, and the catch-all is last with
/// no keywords of its own — it is reached by the `?? last` fallback.
extension DemoProject {

    static var murrorDeliverables: [DemoDeliverable] {
        [
            // ── nova · Marketing — THE WEBSITE ──────────────────────────────────────────────
            // The only entry whose payload reaches `SiteViewer`, which renders it as a real
            // page in a WKWebView. `accent` is Murror's midnight navy and NOT its warm gold:
            // `buildHTML` paints `accent` behind white text in three places (`.btn.p`,
            // `.step .n`, and the whole `.final` block), so a pale colour renders
            // white-on-pale — and `safeHex` validates hex SYNTAX, not contrast, so nothing
            // else in the codebase would catch it.
            // ── THE RESEARCH THE REST OF THE BOARD HANGS OFF ────────────────────────────────
            //
            // These three are `done` in the board and FILED in `DemoProject.filed`, which is
            // what lets the demo show departments building on each other: `UpstreamWork`
            // reads the library, so an unfiled prerequisite feeds nothing forward. They are
            // real artifacts rather than the catch-all on purpose — a downstream run that
            // inherits filler produces filler, and the credit line would then be true about
            // a lie. Keywords sit FIRST so their titles cannot fall through to a later,
            // more general entry.
            DemoDeliverable(
                keywords: ["12 people", "lonely", "interviews"],
                kind: "doc",
                body: """
                Twelve conversations, none of them about the app. What they have in common is \
                not loneliness — it is a specific evening that already happened.

                **The pattern, stated once**
                Eleven of the twelve could name the last time they wanted to reach out and did \
                not. Nobody was short of contacts. What stopped them was not knowing what they \
                would say once the person picked up.

                **What they actually said**
                - "I didn't want to dump it on her." — the fear is being a burden, not being alone.
                - "By the time I worked out what was wrong it was 1am and too late to text."
                - "I journal when it's already bad. Never before." — journaling is triage, not practice.
                - "I know I'm off. I couldn't tell you which off." — naming the feeling is the missing step.

                **The one who disagreed**
                One person found the whole framing insulting: she does not want help understanding \
                herself, she wants fewer obligations. Keep her in mind — she is the person who \
                will find any version of this patronising, and she is not wrong about herself.

                **What this rules out**
                A mood tracker. Every one of them had tried one and stopped; none could say what \
                it had ever told them. Numbers on a chart are not the thing that was missing.

                **What it points at**
                The gap is between feeling something and being able to say it to a person. \
                Anything that only closes the first half is a diary, and they already have one.
                """),

            DemoDeliverable(
                keywords: ["journaling and companion", "scan the", "landscape"],
                kind: "doc",
                body: """
                What the journaling and companion apps promise, what they do on day three, and \
                where the gap actually is.

                **What everyone promises**
                Understand yourself. Every app in the category, near-verbatim.

                **What day three looks like**
                - **Journals** — a blank page and a streak counter. The page does not get easier \
                to face on day three; the counter gets harder to lose.
                - **Mood trackers** — five emoji and a chart nobody reads back. Fast to fill in, \
                which is exactly why it costs nothing and returns nothing.
                - **AI companions** — endlessly available and endlessly agreeable. They keep the \
                conversation inside the app, which is where it stays.

                **The gap, in one line**
                Every one of them ends with the user understanding themselves slightly better, \
                alone. Not one of them ends with a person on the other end.

                **Where that leaves {{product}}**
                The category has solved the private half and left the second half untouched. \
                "AI that brings people closer" is not a softer version of what these do — it is \
                the half they all stop before.

                **Two things to steal**
                A first session that asks for nothing (the best onboarding here asks for no \
                account), and crisis routing that is built in rather than bolted on.

                **One thing to refuse**
                Streaks. Every app in this set has them, and every person we interviewed had \
                broken one and stopped.
                """),

            DemoDeliverable(
                keywords: ["visual direction", "brand"],
                kind: "doc",
                body: """
                The visual direction, decided against one worry: that naming a feeling in an app \
                feels like being graded.

                **The call**
                Warm dark. Not clinical white, not therapy-app pastel. The screen should feel \
                like a lit room at night rather than a form to fill in.

                **Palette**
                - Ground: deep navy, near-black — `#12141C`. The room, not the paper.
                - Warmth: a single amber `#E8A24C`, used for one thing per screen and nothing else.
                - Text: warm off-white `#F2EFE9`. Pure white on navy reads as a dialog box.
                - No red anywhere in the ordinary flow. Red is reserved for the crisis path, so \
                it has to mean only that.

                **Type**
                One serif for the user's own words, one clean sans for everything {{product}} \
                says. The distinction is load-bearing: what you wrote should not look like what \
                the app wrote.

                **What the amber is for**
                The single next action. Never a decoration, never two per screen. If two things \
                are amber, neither is.

                **What this rules out**
                Progress rings, badges, confetti, streak flames. Anything that scores the user \
                contradicts the one worry above.

                **The test**
                Screenshot any screen and ask: does this look like a room, or a report card? \
                If it is a report card, the amber is doing too much or the serif is missing.
                """),

                        DemoDeliverable(
                keywords: ["landing page", "landing", "website"],
                kind: "site",
                body: """
                The page is live in your Library — open it to see it rendered.

                **What it says.** The practice, not the technology. The headline is the promise, \
                the three steps are the loop somebody actually repeats, and the four features are \
                what makes it feel safe enough to be honest in.

                **What it leaves out.** The model, the roadmap, and the word "AI" anywhere except \
                the headline — where it is the thing being promised rather than the thing being sold.

                **The one line to argue about** — *"Most of us were never taught how to understand \
                what we feel."* If that is not true of your reader, nothing below it lands.
                """,
                payloadJSON: """
                {"title":"Murror","brand":"Murror","kicker":"THE CONNECTION PRACTICE",
                 "headline":"AI that brings people","headlineHi":"closer",
                 "sub":"Most of us were never taught how to understand what we feel, or how to show up for the people we love. Murror is a daily practice for both.",
                 "ctaPrimary":"Start free","ctaSecondary":"See how it works",
                 "howEyebrow":"How it works","howTitle":"Three steps, every day",
                 "steps":[{"h":"Name what you feel","p":"Say it badly, in your own words. Murror helps you find the more accurate word for it."},
                          {"h":"See the pattern","p":"The same feeling keeps arriving on the same kind of day. That is the useful part."},
                          {"h":"Reach out","p":"One small, specific message to one real person — written by you, unstuck by us."}],
                 "featEyebrow":"What you get","featTitle":"A practice, not a feed",
                 "features":[{"h":"Emotion recognition","p":"See what you feel, in words precise enough to act on."},
                             {"h":"Relationship insights","p":"Who you have drifted from, and what you last talked about."},
                             {"h":"Small acts of care","p":"A nudge when someone you love has gone quiet."},
                             {"h":"Private by design","p":"Your feelings are not training data, and never leave with your name on them."}],
                 "quote":"I used the word lonely out loud for the first time in a year, and it was to an app. Then I sent the message.",
                 "quoteBy":"an early user",
                 "finalTitle":"Start with one feeling","finalSub":"Free to start.","finalCta":"Open Murror",
                 "accent":"#0a1430","footNote":"Made by MURROR"}
                """),

            // ── luna · Design ───────────────────────────────────────────────────────────────
            // `art` may only be "connect", "session" or "recap" — `artStandIn`'s default draws a
            // questionmark box, which reads as a broken screen rather than a stylised one.
            DemoDeliverable(
                keywords: ["first-run", "first run", "flow", "screens", "onboarding"],
                kind: "screens",
                body: """
                Four screens, install to first message sent. The whole flow is built around one \
                worry: that naming a feeling in an app feels like being graded.

                **So the first screen asks for nothing.** No account, no permissions, no "tell us \
                about yourself". The second accepts a bad answer on purpose — *"weird, I guess"* \
                has to be a valid input or nobody types anything at all.

                **The pattern screen is the payoff** and it cannot come first: it needs three days \
                of data to say anything true, so the flow promises it rather than faking it.
                """,
                payloadJSON: """
                {"screens":[
                  {"name":"Murror","time":"9:41","kick":"Welcome","title":"How are you, actually?","sub":"No account yet. Nothing leaves this screen.","art":"connect","cta":"Start","note":"Takes about a minute"},
                  {"name":"Murror","time":"9:42","kick":"Step 1","title":"Say it badly","sub":"Weird, flat, restless — whatever word you have. We will find the closer one together.","art":"session","cta":"That's it","note":"There is no wrong answer here"},
                  {"name":"Murror","time":"9:43","kick":"Step 2","title":"Three days in, a pattern","sub":"Sunday evenings, mostly. That is worth knowing.","art":"recap","cta":"Show me","note":"Needs a few days of practice first"},
                  {"name":"Murror","time":"9:44","kick":"Step 3","title":"One message","sub":"To one person who has gone quiet. You write it; we get you unstuck.","art":"connect","cta":"Write it","note":"You can skip and come back"}]}
                """),

            // ── crash · Finance ─────────────────────────────────────────────────────────────
            // `.sheet` is not a generic table — `SheetPayload` is a fixed four-input model
            // (price / waitlist / conversion / churn) and all four are required. A markdown
            // table with no payload would render an empty calculator.
            DemoDeliverable(
                keywords: ["free and paid", "pricing", "price"],
                kind: "sheet",
                body: """
                Free has to be genuinely usable or the practice never starts. Paid sells \
                **history**, not more AI.

                **Free** — unlimited check-ins, emotion recognition, 14 days of history, 3 people \
                tracked. **Practice, $6/mo** — history kept forever, patterns over time, unlimited \
                people, care nudges.

                **Why the line sits there.** 14 days is the cheapest honest free tier: long enough \
                to feel the loop, too short to hold a pattern. Patterns are what people pay for, \
                and they cost us nothing extra to serve — it is their own data.

                **What I would not do.** Charge for the check-in. A paywall in front of "how are \
                you" is the wrong business.

                $6 is under the thinking threshold and above the contempt threshold. Move the \
                sliders; change the number once 20 people have used it for a month.
                """,
                payloadJSON: """
                {"price":{"val":6,"min":0,"max":20,"step":1},
                 "waitlist":{"val":400,"min":50,"max":5000,"step":50},
                 "conversion":{"val":8,"min":1,"max":40,"step":1},
                 "churn":{"val":9,"min":1,"max":25,"step":1},
                 "summary":"At $6 and 8% of 400 converting, this covers inference and nothing else. That is the correct ambition for month one — it buys the right to keep going, not a salary."}
                """),

            // ── byte · Engineering ──────────────────────────────────────────────────────────
            // "email capture" ahead of any looser email match.
            DemoDeliverable(
                keywords: ["email capture", "signup", "sign up", "capture"],
                kind: "checklist",
                body: """
                One field, no backend, live today.

                1. **One input, type=email, autofocus.** Name, age and "how did you hear about us" \
                   all cost you signups and none of them change what you build next.
                2. **Post to a hosted form endpoint** — Tally or a Google Form. No server, no \
                   schema migration, no secret to rotate.
                3. **Confirmation in place, not a new page.** Swap the field for one line: *"You're \
                   on the list. We'll write once, when it's ready."* A redirect loses people who \
                   were only half sure.
                4. **Honour the promise literally** — one email, when it ships. Anything else and \
                   the list is worth nothing the second time.
                5. **Log the referrer** so `mur-outreach` can tell which of the three places \
                   actually worked.

                **Done when** a stranger can land, type an address, and you can see it arrive.

                **Not now:** double opt-in, a welcome sequence, or an ESP. Twenty addresses in a \
                spreadsheet do not need infrastructure.
                """),

            // ── nova · Sales ────────────────────────────────────────────────────────────────
            DemoDeliverable(
                keywords: ["first 20", "outreach", "users"],
                kind: "dms",
                body: """
                Three places where people already talk about this, and what to say in each. None \
                of these pitch — the ask is a conversation, because you still need what the \
                interviews gave you.
                """,
                payloadJSON: """
                {"messages":[
                  {"name":"r/CasualConversation","note":"cold — not a launch post",
                   "msg":"I'm building a small thing about the gap between feeling something and telling someone. Not selling it here — I'd just like to know whether that gap is real for you, or whether it's just me. What usually stops you reaching out on a bad evening?"},
                  {"name":"the group chat that went quiet","note":"warm, and the point",
                   "msg":"Random, but I've been building something about staying in touch on purpose rather than by accident. Would you try it for a week and tell me where it feels stupid? I'd rather hear that from you than from a stranger."},
                  {"name":"three therapists who write about loneliness","note":"referred by [name]",
                   "msg":"I'm building a daily practice app around naming feelings and reaching out. I am not claiming it's therapy and I don't want it mistaken for one — which is exactly why I'd value 20 minutes of your scepticism before more people see it. What would you want it to never do?"}]}
                """),

            // ── sage · Support ──────────────────────────────────────────────────────────────
            DemoDeliverable(
                keywords: ["first questions", "faq", "support"],
                kind: "doc",
                body: """
                The questions people will actually ask, answered before they have to write in. The \
                first one is the only one that matters, and the answer is no.

                **Is this therapy?**
                No. Murror is a practice, not treatment, and it is not a substitute for a \
                therapist. If you are in crisis it will say so and point you somewhere that can \
                help — it will not try to handle it itself.

                **Who reads what I write?**
                Nobody. Your entries are yours. We do not train models on them and they never \
                leave with your name attached.

                **What if I write something frightening?**
                You will see a crisis resource for your region, straight away, before anything \
                else. That path is built in and cannot be turned off.

                **What if the app names my feeling wrong?**
                It often will at first — say so, and it adjusts. It is a starting word, not a \
                diagnosis. Being corrected is how the thing gets useful.

                **Do I have to use it every day?**
                No, and a missed day is not a broken streak. There are no streaks, on purpose.

                **Can I delete everything?**
                Yes, in one tap, permanently, without emailing anyone.

                _Add every real question you receive to this list. It doubles as the script for \
                the conversation you are most afraid of having._
                """),

            // ── glitch · Operations ─────────────────────────────────────────────────────────
            DemoDeliverable(
                keywords: ["launch checklist", "launch"],
                kind: "plan",
                body: """
                **Blocking item first, because it is the one that can stop a launch outright.**

                **T-7 — the crisis path is reviewed by somebody qualified.**
                Not tested by us. Reviewed by a clinician. If this is not signed off, the launch \
                moves. Everything below is negotiable; this is not.

                **T-5**
                - Privacy policy live and linked from the first screen, not buried in a footer
                - Deletion actually deletes — verify against the database, not against the UI
                - Crisis resources correct for every region the App Store will serve

                **T-2**
                - Landing page copy frozen; the email capture tested from a phone on cellular
                - Three outreach messages sent, not drafted
                - Rollback rehearsed once, with a stopwatch

                **T-0**
                - Ship in the morning, not at night. Somebody has to be awake for the first replies.
                - Watch the crisis path specifically for the first 24 hours

                **T+7**
                - Read every entry that triggered the crisis path. All of them, by hand.
                - Kill criteria: if the crisis path misfires on anything that is not a crisis, \
                  turn the detection off and ship without it.
                """),

            // ── glitch · Legal ──────────────────────────────────────────────────────────────
            DemoDeliverable(
                keywords: ["privacy", "policy", "terms"],
                kind: "legal",
                body: """
                _Plain-language draft. The data here is the most personal kind there is, so have a \
                lawyer read this before it goes up — and read it yourself first._

                **Privacy Policy — {{product}}**

                **What we collect.** Your email address, what you write in your check-ins, and the \
                names or labels you give the people you track. Plus basic, non-identifying usage \
                counts so we know whether the thing works.

                **What we never do.** We do not sell your data. We do not train public models on \
                what you write. We do not share your entries with anyone, including the people you \
                track — they are never told they are on your list.

                **Where it lives.** Encrypted at rest and in transit. A small number of engineers \
                can reach production data; every access is logged.

                **Emotion labels are not a diagnosis** and are not shared with insurers, employers \
                or advertisers — ever, under any commercial arrangement.

                **The crisis exception.** If what you write suggests immediate danger, we show you \
                a resource. We do **not** contact anybody on your behalf, and we do not alert \
                emergency services. You stay in control of who knows.

                **Deleting.** One tap in Settings removes your account and every entry, \
                permanently, within 30 days across backups. No email required, no retention offer.

                **Children.** Murror is for 18 and over.

                **Contact** — privacy@murror.app.
                """),

            // ── The catch-all. Reached by the `?? last` fallback, so it must stay last and
            // must have no keywords of its own.
            DemoDeliverable(keywords: [], kind: "doc", body: """
            A first cut on '{{title}}' — a starting point, not the final word.

            **This week**
            1. Write down what 'done' looks like in one sentence you would be happy to be held to.
            2. Do the smallest version today. Rough is fine; unstarted is not.
            3. Show it to one of the twelve people you already interviewed before you polish anything.

            **Watch out for** — building for the person who has already understood {{product}}, \
            rather than the one who has not.
            """),
        ]
    }
}
#endif
