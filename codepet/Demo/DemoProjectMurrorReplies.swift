// codepet/Demo/DemoProjectMurrorReplies.swift
#if DEBUG
import Foundation

extension DemoProject {

    /// Murror's department chip replies.
    ///
    /// **Why these had to be written rather than reused.** `MockChat.departmentReply` hardcoded
    /// Codepet's eight, so arming a chip in the Murror demo produced a specialist naming tasks
    /// that are not on Murror's board — "Scan five competitors' positioning", "Write your
    /// landing page copy" — and telling the founder to say "run competitors", a phrase matching
    /// no Murror task, so the router fell through and drafted something unrelated. That is the
    /// find-replace failure the `DemoProject` seam exists to prevent, on the one surface that
    /// never moved behind it.
    ///
    /// Each names only tasks that exist on `murrorTasks`, and each ends on the thing that
    /// department would actually push for next.
    static let murrorDepartmentReplies: [String: String] = [
        "eng": """
        **Ship an email capture** is the only engineering on your board, and it is deliberately \
        small: one field, no backend, no account. The interviews produced twelve people who \
        want this — losing them to a form you have not built yet is the expensive mistake here.

        A hosted form writing into one collection is enough. Want me to draft the setup \
        checklist so it is live today rather than after the redesign?
        """,
        "design": """
        The visual direction is already decided — warm dark, one amber for the single next \
        action, a serif for the founder's own words. What is open is **Design the first-run \
        flow**, and it carries the whole worry: naming a feeling must not feel like being graded.

        Four screens, and the first one asks for nothing. Want me to lay them out?
        """,
        "mkt": """
        You have the sentence already — *"AI that brings people closer"* — and the scan says why \
        it works: every journaling app in the category ends with the user understanding \
        themselves alone. **Build the Murror landing page** is what turns that into something a \
        stranger can read in five seconds.

        Say "run the landing page" and I will write it against the brand direction Luna set.
        """,
        "sales": """
        At twelve interviews you land users one conversation at a time, and **Find the first 20 \
        users** is exactly that — not a campaign, twenty specific people. The research says where \
        they are: r/CasualConversation, not a launch post.

        The people you already interviewed are the warmest twenty. Ask each for one intro.
        """,
        "support": """
        **Answer the first questions** sits on your board, and for this product the first one is \
        the only one that matters: *is this therapy?* The answer is no, and saying it plainly \
        earns you the right to be trusted with the rest.

        Write those answers once and they double as the script for the conversation you are most \
        afraid of having.
        """,
        "fin": """
        **Decide what free and paid mean** is open, and it is the harder half of pricing: a \
        practice people are supposed to do on a bad evening cannot put the thing that helps \
        behind a wall.

        Four inputs — price, signups, conversion, churn — and an honest look at what covers \
        inference. Say "run pricing" and I will build the model.
        """,
        "ops": """
        **Write the launch checklist** is on your board, and for this launch the crisis path is \
        the item that cannot be skipped: what the app does when someone writes something \
        frightening, tested before anyone can.

        The rest is ordinary — same steps, same order, every release. Want me to draft it?
        """,
        "legal": """
        **Draft the privacy policy** is open, and Murror's version is not boilerplate: people are \
        typing the most private thing they have into it. Four honest paragraphs — what you \
        collect, why, who else sees it (nobody), and how someone deletes all of it in one tap.

        Do not copy a competitor's. Yours has to say the entries never leave with a name \
        attached, and mean it.
        """,
    ]
}
#endif
