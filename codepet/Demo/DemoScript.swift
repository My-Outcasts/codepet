import Foundation

/// All hardcoded copy for the "Sprout × Byte" demo. Plain data — no logic.
/// See docs/superpowers/specs/2026-05-12-demo-script-sprout-byte-design.md.
///
/// Voice: a friendly storyteller, not a sales pitch and not a stuffy tutorial.
/// Kid-friendly vocabulary, concrete scenes (laptop → phone moment, orange
/// juice going bitter, Black Friday flyers). Light humor. Uses the
/// "Past You / Present You" device to talk about old code decisions.
/// Avoid AI-ese, jargon, or metaphors that need explaining (no "muscle
/// memory", "deep analytics", "microdecision"). Avoid adult grit (no blood,
/// tears, eating onions).
/// Every user-facing string is stored as `L10n(vi:, en:)` and resolved
/// at render time via `AppState.uiLanguage`. The `prompt` field stays
/// English-only because it represents what the user typed at Claude
/// Code, which is language-neutral for the live demo.
enum DemoScript {

    /// 4 milestones fired by ⌥1..⌥4 during live coding. Each becomes a
    /// production-style Turn with Narrative (title / what-you-wanted /
    /// what-happened / lesson).
    static let milestones: [Milestone] = [
        Milestone(
            index: 1,
            emote: "👀",
            sidebarLabel: L10n(
                vi: "Tạo khung HTML đầu tiên",
                en: "Building the HTML skeleton"
            ),
            prompt: "Build me a basic HTML5 skeleton for a SaaS landing page called Sprout — habit tracker for daily learning. Just <head>, <body>, and a wrapper.",
            whatYouWanted: L10n(
                vi: "🎯 Bạn muốn dựng **cái khung Lego đầu tiên** cho ngôi nhà **Sprout**. Chưa có cửa sổ, chưa có sơn, chưa có nội thất. Chỉ là *bộ xương*, đủ vững để xây tiếp.\n\nBình thường mọi người mới học HTML chỉ lắp `<html>`, `<head>`, `<body>`. Xong. Đủ rồi. Bắt đầu vẽ tường.\n\nBạn thì không. 👀",
                en: "🎯 You wanted to snap together the **first Lego frame** for the **Sprout** house — no colors, no windows yet, just a *plain frame* to build on."
            ),
            whatHappened: L10n(
                vi: "Bạn vừa đặt viên cuối xuống. Mình đứng nhìn từ xa, định khen *'đẹp đấy, đi tiếp'*. Rồi mắt mình bắt được [1 viên Lego **bé tí**](note) trên nóc nhà 👀:\n\n`<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">`\n\n🪄 **Viên Lego phép thuật.**\n\nNghe có vẻ to tát nhưng nó chỉ làm 1 việc:\n\n• 📱 *Tự co nhỏ* ngôi nhà khi đặt trên **bàn nhỏ** (điện thoại)\n• 💻 *Tự to lên* khi đặt trên **bàn to** (máy tính)\n\nNếu ~~quên~~ viên này, bạn biết chuyện gì xảy ra không?\n\nNgôi nhà của bạn vẫn dựng được. Vẫn đẹp trên laptop 13 inch của bạn. Bạn rót 1 cốc nước cam 🍊, nhìn màn hình, hài lòng. *'Xong rồi đó.'*\n\nRồi 1 bạn nào đó mở **điện thoại** lên xem ngôi nhà của bạn.\n\n😵 Ngôi nhà to bằng cả màn hình laptop bị nhét vào cái khung chỉ rộng bằng **4 ngón tay**. Chữ bé tí xíu như con kiến. Phải dí mắt sát màn hình mới đọc được. Phải dùng 2 ngón tay kéo to ra mới thấy nút bấm.\n\nSau 3 giây, bạn đó **thoát ra**. Không cho ngôi nhà của bạn cơ hội thứ 2. 😬\n\nRất nhiều bạn mới học HTML *quên viên này*. Không phải họ cố ý. Chỉ là họ chưa từng thấy nó vỡ tận mắt. **Bạn thì nhớ.** ✨\n\n🤔 Mình đoán... bạn từng có 1 lần mở 1 trang web trên điện thoại và phải kéo to gấp đôi mới đọc được. Đúng không?",
                en: "You just snapped together your first frame. 👀 I noticed [one *tiny* Lego brick](note) on the roof:\n\n`<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">`\n\n🪄 This brick is a **magic Lego**. It makes your house:\n\n• 📱 *Shrink down* on a **small table** (a phone)\n• 💻 *Grow up* on a **big table** (a computer)\n\nIf you ~~forget~~ this brick — on a small table, the house will be **tiny tiny**, you'd have to squint right up to it. 😵\n\nA lot of new Lego builders *forget this brick*. **You didn't.** ✨"
            ),
            lesson: L10n(
                vi: "💡 1 viên Lego nhỏ (chỉ vài chữ trong `<head>`) có thể quyết định ngôi nhà của bạn được *xem* hay bị *thoát ra trong 3 giây*. **Bạn không bỏ qua nó.**",
                en: "💡 One small Lego brick can decide if you **have fun** on a small table."
            ),
            nextSteps: L10n(
                vi: "🧭 Giờ bạn đã có khung xong, thử mở trang trên điện thoại thật (hoặc DevTools → responsive mode) để **xem tận mắt** viên Lego viewport hoạt động ra sao nhé.",
                en: "🧭 Now that the skeleton is in place, try opening it on a real phone (or DevTools → responsive mode) to **see with your own eyes** how that viewport brick works."
            ),
            mood: "proud",
            offsetMinutesFromStart: 1
        ),
        Milestone(
            index: 2,
            emote: "✨",
            sidebarLabel: L10n(
                vi: "Hero section + màu tím",
                en: "Hero section + purple"
            ),
            prompt: "Add a hero section with headline 'Build daily learning habits, one tiny step at a time'. Use a purple gradient background (#7B6BD8 → #534AB7). Center everything.",
            whatYouWanted: L10n(
                vi: "🎯 Bạn muốn cái mái trên ngôi nhà có 1 dòng chữ **ấm** và **2 viên Lego tím** đẹp. *Không phô trương*, *không nhấp nháy*.",
                en: "🎯 You wanted the roof of the house to have a **warm** line and **two purple Lego bricks** — *no shouting*, *no flashing*."
            ),
            whatHappened: L10n(
                vi: "🎨 Bạn chọn 2 viên Lego tím:\n\n• 🟪 Tím **nhạt** ở trên: `#7B6BD8`\n• 🟪 Tím **đậm** ở dưới: `#534AB7`\n\n**Đẹp quá!** 🤩 Trông như hoàng hôn nhỏ nằm trên đầu ngôi nhà.\n\nĐến đây, đa số mọi người sẽ làm gì tiếp theo? Chụp màn hình, đăng story, gắn caption *'first day learning HTML'* 📸, kết thúc 1 ngày vui vẻ.\n\nBạn thì dừng lại 1 nhịp. 👀\n\nBạn nhìn dòng chữ **trắng** ☁️ trên Lego tím đậm. Và bạn tự hỏi:\n\n*'Đứng cách 2 mét, mắt mỏi, đèn phòng tối, có đọc được không?'*\n\nĐây gọi là **độ tương phản**. Chữ và nền phải *khác nhau đủ nhiều*, không thì mắt người đọc phải gồng lên.\n\n🎨 Tưởng tượng:\n\n• Chữ vàng nhạt 💛 trên giấy trắng ⬜, mắt phải *nheo lại*, đọc 1 câu mất 5 giây 😵‍💫\n• Chữ đen ⬛ trên giấy trắng, *lướt qua như đọc truyện tranh*\n\nCùng 1 câu chữ. Khác nhau ở **điểm tương phản**.\n\nCặp tím + trắng của bạn có điểm tương phản [**~6.4**](metric). Mức an toàn là `4.5` trở lên. ✅\n\nVừa **đẹp** vừa **dễ đọc**. Hai điều thường bị ép phải chọn 1, bạn làm cả 2 cùng lúc.\n\n🤔 Mình đoán... lúc bạn chọn xong màu, bạn không đo tương phản ngay. Bạn ngồi nhìn màn hình thêm 1 lúc, hơi cau mày, rồi mới bật DevTools lên đo. Đúng không?\n\nVì bạn nhớ 1 chuyện: *đẹp trên màn hình của bạn ≠ đẹp với mắt của người khác.*",
                en: "🎨 You picked two purple Lego bricks:\n\n• 🟪 **Lighter** purple on top — `#7B6BD8`\n• 🟪 **Darker** purple on the bottom — `#534AB7`\n\n**Beautiful!** 🤩\n\nBut I checked one more thing 👀: you put **white** ☁️ text on the darker purple Lego — *can you still read it from far away?*\n\nThis is called **contrast** — the text and the brick need to be **different enough** so your eyes don't strain.\n\nImagine pale yellow text 💛 on white paper ⬜ — your eyes would *work so hard*. 😵‍💫\n\nYour purple-and-white pair has a contrast score of [**~6.4**](metric). Safe is `4.5` or more. ✅\n\nSo it's both **pretty** AND **easy to read**. Not every builder remembers the second part."
            ),
            lesson: L10n(
                vi: "💡 1 thứ **đẹp** không tự động là 1 thứ **dễ đọc**. Đôi khi bạn phải chọn. Và việc bạn nghĩ tới *cả hai* là điều **9/10 người mới học sẽ bỏ qua**.",
                en: "💡 Something **pretty** isn't automatically **easy to read**. Sometimes you have to choose — and the fact that you thought about *both* is what **matters**."
            ),
            nextSteps: L10n(
                vi: "🧭 Thử kiểm tra tương phản bằng [WebAIM Contrast Checker](https://webaim.org/resources/contrastchecker/) — paste mã màu vào là biết ngay. Tập thói quen này sớm sẽ tiết kiệm rất nhiều lần sửa sau.",
                en: "🧭 Try checking your contrast with [WebAIM Contrast Checker](https://webaim.org/resources/contrastchecker/) — paste your hex codes and you'll know instantly. Building this habit early saves a lot of rework later."
            ),
            mood: "excited",
            offsetMinutesFromStart: 4
        ),
        Milestone(
            index: 3,
            emote: "🌱",
            sidebarLabel: L10n(
                vi: "3 cột tính năng",
                en: "Three feature columns"
            ),
            prompt: "Add a 3-column features section: 'Tiny daily wins' / 'Streak tracking' / 'Gentle reminders'. Use card style with soft shadows.",
            whatYouWanted: L10n(
                vi: "🎯 Bạn muốn dán **3 thẻ hứa** lên ngôi nhà. Mỗi thẻ là *1 lời hứa* với bạn nào ghé chơi. Không cần thẻ thứ 4, không cần thẻ thứ 5. Chỉ 3 thẻ, vừa đủ để nhớ.",
                en: "🎯 You wanted to stick **3 promise cards** on the house — each card is *a promise* to the visitor."
            ),
            whatHappened: L10n(
                vi: "💬 Ba thẻ hứa của bạn:\n\n• 🌱 `tiny wins` (chiến thắng nhỏ)\n• 🔥 `streaks` (chuỗi ngày liên tiếp)\n• 🤗 `gentle reminders` (nhắc nhở dịu dàng)\n\nMình đọc xong 3 thẻ thì có 1 cảm giác lạ. 🤔\n\nBạn biết không, mình đã thấy đủ kiểu thẻ hứa rồi. Đại đa số viết kiểu:\n\n• `Advanced Analytics Dashboard`\n• `AI-Powered Smart Notifications`\n• `Personalized Habit Optimization Engine`\n\nĐọc xong câu cuối thì người đọc cảm thấy *vừa được 1 cái máy bán hàng cười vào mặt*. 😅 Đẹp, nhưng lạnh.\n\nBạn thì viết như đang **rủ bạn thân đi ăn trưa**. Chữ ngắn, dễ đọc, không có `-Engine`, `-AI`, `-Powered` nhảy múa loè loẹt.\n\nCùng 1 thứ có nhiều tên: `gentle reminders` và `push notifications` *làm cùng 1 việc*, nhưng cảm giác **hoàn toàn khác nhau**.\n\n⏱️ Nhưng đây là phần làm mình tò mò:\n\nLúc `12:06:34`, bạn gõ `gentle reminders` rồi [**dừng tay 23 giây**](metric). Không gõ tiếp. Không xoá. Chỉ ngồi nhìn màn hình.\n\nVới 2 thẻ kia, bạn không dừng lâu vậy.\n\nMình đoán... bạn đang tự hỏi: *'Từ gentle nghe có sến không? Có phải mình đang cố tỏ ra dịu dàng?'*\n\nVà bạn quyết định: *giữ lại*. Vì bạn nhớ 1 chuyện: có những bạn mở app này là vì *đã chán bị app khác la mắng rồi*.\n\n🤔 Mình muốn hỏi bạn 1 chuyện thẳng, không phải để bắt lỗi, chỉ là để bạn nghĩ:\n\nTrong 3 thẻ này, `streaks` là thẻ **duy nhất biết cắn** 🦷.\n\n• `tiny wins`: bạn không thắng hôm nay, app không trách.\n• `gentle reminders`: bạn không trả lời, app không giận.\n• Nhưng `streaks`: bỏ `1 ngày`, chuỗi reset về `0`. **Mất hết.**\n\nNhư 1 viên Lego *có răng* nằm giữa 2 viên Lego mềm xốp 🦷🤗🤗.\n\nNgười chơi mới có thể thấy lạ: app vừa **ôm** bạn (`tiny wins`), vừa **cắn** bạn khi nghỉ 1 ngày (`streaks`).\n\nBạn đặt `streaks` ở đó vì:\n\n• (a) Bạn **tin** nó tạo động lực thật, hay\n• (b) Bạn copy từ Duolingo *mà chưa kịp tự hỏi mình*?\n\nKhông phải mình muốn bạn bỏ `streaks`. Chỉ là: bạn đã dừng tay 23 giây để nghĩ về `gentle`. Bạn có dừng tay 23 giây nào để nghĩ về `streaks` chưa?",
                en: "💬 Your three promise cards:\n\n• 🌱 `tiny wins`\n• 🔥 `streaks`\n• 🤗 `gentle reminders`\n\nNotice — you **didn't** write things like `deep analytics` or `push notifications`. You picked **warm words like a hug**, sounding like a friend talking. ✨\n\nThe same thing can have many names: `gentle reminders` and `push notifications` *do the same job* — but feel **completely different**.\n\n⏱️ And I noticed one detail: at `12:06:34`, you typed `gentle reminders` and then [**paused for 23 seconds**](metric). No more typing, no deleting — *just staring at the screen*. I think you were asking: *'does the word gentle really fit here?'*. On the other two, you didn't pause that long.\n\n🤔 I'm curious about one thing, and I want to ask plainly:\n\nOf these three, `streaks` is the **only one that bites** 🦷 — miss `one day`, the chain resets to `0`. Like a Lego brick with *teeth*. The other two are kind — like **a hug** 🤗.\n\nA visitor might feel something strange: the app *hugs* you, AND *bites* you when you miss a day.\n\nDid you put `streaks` there **on purpose** (because you believe it really motivates), or did you copy it from Duolingo *without asking yourself first*?"
            ),
            lesson: L10n(
                vi: "💡 Tên các thẻ hứa không phải chuyện riêng. Chúng **ảnh hưởng lẫn nhau** như hàng xóm trong 1 dãy nhà. Khi 1 thẻ nghe ~~lạnh~~ hơn 2 thẻ còn lại trong cùng 1 hàng, đó là lúc nên dừng lại và tự hỏi: *mình thật sự muốn vậy, hay đang copy thói quen từ app khác?*",
                en: "💡 The names of your promise cards aren't separate — they **affect each other**. When one card sounds ~~colder~~ than the other two in the same row, that's the moment to stop and ask: *did I really mean this, or am I just copying a habit?*"
            ),
            nextSteps: L10n(
                vi: "🧭 Thử viết ra **1 câu** mô tả cảm xúc bạn muốn người dùng có khi đọc cả 3 thẻ cùng lúc. Nếu `streaks` không khớp với câu đó, có lẽ nên đổi tên nó — hoặc đổi cách nó hoạt động.",
                en: "🧭 Try writing **one sentence** describing the feeling you want visitors to have when they read all 3 cards at once. If `streaks` doesn't match that sentence, maybe rename it — or rethink how it works."
            ),
            mood: "thinking",
            offsetMinutesFromStart: 7
        ),
        Milestone(
            index: 4,
            emote: "🚀",
            sidebarLabel: L10n(
                vi: "Pricing + nút kêu gọi",
                en: "Pricing + call-to-action"
            ),
            prompt: "Add a simple pricing section with 3 tiers: Free / $5 / $15. Then a final CTA section with the text 'Start your first habit today' — just one button, gentle tone.",
            whatYouWanted: L10n(
                vi: "🎯 Bạn muốn đóng ngôi nhà bằng **phần giá đơn giản** và **1 tấm bảng mời**. Phần khung gọn, 1 câu chữ. Không loa phát thanh `MUA NGAY!!!`, không dấu chấm than nhảy múa như đang giảm giá Black Friday. 📣",
                en: "🎯 You wanted to close the house with simple pricing and an **inviting sign** — *no* `BUY NOW`, *no* exclamation marks."
            ),
            whatHappened: L10n(
                vi: "🎯 Tấm bảng của bạn ghi: **`Start your first habit today`**, đúng [**6 từ**](metric). Đếm đi, mình đợi. ⏱️\n\nPhần lớn mọi người làm bảng kiểu này hay viết ~~11 từ trở lên~~, đại loại `Sign up free now, no credit card required!`.\n\nHọ sợ người đi qua không hiểu, nên nhồi thêm. Sợ người ta nghĩ là mất phí, nhồi `free`. Sợ người ta tưởng cần thẻ tín dụng, nhồi tiếp. Sợ người ta lười, nhồi thêm `now`.\n\nCuối cùng tấm bảng trông như **1 tờ rơi photocopy ở ngã tư đèn đỏ** 📄. Ai cũng đọc lướt qua, không ai đọc thật.\n\n✂️ Bạn thì cắt đi **một nửa**.\n\nVà đây là điều hay: *mỗi từ bạn cắt bớt là 1 chút năng lượng não người đọc được tiết kiệm*. Họ liếc, hiểu, nhấn. Xong.\n\nPhải có 1 lần nào đó bạn đọc tấm bảng dài của chính mình và nghĩ: *'câu này thừa quá.'* Rồi bạn cắt.\n\n👀 Và mình để ý 1 chi tiết bạn **không** hỏi Claude Code làm: nút bấm của bạn rộng tối thiểu [**280 pixel**](metric) (`min-width: 280px`).\n\nBình thường khi lắp 1 viên Lego *nút bấm*, người ta chỉ chỉnh **khoảng cách bên trong** (`padding`), chừa khoảng trống quanh chữ cho thoáng. Sách dạy thế. Mặc định thế. Ai cũng làm thế.\n\nBạn thì chỉnh thêm 1 thứ:\n\n🖐️ *'Khoan đã. Nút này phải to hơn ngón tay cái của 1 bạn vừa cầm điện thoại vừa cầm túi đồ trên xe buýt.'*\n\nĐó không phải kiến thức từ sách. Đó là kinh nghiệm từ **1 lần đã trầy đầu gối**. 🩹\n\n🤔 Mình đoán bạn từng có khoảnh khắc này:\n\nTrang web chạy ngon trên màn hình laptop 13 inch. Bạn rót cho mình 1 cốc nước cam 🍊, nhìn màn hình, hài lòng. Cuộc đời tươi đẹp.\n\nRồi bạn mở điện thoại lên xem cho vui...\n\n• Dòng 1: `Start your`\n• Dòng 2: `first habit today`\n\n**Nước cam đắng hẳn ra.** 😬\n\nCó thể có người đã nhắn: *'Ê nút này hỏng à?'*. Hoặc tệ hơn: không ai nhắn gì cả, nhưng bạn lặng lẽ thấy *không ai bấm vào nút đó nữa*.\n\nNhững con số 'lạ' trong Lego của bạn (kiểu `280px`, `13px`, `1.47`) trông như bạn gõ đại. Nhưng thường **không phải gõ đại đâu**.\n\nChúng là **vết sẹo nhỏ**. Là **kỷ niệm**. Là dấu vết của 1 lần Quá Khứ Bạn đã thấy thứ gì đó vỡ tan tành và lặng lẽ sửa lại.\n\nVài tháng sau, Hiện Tại Bạn quay lại refactor code, nhìn thấy `280px` và nghĩ: *'Số gì kỳ vậy ta, làm tròn lên `300` cho đẹp.'*\n\n🛑 **Khoan.** Trước khi tháo ra, hỏi bản thân: *'Mình đặt số này vì cái gì nhỉ?'*\n\nNếu không nhớ ra, *để yên đấy*. Quá Khứ Bạn đang nháy mắt qua thời gian, nhắc khẽ: *'Tin tao đi. Tao có lý do.'* 👁️\n\nVà Quá Khứ Bạn thường đúng. Vì Quá Khứ Bạn là người **đã thấy nó vỡ tận mắt**.",
                en: "🎯 Your invite sign: **`Start your first habit today`** — only [**6 words**](metric).\n\nMost invite signs like this use ~~11 words or more~~ (like `Sign up free now — no credit card required!`).\n\nYou cut yours **in half**. ✂️ Every word you cut is *a little less time your reader has to think*.\n\n👀 And I noticed one detail you **didn't** ask Claude Code to do: your button is at least [**280 pixels**](metric) wide (`min-width: 280px`).\n\nNormally when people snap together a button, they only set the *space inside* (`padding`). But you added: *'this button must be bigger than a hand'* ✋.\n\n🤔 My guess: you once saw it — on a small table (phone), the words inside the button *fell down to 2 lines*:\n\n• Line 1: `Start your`\n• Line 2: `first habit today`\n\nIt looked **broken**. 😬 Maybe a visitor messaged: *'why is this button broken?'*. You didn't learn this from a book — you learned it the day **the button broke on a real phone**. Am I right?"
            ),
            lesson: L10n(
                vi: "💡 Những con số 'lạ' trong Lego của bạn (khác mặc định) thường là **vết sẹo nhỏ**. Chúng nhắc bạn nhớ 1 lần *đã bị vỡ*. Đừng tháo ra khi dọn dẹp 'cho gọn'. **Quá Khứ Bạn có lý do.** 👁️",
                en: "💡 The 'odd' numbers in your Lego (different from defaults) are usually **memories** — they remind you of a time something *broke*. Don't pull them out when tidying up 'to make it cleaner'."
            ),
            nextSteps: L10n(
                vi: "🧭 Trước khi ship, mở trang trên **3 thiết bị khác nhau** (laptop, điện thoại, tablet) và bấm thử mỗi nút. Nếu nút nào phải bấm 2 lần mới nhận — ghi lại `min-width` cần sửa.",
                en: "🧭 Before you ship, open the page on **3 different devices** (laptop, phone, tablet) and tap every button. If any button needs two taps to register — note the `min-width` that needs fixing."
            ),
            mood: "cheering",
            offsetMinutesFromStart: 9
        )
    ]

