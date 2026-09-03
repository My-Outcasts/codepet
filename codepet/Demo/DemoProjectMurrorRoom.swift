// codepet/Demo/DemoProjectMurrorRoom.swift
#if DEBUG
import Foundation

/// Murror's department room: **should emotion detection ship before a clinician reviews it?**
///
/// Codepet's room convenes three departments (`fin`, `mkt`, `eng`) on its own paywall question,
/// which left `sage` and `glitch` without a voice anywhere in the demo. This one convenes four
/// and gives both of them one — and it argues about something the product genuinely has to
/// answer rather than about a launch date.
///
/// **Frames are wire JSON decoded by the real `VirtualCompanyEvent.from(frame:)`.** Constructing
/// the events directly would be shorter, but most payload structs declare `init(from:)` and so
/// have no memberwise init — and going around the decoder is the wrong shortcut anyway: a fixture
/// built from Swift values cannot catch a renamed wire key, while this one fails the moment the
/// contract and the client disagree. `docs/superpowers/specs/virtual-company-sse-contract.md` is
/// the authority for every key below.
///
/// Written against that contract's rendering rules. The ones that bite a fixture hardest:
///
/// - **Rule 2: never collapse the positions into one "we agree" paragraph.** Consensus is what a
///   fixture fakes most easily. This room does not resolve — Legal hard-blocks, Design pushes,
///   and it ends `unresolved: true`, which rule 6 calls a valid outcome rather than an error.
/// - **Rule 8: no artificial delay or fake typing.** Every frame is yielded at once. The thing
///   worth watching is the disagreement, not a progress bar.
/// - **Rule 4:** each negotiation turn carries `what_would_change_my_mind`, which is what teaches
///   that disagreement is settled by evidence rather than by authority.
extension DemoProject {

