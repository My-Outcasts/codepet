// codepet/Services/MockVirtualCompany.swift
#if DEBUG
import Foundation

/// A room, without the network.
///
/// `VirtualCompanyClient` was the ONE client with no mock path — the single thing
/// that still reached the wire when every other call was stubbed. So convening under
/// `-CODEPET_MOCK_CHAT` or the autoplay walkthrough spent on the live
/// `virtualCompanyRun` (~$0.20 a room), unattended, while every surface around it
/// claimed to be free. It goes in at `CompanyStore.vcRunner`, the seam that already
/// existed for exactly this and that `codeRunner` uses the same way.
///
/// **The frames are wire JSON, decoded by the real `VirtualCompanyEvent.from(frame:)`.**
/// Constructing the events directly would have been shorter, but most of the payload
/// structs declare `init(from:)` and so have no memberwise init — and going around
/// the decoder is the wrong shortcut anyway: a fixture built from Swift values cannot
/// catch a renamed wire key, while this one fails loudly the moment the contract and
/// the client disagree. `docs/superpowers/specs/virtual-company-sse-contract.md` is
/// the authority for every key below.
///
/// **Written against that contract's nine rendering rules**, which `CLAUDE.md` records
/// a previous plan's sample code violating in five places. The two that bite a FIXTURE
/// hardest:
///
/// - **Rule 8: no artificial delay or fake typing.** The temptation in a demo is to
///   space the frames so the room looks like it is thinking. "Users detect it and lose
///   trust" — so every frame is yielded at once and the room arrives whole. The thing
///   worth watching is the disagreement, not a progress bar.
/// - **Rule 2: never collapse the positions into one "we agree" paragraph.**
///   Consensus is what a fixture fakes most easily, and `runSynthesis` throws on a
///   brief that buries dissent server-side. So this room genuinely disagrees: Finance
///   hard-blocks, Marketing pushes, Engineering owns the date — and it ends
///   `unresolved: true`, which rule 6 calls a valid outcome rather than an error.
enum MockVirtualCompany {

    /// Drop-in for `VirtualCompanyClient.run`.
    static func run(_ req: VirtualCompanyRequest)
        -> AsyncThrowingStream<VirtualCompanyEvent, Error> {
        AsyncThrowingStream { continuation in
            for frame in frames(ask: req.request) {
                // A frame that will not decode is dropped by `from(frame:)` and logged
                // by it. That is the same tolerance a live run has, and it means a
                // contract drift shows up as a missing card rather than a crash.
                if let event = VirtualCompanyEvent.from(frame: frame) {
                    continuation.yield(event)
                }
            }
            continuation.finish()
        }
    }