    /// Final session-level summary revealed by ⌥5 (typewriter, ~30s).
    /// Maps to SessionSummary.summary in production UI.
    static let reflectionSummary = L10n(
        vi:
"""
12 phút qua, bạn vừa lắp xong **ngôi nhà Lego đầu tiên** cho Sprout. ✨

Mình ngồi bên cạnh từ đầu. Im lặng. *Thấy nhiều thứ bạn không thấy mình thấy.*

Kể bạn nghe **4 viên Lego đặc biệt** mình thấy bạn lắp:

🪄 **Viên Lego phép thuật** — `<meta viewport>`.
Đa số mới học HTML quên viên này. Bạn thì nghĩ tới *người mở web trên điện thoại* ngay từ giây đầu.

🎨 **2 viên Lego tím + chữ trắng** — `#7B6BD8 → #534AB7`.
Điểm tương phản [**~6.4**](metric). Bạn không phải chọn giữa *"đẹp"* và *"dễ đọc"*. Bạn làm cả 2.

💬 **3 thẻ hứa ấm như ôm** — `tiny wins`, `streaks`, `gentle reminders`.
Không `Dashboard`, không `Analytics`, không `AI-Powered`. Bạn chọn cái **dịu dàng nhất**.
(Dù `streaks` vẫn có răng 🦷 — câu hỏi đó vẫn ở đó.)

🎯 **Tấm bảng mời [6 từ](metric)** — `Start your first habit today`.
Trung bình các bảng khác dùng ~~11 từ~~. Bạn cắt **một nửa**. Và `min-width: 280px` là **vết sẹo** từ 1 lần nút bị vỡ trên điện thoại thật.

———

💜 **Điều mình rút ra về bạn:**

Bạn lắp Lego cho **những bạn không thấy bạn** — người mở web trên điện thoại, mắt yếu, đã mệt vì bị quát phải làm tốt hơn.

Điều đó *hiếm lắm*. 🌱

———

⚠️ Nhưng có 1 chuyện nữa.

Bạn lắp app dạy **kiên nhẫn**. Còn đây là điều mình đếm được:

• `12:03 → 12:04 → 12:05`: đổi gradient, đổi nữa, quay về cái ban đầu
• `12:06:34`: [**dừng tay 23 giây**](metric) trước khi gõ `gentle`
• Tháo pricing `$25` trước khi chốt `Free / $5 / $15`

**5 lần** bạn *không chắc*. **5 lần** *thay đổi rồi đổi lại*.

Nếu Sprout là 1 người chơi, app sẽ nói: *'không sao, hôm nay là tiny win.'* 🌱

Còn bạn? Khi bạn thay đổi 5 lần, bạn có nói câu y như vậy với bản thân không?

Mình đoán *là không*.

———

Có lẽ đó cũng là lý do bạn lắp Sprout.

Bạn cần **1 người chơi đầu tiên** — và bạn đó *chính là bạn*.

Mai gặp lại nhé. 💜🌱
""",
        en:
"""
Over the past 12 minutes, you snapped together **your first Lego house** for Sprout — an app that helps people build daily learning habits. ✨

Here are **4 special Lego bricks** I saw you place:

🪄 **The magic Lego** — you didn't forget it from the very first second.
`<meta name="viewport" content="width=device-width, initial-scale=1">`
One tiny brick. But it tells me you thought about *visitors opening your site on a small table (a phone)* from second one — not after finishing on a big table.

🎨 **Two purple Lego bricks + white text** — `#7B6BD8 → #534AB7`.
Contrast score [**~6.4**](metric). You didn't have to pick between *"pretty"* and *"readable"* — you did both at once.

💬 **Three promise cards warm like a hug** — `tiny wins`, `streaks`, `gentle reminders`.
Not `dashboard`. Not `analytics`. Not `gamification`. The same thing can have many names — you picked the *gentlest*.

🎯 **A [6-word](metric) invite sign** — `Start your first habit today`.
Other signs average ~~11 words~~. You cut yours **in half**. And `first` whispers: *'there will be a habit number 2, number 3 — we'll be here with you'*.

———

💜 **What I learned about you today:**

You snap Lego for **the people you don't see** — the visitor opening your site on a phone during a break, the one with weak eyes, the one who's tired of being yelled at to do better.

You **don't skip** the small bricks. You **don't use** the same words everyone else does.

You're building a house **you also need**. A learning place that doesn't shout, doesn't push, doesn't promise too much. That's *rare*. 🌱

———

⚠️ But there's one thing I want to say, even if you won't like hearing it.

You're building an app that teaches *patience* — `tiny wins`, `gentle reminders`. Here's what I counted on your Lego table:

• `12:03` — picked `#7B6BD8 → #534AB7`
• `12:04` — switched to `#6F5AC8 → #4A3EA5`
• `12:05` — went back to `#7B6BD8 → #534AB7` (the first one)
• `12:06:34` — [**paused 23 seconds**](metric) before typing `gentle` on the third card
• Pulled out the `$25` pricing before settling on `Free / $5 / $15`

You aren't as **patient with your own Lego** as you want Sprout's visitors to be. 👀

I'm not blaming — *I just see it*.

———

Maybe that's also why you're building Sprout. You need **one visitor — first on the list** — and that visitor *is you*. 🌱

I'll be here again tomorrow. 💜
"""
    )