    static func murrorRoomFrames(ask: String) -> [SSEFrame] {
        [
            SSEFrame(event: "run_started", data: #"{"run_id":"mock-room-murror-1"}"#),

            SSEFrame(event: "routing", data: """
            {"decision":"multi_agent",
             "agents":["legal","design","support","engineering"],
             "real_question":\(json(ask)),
             "request_type":"decision",
             "reason_per_agent":{
               "legal":"Naming someone's emotional state is a claim, and claims about health are regulated.",
               "design":"Without it the product is a blank text box, which is a different product.",
               "support":"Whoever gets a wrong label on their worst day writes to us, not to the model.",
               "engineering":"The detection is ready; the crisis routing behind it is not."},
             "excluded":{
               "mkt":"The launch story is the same either way — this is about what ships, not how it is told.",
               "fin":"No revenue consequence at this stage; nothing here is priced."},
             "missing_info":[],
             "agent_meta":[
               {"agent_id":"legal","department_key":"legal"},
               {"agent_id":"design","department_key":"design"},
               {"agent_id":"support","department_key":"support"},
               {"agent_id":"engineering","department_key":"eng"}]}
            """),

            SSEFrame(event: "agent_start", data: #"{"agent_id":"legal","department_key":"legal"}"#),
            SSEFrame(event: "agent_position", data: """
            {"agent_id":"legal","department_key":"legal","position":{
              "stance":"do_not_proceed",
              "position":"Not until a clinician has read the labels we actually generate.",
              "reasoning":"Telling someone what they feel is a claim about their mental state. Unreviewed, in a product about loneliness, that is a health claim — and we would be making it thousands of times a day to people who are already struggling. The exposure is not the wording of our disclaimer; it is the output itself.",
              "evidence_needed":["A clinician's review of 200 real generated labels","The exact wording every label can produce"],
              "risks_i_own":["A regulator reading our feature list before our disclaimer","One screenshot of a bad label becoming the story"],
              "confidence":5,
              "cost_to_my_dept":"Nothing. The cost lands on the launch date, which is not mine.",
              "hard_blocker":"No qualified person has read a single one of the labels we generate."}}
            """),

            SSEFrame(event: "agent_start", data: #"{"agent_id":"design","department_key":"design"}"#),
            SSEFrame(event: "agent_position", data: """
            {"agent_id":"design","department_key":"design","position":{
              "stance":"proceed",
              "position":"Ship it. Without the label there is no product, only a text box.",
              "reasoning":"The whole promise is that you say something badly and get a truer word back. Take that away and we have shipped a diary with a nicer font — and nobody in the twelve interviews asked for a diary. The label is not a diagnosis and does not read like one; it reads like a friend guessing, and being wrong out loud is how the practice teaches.",
              "evidence_needed":["Five people using it for a week with the label off, to see if they keep going"],
              "risks_i_own":["A wrong label landing badly on somebody's worst evening"],
              "confidence":4,
              "cost_to_my_dept":"The first-run flow has to be redesigned around an absence.",
              "hard_blocker":null}}
            """),

            SSEFrame(event: "agent_start", data: #"{"agent_id":"support","department_key":"support"}"#),
            SSEFrame(event: "agent_position", data: """
            {"agent_id":"support","department_key":"support","position":{
              "stance":"proceed_with_conditions",
              "position":"Only behind a crisis path that a human has tested end to end.",
              "reasoning":"Someone will type the worst day of their life into this in the first week — that is not a risk, it is a certainty, and it is the point of the product. What matters is what happens in the next second. If the answer is a cheerful label and a streak counter, we have done harm. If it is a resource and a way out, we have done the job.",
              "evidence_needed":["A tested crisis path with real regional resources","Who is on call for the first week of replies"],
              "risks_i_own":["Being the person who reads that message and has nothing to offer"],
              "confidence":4,
              "cost_to_my_dept":"Somebody has to be awake and reachable for the first week.",
              "hard_blocker":null}}
            """),

            SSEFrame(event: "agent_start", data: #"{"agent_id":"engineering","department_key":"eng"}"#),
            SSEFrame(event: "agent_position", data: """
            {"agent_id":"engineering","department_key":"eng","position":{
              "stance":"proceed_with_conditions",
              "position":"The detection is ready. The routing behind it is two weeks and cannot be faked.",
              "reasoning":"Classifying the feeling is the easy half and it works. Deciding that a particular sentence needs a human rather than a label is the hard half, and there is no shortcut: it needs a real list of resources per region and a path that cannot be dismissed by accident. I can ship detection on Friday. I cannot ship the thing that makes detection safe on Friday.",
              "evidence_needed":["A frozen list of crisis resources per launch region"],
              "risks_i_own":["The two weeks","A classifier that misses the one sentence that mattered"],
              "confidence":3,
              "cost_to_my_dept":"Everything else on the board waits behind it.",
              "hard_blocker":null}}
            """),

            SSEFrame(event: "conflicts", data: """
            {"conflicts":[
              {"a":"legal","b":"design","kind":"BLOCKER",
               "reason":"Legal will not ship an unreviewed label; Design says the product without the label is not the product."},
              {"a":"support","b":"design","kind":"TENSION",
               "reason":"The crisis path Support requires is two weeks that Design wants spent on the flow itself."}]}
            """),

            // Rule 4 lives on this frame: `what_would_change_my_mind` on every turn.
            SSEFrame(event: "negotiation_round", data: """
            {"round":1,"turns":[
              {"agent":"legal",
               "precise_disagreement":"Design is treating the label as a guess. To a regulator it is an assertion, and we make it at scale.",
               "what_would_change_my_mind":"One clinician reading 200 real labels and saying none of them read as a diagnosis.",
               "proposal":"Ship the practice without the label, and turn detection on the day the review clears.",
               "resolved":false},
              {"agent":"design",
               "precise_disagreement":"Legal is protecting against the label's wording. The risk is the silence if we remove it — people stop after two days.",
               "what_would_change_my_mind":"Five people keeping the practice for a week with detection switched off.",
               "proposal":"Ship detection to the twelve people already interviewed, not to the store.",
               "resolved":false},
              {"agent":"support",
               "precise_disagreement":"Both of you are arguing about the label. I am arguing about the sentence underneath it.",
               "what_would_change_my_mind":"Nothing about the label. I need the crisis path either way.",
               "proposal":"Crisis path first, then let Legal and Design argue about the label with two weeks in hand.",
               "resolved":false}]}
            """),

            // `department_key` is null: the contract is explicit that the devil's advocate must
            // NOT be given a department colour — "You are not a department. You have no
            // interests to protect."
            SSEFrame(event: "devils_advocate", data: """
            {"agent_id":"devils_advocate","department_key":null,"verdict":{
              "plan_is_sound":false,
              "load_bearing_assumption":"That the label is what helps. The useful act may be the typing, and the label merely what makes the typing feel answered.",
              "how_it_could_be_false":"Journalling works with no reader at all. If the benefit is in naming it yourself, then a wrong label is pure downside and a right one adds nothing you did not already do.",
              "cheapest_test":"Give six of the twelve a version that only ever replies 'noted' and see who is still writing on day seven.",
              "failure_post_mortem":"Detection shipped, reviewed and safe. Retention was identical to the version without it, and the two weeks bought a feature nobody needed.",
              "who_is_not_in_the_room":"The person who wrote one entry, got a word that was slightly wrong, felt unseen, and never opened it again. They do not write in.",
              "objections":["Everyone here assumes the label is the value; nobody has tested that","The crisis path is being justified by the label, but it is needed whether or not the label ships"]}}
            """),

            // Rules 3 and 5: the real disagreement verbatim, and an either/or the founder owns —
            // never "it's up to you".
            SSEFrame(event: "brief", data: """
            {"recommendation":"Build the crisis path now, because it is required either way. Ship the practice without the label, and turn detection on when a clinician has read the output.",
             "confidence":3,
             "confidence_reason":"The sequencing is agreed by three of the four. Whether the product works at all without the label is genuinely untested.",
             "the_real_disagreement":"Whether naming the feeling for someone is the product, or whether the product is the act of them naming it themselves.",
             "tradeoff_founder_must_own":"Either you ship a diary and risk that nobody stays past day three, or you ship a claim about somebody's mental state that no qualified person has read.",
             "kill_criteria":["The crisis path misfires on anything that is not a crisis","Fewer than three of the twelve are still writing on day seven"],
             "next_action":{"action":"Send 200 real generated labels to a clinician this week, and ask six of the twelve to try it with detection off.","owner":"you"},
             "what_we_dont_know":"Whether the label is the value or the wrapper. Nobody in this room has tested it.",
             "unresolved":true}
            """),

            // Zeroes, because nothing was spent. A fixture reporting a dollar figure would be
            // inventing a charge in the one place the founder checks for real ones.
            SSEFrame(event: "telemetry", data: """
            {"tokens_per_agent":{},"cost_estimate_usd":0,"stopped_reason":null}
            """),

            SSEFrame(event: "done", data: #"{"run_id":"mock-room-murror-1","unresolved":true,"skipped":null}"#),
        ]
    }
}
#endif
