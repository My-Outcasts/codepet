// codepet/Demo/DemoProjectCodepetReplies.swift
#if DEBUG
import Foundation

extension DemoProject {

    /// Codepet's department chip replies — moved VERBATIM out of `MockChat.departmentReply`,
    /// which hardcoded them for every demo project. Written against THIS board on purpose:
    /// a reply that would read identically for any company disproves the specialist's claim
    /// to know it.
    static let codepetDepartmentReplies: [String: String] = [
        "eng": """
            The only engineering on your board is **Set up a waitlist signup**, and it is \
            waiting on the landing page — there is nowhere to put the form yet. When it \
            unblocks, keep it a hosted form writing into one collection; collecting an email \
            does not need a backend, and building one now is a week you spend not shipping.

            Want me to sketch the smallest version that would actually capture a signup today?
            """,
        "design": """
            Decide who is looking before you decide what they see. **Sketch two early user \
            personas** is open right now and it is the cheaper half of this — **Design your \
            brand look** is downstream of it, because a visual direction is an argument aimed \
            at someone specific.

            Give me the two people and I will make the colors and type argue for them.
            """,
        "mkt": """
            Your bottleneck is the sentence, not the channel. **Scan five competitors' \
            positioning** is open now, and the gap it finds is exactly what **Write your \
            landing page copy** needs: one line a stranger understands in five seconds.

            Say "run competitors" and I will do the scan and hand you the sentence it points at.
            """,
        "sales": """
            At your stage you land users one conversation at a time — a campaign has nothing \
            to convert yet. **Write a cold outreach email** is on the board but waits on both \
            the landing page and a price, and that order is right: a stranger needs somewhere \
            to look and something to say yes to.

            Until then your five discovery calls are the pipeline. Ask for one intro at the \
            end of every single one.
            """,
        "support": """
            You have no users yet, which makes support cheap to get right and expensive to \
            retrofit. **Draft a support FAQ** sits behind pricing on your board for a reason — \
            the first questions are always what is this, what does it cost, and can I cancel.

            Write those answers once and they double as your objection-handling script on the \
            discovery calls.
            """,
        "fin": """
            Numbers before vibes. **Size the market you're entering** is open right now, and it \
            is a top-down sanity check you can finish in an hour — not a fundraising slide, so \
            do not spend a week on it.

            Then **Draft a simple pricing plan**, because a price is the first thing that makes \
            interest cost something. Ship a number you are allowed to change.
            """,
        "ops": """
            Operations is the plumbing that stops you from being the plumbing. **Set up a \
            deploy checklist** is on your board behind the waitlist, and the whole point of it \
            is that shipping stops needing your full attention — same steps, same order, every \
            release.

            Write it the first time you deploy by hand, while you still remember what you forgot.
            """,
        "legal": """
            Legal here is cheap insurance bought before you need it. **Draft a privacy policy** \
            is on your board, and at your size it is four honest paragraphs: what you collect, \
            why, who else sees it, and how someone deletes it.

            Draft it in plain language now and have a lawyer read it before you take money. Do \
            not copy a competitor's — you will inherit claims about a company that is not yours.
            """,
    ]
}
#endif