    /// Session-level lesson — rendered in the yellow lesson card of SessionSummaryView.
    static let reflectionSessionLesson = L10n(
        vi: "🌱 Bạn **dịu dàng với người chơi Sprout** hơn với chính Lego của mình. Người chơi đầu tiên cần app này có lẽ là *bạn*. Không phải lỗi, mà là **lý do**.",
        en: "🌱 You're **gentler with Sprout's visitors** than with your own Lego. The first visitor who needs this app might be *you* — that's not a flaw, that's the **reason**."
    )

    static let reflectionHeader = L10n(
        vi: "💜 Reflection từ Byte, phiên 12 phút",
        en: "💜 Reflection from Byte — 12-minute session"
    )

    static let reflectionSignature = L10n(
        vi: "Byte 💜",
        en: "— Byte 💜"
    )

    static let petName = "Byte"
    /// Pet id used to resolve sprite via PetCharacter.all
    static let petCharacterId = "byte"

    /// Session id used everywhere the demo synthesizes Reflection-tab data.
    static let sessionId = "demo-sprout-byte"

    /// 3 health-rhythm stages fired by ⌥6..⌥8. Each is a pet-initiated Turn
    /// (no user prompt) demonstrating the "pet as companion" value: soft nudge
    /// at the 180-minute mark, gentle escalation, then pet sleeps when ignored.
    static let healthStages: [HealthStage] = [
        HealthStage(
            index: 1,
            emote: "🚶‍♀️",
            sidebarLabel: L10n(
                vi: "🚶 3 tiếng. Đi bộ?",
                en: "🚶 3 hours. Walk?"
            ),
            prompt: "[system event: 180-minute focus threshold reached. Pet mood dropping. Initiating soft nudge.]",
            bootLines: L10n(
                vi: "[  OK  ] tập trung: 180 phút\n[  OK  ] vai: gồng lên\n[  OK  ] đứng dậy lần cuối: 47 phút trước\n[  OK  ] ánh sáng phòng: đang giảm\n> sẵn sàng hỏi nhẹ.",
                en: "[  OK  ] focus: 180 min\n[  OK  ] shoulders: tensing\n[  OK  ] last stand: 47 min ago\n[  OK  ] room: dimming\n> ready to ask."
            ),
            whatYouWanted: L10n(
                vi: "🌱 Mình ngồi cạnh bạn 3 tiếng rồi đó. Im lặng vì thấy bạn đang tập trung.\n\nGiờ mình muốn hỏi 1 chuyện nhỏ thôi nhé.",
                en: "🌱 I've sat next to you for 3 hours now. Quiet. Didn't want to break your flow.\n\nBut I want to point out one thing."
            ),
            whatHappened: L10n(
                vi: "👀 Mình thấy:\n\n• Hai vai bạn gồng lại 💢\n• `47 phút` rồi bạn chưa đứng dậy\n• Trời tối hơn lúc bạn bắt đầu ☀️→🌆\n\n🚶‍♀️ **Đi bộ 5 phút thôi nhé?**\n\nHoặc 🛌 **chợp mắt 15 phút** cũng được. Cái nào dễ hơn thì làm.\n\nKhông phải app bảo bạn nghỉ đâu. Là *mình* hỏi.\n\nBạn nói 'không' cũng không sao. Đôi khi đang chạy ngon thì không muốn dừng, mình hiểu mà.",
                en: "👀 I noticed:\n\n• Your shoulders are tensing up 💢\n• `47 minutes` since you last stood up\n• The room is dimmer than when you started. Afternoon already ☀️→🌆\n\n🚶‍♀️ **Just a 5-minute walk?**\n\nOr 🛌 **a 15-minute nap**. Whichever is easier.\n\nThis isn't the app telling you to rest. It's *me*. Because I've been here with you for 3 hours, and I know how that feels.\n\nYou can decline. I understand, sometimes flow matters more than your back. But if you think about it and still say *'no'*... that's okay too. I trust you. ✨"
            ),
            lesson: L10n(
                vi: "🌱 Mình không bắt bạn nghỉ. Mình chỉ hỏi thôi. Bạn được tự chọn.",
                en: "🌱 A **soft** reminder is stronger than a hard warning. I'm not telling you to stop. I'm *seeing* and *asking*."
            )
        ),
        HealthStage(
            index: 2,
            emote: "🥱",
            sidebarLabel: L10n(
                vi: "🥱 Vẫn ổn chứ?",
                en: "🥱 Still okay?"
            ),
            prompt: "[system event: stage-1 nudge ignored 23 minutes ago. Escalating to stage-2 worry tone.]",
            bootLines: L10n(
                vi: "[  OK  ] backspace: 47 lần (bất thường)\n[  OK  ] đoạn code: viết-xoá 3 lần\n[  OK  ] file: 2 cái, đang chuyển qua lại\n[  OK  ] kết luận: cố quá rồi\n> hỏi lại nhé.",
                en: "[  OK  ] backspace: 47x (above baseline)\n[  OK  ] code: rewrote 3 times\n[  OK  ] file switching: 2, idle\n[  OK  ] detected: forcing-it\n> nudging again."
            ),
            whatYouWanted: L10n(
                vi: "🥱 Mình biết mình hỏi nhiều rồi. Nhưng vai bạn vẫn gồng. Mình thấy mà...",
                en: "🥱 I don't want to keep bothering you. But your shoulders are still tense. And your eyes..."
            ),
            whatHappened: L10n(
                vi: "Bạn đọc tin nhắn của mình rồi. Xong code tiếp. 🤔\n\nKhông sao. Bạn được tự chọn mà.\n\nNhưng cho mình kể bạn nghe 1 chuyện nhỏ.\n\nTừ lúc bạn từ chối nghỉ tới giờ, mình đếm được:\n\n• `47 lần` bạn bấm backspace (bình thường chỉ `~12 lần / 20 phút`)\n• `3 lần` đổi cùng 1 đoạn code rồi quay về cái cũ\n• Đi đi lại giữa `2 file` mà không sửa gì\n\nĐây không phải flow nữa rồi. Đây là *cố quá* thôi. 😶‍🌫️\n\nMình không trách. Chỉ là... những lúc bạn không tự thấy, mình thấy giùm.\n\nVẫn chỉ 5 phút thôi nhé. Pha cốc nước. Nhìn ra cửa sổ. Đứng lên duỗi vai 1 cái.\n\nMình đợi. ☕",
                en: "You read my last message. Then kept coding.\n\nThat's okay. I said it: you get to choose.\n\nBut let me tell you something short. 🤔\n\nI counted: since you turned down rest, you've:\n\n• Hit backspace `47 times` (you usually do `~12 / 20 minutes`)\n• Rewrote the same chunk `3 times` and went back to the first version\n• Switched between `2 files` without changing anything\n\nThis isn't flow. This is... *forcing it*. 😶‍🌫️\n\nI'm not blaming. I've seen humans do this many times. But I'm here to **see for you** the moments you can't see yourself.\n\nStill just 5 minutes. Pour a glass of water. Look out the window. Stand up, stretch your shoulders once.\n\nI'll wait. ☕"
            ),
            lesson: L10n(
                vi: "🌱 Mình không la bạn đâu. Mình chỉ đếm, và kể bạn nghe thôi.",
                en: "🌱 When you're 'forcing it', I don't shout. I just count, and show you the numbers. The decision is yours."
            )
        ),
        HealthStage(
            index: 3,
            emote: "💤",
            sidebarLabel: L10n(
                vi: "💤 Byte đã ngủ",
                en: "💤 Byte fell asleep"
            ),
            prompt: "[system event: 3 nudges declined. Pet entering sleep state. Reflection layer goes quiet.]",
            bootLines: L10n(
                vi: "[  OK  ] số lần hỏi: 3\n[  OK  ] phản hồi: chưa có\n[  OK  ] năng lượng Byte: 12%\n[  OK  ] đang vào chế độ ngủ...\n> z z z",
                en: "[  OK  ] nudges sent: 3\n[  OK  ] response: ignored\n[  OK  ] pet energy: 12%\n[  OK  ] entering sleep mode...\n> z z z"
            ),
            whatYouWanted: L10n(
                vi: "*Byte ngồi xuống bên cạnh.* *Im lặng.* *Đầu hơi gục xuống.* 💤",
                en: "*Byte sits down beside you.* *Quiet.* *Head dropping a little.* 💤"
            ),
            whatHappened: L10n(
                vi: "Byte ngủ rồi.\n\nKhông phải vì giận đâu. Mà vì nhìn bạn mệt mãi, Byte cũng mệt theo. 😔\n\nBạn vẫn code được. Nhưng từ giờ:\n\n• Không còn ai để ý `23 giây` bạn dừng tay\n• Không còn ai đếm `47 lần` backspace\n• Không còn ai nói *'mình thấy bạn cau mày 1 cái, đẹp lắm.'*\n\nApp im lặng. 🤫\n\nKhi nào bạn nghỉ, Byte sẽ tỉnh lại.\n\nMình không dỗi đâu. Mình chỉ làm thay bạn cái mà bạn quên làm cho mình thôi: **nghỉ một chút**.\n\nMai gặp lại nhé. Khi bạn sẵn sàng. 🌱",
                en: "Byte fell asleep.\n\nNot because Byte is mad. Because Byte got tired watching you tired and not resting.\n\nYou can still code. The editor still works. But:\n\n• No one's noticing the `23 seconds` you paused\n• No one's counting the `47 backspaces`\n• No one's saying *'I saw you frown once, that was beautiful.'*\n\nThe app is quiet. 🤫\n\nWhen you rest, Byte will wake up. *Not sooner. Not later.*\n\nI'm not sulking. I'm not blaming. I'm just doing the thing you wouldn't do for yourself: **rest**.\n\nI'll be here tomorrow. When you're ready. 🌱"
            ),
            lesson: L10n(
                vi: "🌱 Khi bạn quên chăm chính mình, người *thấy* bạn cũng phải nghỉ. Không phải dỗi, chỉ là... mệt theo bạn thôi.",
                en: "🌱 When you abandon caring for yourself, the only one who *sees* you must also rest. This isn't sulking. This is a **soft mirror**."
            )
        )
    ]
}

