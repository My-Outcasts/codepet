import Foundation

extension DictionaryContent {

    static let variablesTerms: [DictionaryTerm] = [

        .init(
            id: "variable", topicId: "variables",
            title: L10n(vi: "Biến", en: "Variable"),
            cardDefinition: L10n(
                vi: "Một **cái hộp có tên** để giữ một thứ mà chương trình có thể đổi sau này.",
                en: "A **named box** that holds something your program can change later."
            ),
            whatItReallyMeans: L10n(
                vi: "Cái tên (ví dụ `score`) luôn dán chặt vào hộp đó. Bạn thay thứ bên trong bao nhiêu lần cũng được mà tên không đổi — nhờ vậy code nhắc tới `score` ở mọi nơi mà không cần biết lúc này trong hộp đang là số mấy.",
                en: "The name (say `score`) stays stuck to that box. You can swap what's inside as many times as you like and the name never changes — so your code can say `score` everywhere without caring what number is in it right now."
            ),
            diagram: DiagramSpec(.labeledBox,
                [L10n(vi: "score", en: "score"), L10n(vi: "10", en: "10")],
                accent: .purple,
                caption: L10n(vi: "Tên dán bên ngoài, giá trị nằm bên trong.",
                              en: "Name on the outside, value tucked inside.")),
            codeExample: "var score = 0\nscore = score + 10\n// score is now 10",
            whenToUse: L10n(
                vi: "Mỗi khi một giá trị **sẽ thay đổi** lúc chương trình chạy — bộ đếm, ô nhập của người dùng, kết quả một phép tính.",
                en: "Any time a value **will change** while your program runs — counters, user input, the result of a calculation."
            ),
            tags: [], related: ["constant", "string", "number"]
        ),

        .init(
            id: "constant", topicId: "variables",
            title: L10n(vi: "Hằng số", en: "Constant"),
            cardDefinition: L10n(
                vi: "Một cái hộp có tên mà **một khi đã bỏ đồ vào thì khóa lại** — không đổi được nữa.",
                en: "A named box that, **once you put something in, locks shut** — it can't change."
            ),
            whatItReallyMeans: L10n(
                vi: "Giống như biến, nhưng được khóa. Sau khi đặt giá trị lần đầu, bạn không gán lại được nữa; nếu cố thử, máy sẽ báo lỗi ngay. Cái lợi: khi đọc code bạn **biết chắc** giá trị này không bị đổi lén ở đâu đó.",
                en: "Like a variable, but locked. After you set it the first time you can't reassign it; if you try, the computer flags it immediately. The payoff: when you read the code you **know for sure** this value isn't being changed behind your back."
            ),
            diagram: DiagramSpec(.labeledBox,
                [L10n(vi: "maxTries 🔒", en: "maxTries 🔒"), L10n(vi: "3", en: "3")],
                accent: .gold,
                caption: L10n(vi: "Đặt một lần rồi khóa — không gán lại được.",
                              en: "Set once, then locked — no reassigning.")),
            codeExample: "let maxAttempts = 3\n// maxAttempts = 4   // ✗ error",
            whenToUse: L10n(
                vi: "Cứ chọn **hằng số trước**. Chỉ dùng biến khi thật sự cần gán lại. Hằng số làm code dễ đọc, dễ tin hơn.",
                en: "Reach for a **constant first**. Use a variable only when you actually need to reassign. Constants make code easier to read and trust."
            ),
            tags: [], related: ["variable"]
        ),

        .init(
            id: "string", topicId: "variables",
            title: L10n(vi: "Chuỗi (String)", en: "String"),
            cardDefinition: L10n(
                vi: "Một đoạn **chữ** — chữ cái, chữ số, khoảng trắng, emoji, bất cứ gì viết ra được.",
                en: "A piece of **text** — letters, digits, spaces, emoji, anything you can type."
            ),
            whatItReallyMeans: L10n(
                vi: "Máy tính coi đoạn chữ là một dãy ký tự nối liền nhau. Bạn đọc được cả dãy, đếm số ký tự, hoặc **nối** hai đoạn lại thành một câu dài hơn. Chữ luôn nằm trong dấu nháy: `\"hello\"`.",
                en: "The computer treats text as a chain of characters joined together. You can read the whole chain, count its characters, or **join** two pieces into one longer sentence. Text always sits inside quotes: `\"hello\"`."
            ),
            diagram: DiagramSpec(.labeledBox,
                [L10n(vi: "greeting", en: "greeting"), L10n(vi: "\"hello\"", en: "\"hello\"")],
                accent: .pink,
                caption: L10n(vi: "Chữ luôn đặt trong dấu nháy.",
                              en: "Text always lives inside quotes.")),
            codeExample: "let greeting = \"hello\"\nlet name = \"Ada\"\nlet message = greeting + \", \" + name",
            whenToUse: L10n(
                vi: "Cho **mọi thứ là chữ** — tên, tin nhắn, nhãn nút bấm, địa chỉ.",
                en: "For **anything made of text** — names, messages, button labels, addresses."
            ),
            tags: [], related: ["number", "boolean"]
        ),

        .init(
            id: "number", topicId: "variables",
            title: L10n(vi: "Số", en: "Number"),
            cardDefinition: L10n(
                vi: "Một giá trị **số** — số nguyên như `7`, hoặc số lẻ như `9.99`.",
                en: "A **numeric** value — a whole number like `7`, or a decimal like `9.99`."
            ),
            whatItReallyMeans: L10n(
                vi: "Có hai kiểu hay gặp: số nguyên (`Int`) để **đếm** — 0, 1, 2, 3 — và số thập phân (`Float`/`Double`) để **đo** — 1.5, 3.14. Cùng ý tưởng, khác độ chính xác.",
                en: "Two kinds show up a lot: whole numbers (`Int`) for **counting** — 0, 1, 2, 3 — and decimals (`Float`/`Double`) for **measuring** — 1.5, 3.14. Same idea, different precision."
            ),
            diagram: DiagramSpec(.labeledBox,
                [L10n(vi: "price", en: "price"), L10n(vi: "9.99", en: "9.99")],
                accent: .teal,
                caption: L10n(vi: "Đếm → số nguyên. Đo → số thập phân.",
                              en: "Counting → whole. Measuring → decimal.")),
            codeExample: "let count: Int = 7\nlet price: Double = 9.99",
            whenToUse: L10n(
                vi: "Mỗi khi cần **tính toán hoặc đếm** — điểm, giá tiền, số lượng.",
                en: "Any time you need to **calculate or count** — scores, prices, quantities."
            ),
            tags: [], related: ["variable", "boolean"]
        ),

        .init(
            id: "boolean", topicId: "variables",
            title: L10n(vi: "Boolean", en: "Boolean"),
            cardDefinition: L10n(
                vi: "Một giá trị **chỉ có hai mặt**: `true` (đúng) hoặc `false` (sai).",
                en: "A value with **only two faces**: `true` or `false`."
            ),
            whatItReallyMeans: L10n(
                vi: "Không có gì ở giữa — không nửa-đúng, không nửa-sai. Đây là kiểu dữ liệu để code đặt **câu hỏi có/không** và nhận câu trả lời dứt khoát, rồi dựa vào đó mà quyết định làm gì tiếp.",
                en: "Nothing in between — no half-true, no half-false. It's the type your code uses to ask a **yes/no question** and get a firm answer, then decide what to do next based on it."
            ),
            diagram: DiagramSpec(.labeledBox,
                [L10n(vi: "isLoggedIn", en: "isLoggedIn"), L10n(vi: "true ✅", en: "true ✅")],
                accent: .orange,
                caption: L10n(vi: "Chỉ `true` hoặc `false` — không có lựa chọn thứ ba.",
                              en: "Only `true` or `false` — no third option.")),
            codeExample: "let isLoggedIn = true\nif isLoggedIn { /* show dashboard */ }",
            whenToUse: L10n(
                vi: "Khi code cần một **câu hỏi có/không** — *\"đã đăng nhập chưa?\"*, *\"tải xong chưa?\"*.",
                en: "When your code needs a **yes/no question** — *\"is the user signed in?\"*, *\"did the upload finish?\"*."
            ),
            tags: [], related: ["if-else", "conditional"]
        ),

        .init(
            id: "array", topicId: "variables",
            title: L10n(vi: "Mảng (Array)", en: "Array"),
            cardDefinition: L10n(
                vi: "Một **danh sách có thứ tự**, lấy từng món ra bằng vị trí của nó.",
                en: "An **ordered list** of things, where you grab each one by its position."
            ),
            whatItReallyMeans: L10n(
                vi: "Tưởng tượng một dãy ô đánh số bắt đầu từ `0`: `[0] [1] [2]`. Mỗi ô giữ một món. Bạn đưa cho mảng con số `2`, nó mở ô số 2 và đưa lại món bên trong. Thứ tự là cố định, nên bạn luôn biết món nào *đầu tiên*, *thứ hai*, *thứ ba*.",
                en: "Picture a row of numbered slots starting at `0`: `[0] [1] [2]`. Each slot holds one thing. Hand the array the number `2` and it opens slot 2 and gives you what's inside. The order is fixed, so you always know which item is *first*, *second*, *third*."
            ),
            diagram: DiagramSpec(.indexedSlots,
                [L10n(vi: "\"red\"", en: "\"red\""),
                 L10n(vi: "\"green\"", en: "\"green\""),
                 L10n(vi: "\"blue\"", en: "\"blue\"")],
                accent: .purple,
                caption: L10n(vi: "Mỗi ô đánh số từ 0 — đưa số là lấy đúng món.",
                              en: "Each slot is numbered from 0 — give the number, get that item.")),
            codeExample: "let colors = [\"red\", \"green\", \"blue\"]\nlet first = colors[0]   // \"red\"",
            whenToUse: L10n(
                vi: "Khi có **một bộ nhiều món giống nhau** và *thứ tự quan trọng* — danh sách việc cần làm, hàng đợi tin nhắn.",
                en: "When you have a **collection of similar things** and *order matters* — a to-do list, a queue of messages."
            ),
            tags: [], related: ["variable", "iteration", "object"]
        ),

        .init(
            id: "object", topicId: "variables",
            title: L10n(vi: "Đối tượng (Object)", en: "Object"),
            cardDefinition: L10n(
                vi: "Một **bảng tra cứu**: đưa một cái tên (khóa), nhận lại giá trị gắn với nó.",
                en: "A **labeled lookup**: give it a name (a key), get back the value tied to it."
            ),
            whatItReallyMeans: L10n(
                vi: "Mảng lấy món theo *số thứ tự*; đối tượng lấy món theo *tên*. Giống một cuốn danh bạ: tra `\"Ada\"` là ra số của Ada. Mỗi cặp là một *khóa → giá trị*. Khóa phải là duy nhất, nhưng thứ tự thì không quan trọng.",
                en: "An array fetches things by *number*; an object fetches them by *name*. Like a phone book: look up `\"Ada\"` and get Ada's number. Each pair is a *key → value*. Keys must be unique, but their order doesn't matter."
            ),
            diagram: DiagramSpec(.keyValue,
                [L10n(vi: "name: \"Ada\"", en: "name: \"Ada\""),
                 L10n(vi: "level: 7", en: "level: 7"),
                 L10n(vi: "online: true", en: "online: true")],
                accent: .purple,
                caption: L10n(vi: "Tra theo khóa (tên), không theo số vị trí.",
                              en: "Look it up by key (a name), not by position number.")),
            codeExample: "let user = [\n    \"name\": \"Ada\",\n    \"level\": 7\n]\nlet who = user[\"name\"]   // \"Ada\"",
            whenToUse: L10n(
                vi: "Khi bạn cần **tra cứu theo tên** thay vì theo vị trí — hồ sơ người dùng, cài đặt, đếm số lần xuất hiện.",
                en: "When you need to **look things up by name** instead of position — a user profile, settings, counting occurrences."
            ),
            tags: [], related: ["array", "json", "variable"]
        ),

        .init(
            id: "null", topicId: "variables",
            title: L10n(vi: "Rỗng (null / nil)", en: "Null (nil)"),
            cardDefinition: L10n(
                vi: "Một cái hộp **cố tình để trống** — \"chưa có giá trị nào ở đây\".",
                en: "A box that's **empty on purpose** — \"there's no value here yet.\""
            ),
            whatItReallyMeans: L10n(
                vi: "Khác với số `0` hay chuỗi rỗng `\"\"` (đó vẫn là *một* giá trị), `nil` nghĩa là *không có gì cả* — như ô \"số điện thoại\" mà người dùng bỏ trống. Lập trình viên phải **kiểm tra nil trước khi dùng**, nếu không chương trình dễ vấp ngã đúng ngay chỗ trống đó.",
                en: "Unlike `0` or an empty string `\"\"` (those are still *a* value), `nil` means *nothing at all* — like a \"phone number\" field left blank. You must **check for nil before using it**, or the program trips over that empty spot."
            ),
            diagram: DiagramSpec(.labeledBox,
                [L10n(vi: "phone", en: "phone"), L10n(vi: "nil ∅", en: "nil ∅")],
                accent: .orange,
                caption: L10n(vi: "Không phải số 0 — mà là *chưa có gì*.",
                              en: "Not zero — *nothing's there yet*.")),
            codeExample: "var phone: String? = nil\nif let p = phone {\n    print(p)   // only runs when not nil\n}",
            whenToUse: L10n(
                vi: "Khi một giá trị **có thể chưa tồn tại** — ô người dùng bỏ trống, dữ liệu chưa tải xong.",
                en: "When a value **might not exist yet** — a field left blank, data that hasn't loaded."
            ),
            tags: [], related: ["variable", "boolean"]
        ),
    ]
}