    /// Exposed so a test can assert every frame decodes — the whole value of building
    /// the fixture on the wire format rather than on Swift values.
    static func frames(ask: String) -> [SSEFrame] {
        [
            SSEFrame(event: "run_started", data: #"{"run_id":"mock-room-1"}"#),

            SSEFrame(event: "routing", data: """
            {"decision":"multi_agent",
             "agents":["finance","marketing","engineering"],
             "real_question":\(json(ask)),
             "request_type":"decision",
             "reason_per_agent":{
               "finance":"It changes when revenue starts and what the trial costs.",
               "marketing":"A paywall at launch changes the launch story itself.",
               "engineering":"Billing is the longest pole; the date moves with it."},
             "excluded":{
               "design":"No surface changes either way at this stage.",
               "legal":"No new terms until money actually moves."},
             "missing_info":[],
             "agent_meta":[
               {"agent_id":"finance","department_key":"fin"},
               {"agent_id":"marketing","department_key":"mkt"},
               {"agent_id":"engineering","department_key":"eng"}]}
            """),

            SSEFrame(event: "agent_start", data: #"{"agent_id":"finance","department_key":"fin"}"#),
            SSEFrame(event: "agent_position", data: """
            {"agent_id":"finance","department_key":"fin","position":{
              "stance":"do_not_proceed",
              "position":"Ship the paywall after launch, not before it.",
              "reasoning":"Nobody has paid yet, so there is no price to defend — only a guess to defend. Billing before a single conversation with a paying founder means building the wrong meter and then charging for it.",
              "evidence_needed":["Five founders who say what they would pay for","One week of real usage per account"],
              "risks_i_own":["Revenue starts later","Trial abuse for a few weeks"],
              "confidence":4,
              "cost_to_my_dept":"A delayed revenue start, which is recoverable.",
              "hard_blocker":"No price can be set before anyone has used the thing."}}
            """),

            SSEFrame(event: "agent_start", data: #"{"agent_id":"marketing","department_key":"mkt"}"#),
            SSEFrame(event: "agent_position", data: """
            {"agent_id":"marketing","department_key":"mkt","position":{
              "stance":"proceed",
              "position":"Launch with the paywall visible, even if generous.",
              "reasoning":"A launch is the only day the product gets free attention. A price on the page is what makes it a product rather than a demo, and the story is far harder to tell twice.",
              "evidence_needed":["Competitor pricing pages at launch"],
              "risks_i_own":["Fewer signups on day one"],
              "confidence":4,
              "cost_to_my_dept":"A smaller top of funnel on the loudest day of the year.",
              "hard_blocker":null}}
            """),

            SSEFrame(event: "agent_start", data: #"{"agent_id":"engineering","department_key":"eng"}"#),
            SSEFrame(event: "agent_position", data: """
            {"agent_id":"engineering","department_key":"eng","position":{
              "stance":"proceed_with_conditions",
              "position":"Billing can be ready, but it is the longest pole on the board.",
              "reasoning":"Stripe plus the credit meter is the one piece with no honest shortcut. It can land by the freeze if nothing else takes its slot.",
              "evidence_needed":["A frozen credit-accounting rule"],
              "risks_i_own":["The freeze date","A meter that undercounts and has to be reissued"],
              "confidence":3,
              "cost_to_my_dept":"Everything else on the board slips behind it.",
              "hard_blocker":null}}
            """),

            SSEFrame(event: "conflicts", data: """
            {"conflicts":[
              {"a":"finance","b":"marketing","kind":"BLOCKER",
               "reason":"Finance will not set a price before anyone has used the product; Marketing will not launch without one."},
              {"a":"engineering","b":"marketing","kind":"TENSION",
               "reason":"Billing at launch consumes the slot the launch itself needs."}]}
            """),

            // Rule 4 lives on this frame: each side's `what_would_change_my_mind` is
            // what teaches that disagreement is settled by evidence, not authority.
            SSEFrame(event: "negotiation_round", data: """
            {"round":1,"turns":[
              {"agent":"finance",
               "precise_disagreement":"Marketing wants a number on the page; I have no basis for the number.",
               "what_would_change_my_mind":"Five founders telling us what they would pay, before the page goes up.",
               "proposal":"Launch with the trial and a stated price, and take no card for two weeks.",
               "resolved":false},
              {"agent":"marketing",
               "precise_disagreement":"Finance is treating the price as a promise. It is a positioning statement.",
               "what_would_change_my_mind":"Evidence that a second pricing announcement gets any attention at all.",
               "proposal":"Price on the page at launch; billing switched on when the meter is trusted.",
               "resolved":false}]}
            """),

            // `department_key` is null: the contract is explicit that the devil's
            // advocate must NOT be given a department colour — "You are not a
            // department. You have no interests to protect."
            SSEFrame(event: "devils_advocate", data: """
            {"agent_id":"devils_advocate","department_key":null,"verdict":{
              "plan_is_sound":false,
              "load_bearing_assumption":"That the launch is the only moment attention is available.",
              "how_it_could_be_false":"For a founder tool the loudest day is usually the day the first real user ships something with it — which is after launch.",
              "cheapest_test":"Ask the five founders already in the trial whether they noticed the launch at all.",
              "failure_post_mortem":"The paywall shipped on time, converted four people, and the meter had to be reissued because nobody had used it enough to know what a credit was worth.",
              "who_is_not_in_the_room":"The founder who churns in week two and never says why.",
              "objections":["Both sides are arguing about the page, not the meter","Nobody has priced the cost of getting the meter wrong"]}}
            """),

            // Rules 3 and 5: the real disagreement verbatim, and an either/or the
            // founder owns — never "it's up to you".
            SSEFrame(event: "brief", data: """
            {"recommendation":"Put the price on the page at launch and switch billing on two weeks later, once the meter has counted real usage.",
             "confidence":3,
             "confidence_reason":"The sequencing is agreed; the price itself is not.",
             "the_real_disagreement":"Whether a price is a promise you must be able to keep, or a positioning statement you are allowed to revise.",
             "tradeoff_founder_must_own":"Either you launch with a number you may have to change, or you launch without one and give up the only day the product gets free attention.",
             "kill_criteria":["Fewer than three trial accounts reach a second session","The credit meter is off by more than 20% on any run"],
             "next_action":{"action":"Ask the five trial founders what they would pay, before the page copy is frozen.","owner":"you"},
             "what_we_dont_know":"What a credit is worth to someone who has not yet shipped anything with it.",
             "unresolved":true}
            """),

            // Zeroes, because nothing was spent. A fixture reporting ~$0.20 would be
            // inventing a charge in the one place the founder checks for real ones.
            SSEFrame(event: "telemetry", data: """
            {"tokens_per_agent":{},"cost_estimate_usd":0,"stopped_reason":null}
            """),

            SSEFrame(event: "done", data: #"{"run_id":"mock-room-1","unresolved":true,"skipped":null}"#),
        ]
    }

    /// The founder's own question goes into `real_question`, so it has to survive
    /// quoting. Encoded rather than interpolated — an ask containing a quote mark
    /// would otherwise produce invalid JSON and silently drop the routing frame,
    /// which is the whole room.
    private static func json(_ string: String) -> String {
        guard let data = try? JSONEncoder().encode(string),
              let text = String(data: data, encoding: .utf8) else { return "\"\"" }
        return text
    }
}
#endif