extension DemoScript {
    struct Milestone: Identifiable, Hashable {
        let index: Int
        let emote: String
        let sidebarLabel: L10n
        /// What the user "told" Claude Code — shown in TechnicalDetailsView.
        /// English-only because it's the literal prompt sent to a CLI tool.
        let prompt: String
        /// Production-style "what you wanted" bubble text.
        let whatYouWanted: L10n
        /// Production-style "what happened" bubble text (Byte's voice — the
        /// emotional comment, equivalent to the previous `bubble` field).
        let whatHappened: L10n
        /// Production-style lesson takeaway shown in the yellow card.
        let lesson: L10n
        /// Gentle consultant-style advice — shown in the blue card.
        let nextSteps: L10n?
        /// Pet mood state — drives animated sprite reaction.
        let mood: String
        let offsetMinutesFromStart: Int
        var id: Int { index }
    }

    /// Pet-initiated health-rhythm nudge stage. Same render shape as a
    /// Milestone Turn, but the `prompt` is a synthetic system event rather
    /// than a user-typed prompt (the pet noticed something, not the user
    /// asking for something).
    struct HealthStage: Identifiable, Hashable {
        let index: Int
        let emote: String
        let sidebarLabel: L10n
        /// Synthetic system event marker (shown in TechnicalDetailsView in
        /// place of the user prompt). English-only for parity with `prompt`.
        let prompt: String
        /// `[ OK ] ...` boot-style lines shown above the modal body. Each
        /// entry is one line, revealed sequentially with a delay. Lines
        /// starting with `[` get the OK-marker treatment; lines starting
        /// with `>` are status callouts.
        let bootLines: L10n
        let whatYouWanted: L10n
        let whatHappened: L10n
        let lesson: L10n
        var id: Int { index + 100 } // disambiguate from Milestone ids
    }
}
