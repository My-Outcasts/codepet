import Foundation

extension DictionaryContent {

    static let controlFlowTerms: [DictionaryTerm] = [

        .init(
            id: "if-else", topicId: "control-flow",
            title: L10n(vi: "If / else", en: "If / else"),
            cardDefinition: L10n(
                vi: "Một **ngã rẽ**: làm việc này nếu đúng, làm việc kia nếu sai.",
                en: "A **fork in the road**: do one thing if true, another if false."
            ),
            whatItReallyMeans: L10n(
                vi: "Code kiểm tra một câu hỏi đúng/sai rồi **chỉ chạy một trong hai nhánh**. Phần `if` chạy khi câu trả lời là đúng; phần `else` là phương án dự phòng khi sai. Không bao giờ chạy cả hai.",
                en: "The code checks a true/false question and **runs only one of two branches**. The `if` part runs when the answer is true; the `else` part is the fallback when it's false. Never both."
            ),
            diagram: DiagramSpec(.fork,
                [L10n(vi: "score ≥ 100?", en: "score ≥ 100?"),
                 L10n(vi: "Thắng!", en: "You win!"),
                 L10n(vi: "Thử lại", en: "Try again")],
                accent: .teal),
            codeExample: "if score >= 100 {\n    print(\"You win!\")\n} else {\n    print(\"Try again\")\n}",
            whenToUse: L10n(
                vi: "Mỗi khi chương trình phải **chọn giữa hai hướng** dựa trên một điều kiện.",
                en: "Any time your program must **choose between two paths** based on a condition."
            ),
            tags: [], related: ["conditional", "boolean", "break-continue", "guard-early-return"]
        ),

        .init(
            id: "loop", topicId: "control-flow",
            title: L10n(vi: "Vòng lặp (Loop)", en: "Loop"),
            cardDefinition: L10n(
                vi: "Một khối code chạy **đi chạy lại** cho đến khi bạn bảo dừng.",
                en: "A block of code that runs **over and over** until you tell it to stop."
            ),
            whatItReallyMeans: L10n(
                vi: "Thay vì chép tay cùng một việc mười lần, bạn viết nó một lần và bảo máy *\"lặp lại đến khi đủ\"*. Mỗi vòng làm thêm một phần; vòng lặp tự dừng khi điều kiện đã thỏa.",
                en: "Instead of copy-pasting the same action ten times, you write it once and tell the computer *\"repeat until done\"*. Each pass does one more piece; the loop stops itself once the condition is met."
            ),
            diagram: DiagramSpec(.cycle,
                [L10n(vi: "xây thêm 1 viên", en: "add one brick"),
                 L10n(vi: "đủ 10 viên thì dừng", en: "stop at 10 bricks")],
                accent: .purple),
            codeExample: "for i in 1...3 {\n    print(\"Round \\(i)\")\n}\n// Round 1, Round 2, Round 3",
            whenToUse: L10n(
                vi: "Bất cứ khi nào bạn định **chép cùng một đoạn code** từ 3 lần trở lên.",
                en: "Any time you'd otherwise **copy the same code** three or more times."
            ),
            tags: [], related: ["iteration", "break-continue", "array"]
        ),

        .init(
            id: "iteration", topicId: "control-flow",
            title: L10n(vi: "Lặp (Iteration)", en: "Iteration"),
            cardDefinition: L10n(
                vi: "**Một lần chạy** qua vòng lặp — một bước trong cả quá trình lặp.",
                en: "**One single pass** through a loop — one step of the whole repeat."
            ),
            whatItReallyMeans: L10n(
                vi: "Vòng lặp là *cả công việc* xây bức tường; iteration là *từng viên gạch* được đặt xuống. Mỗi lần khối code chạy lại từ đầu là một iteration. Đi qua một danh sách từng món một cũng là lặp.",
                en: "A loop is the *whole job* of building a wall; an iteration is *each single brick* going down. Every time the code block runs from the top, that's one iteration. Going through a list one item at a time is iterating too."
            ),
            diagram: DiagramSpec(.cycle,
                [L10n(vi: "đặt 1 viên gạch", en: "place one brick"),
                 L10n(vi: "hết danh sách thì dừng", en: "stop at end of list")],
                accent: .purple),
            codeExample: "for color in [\"red\", \"green\", \"blue\"] {\n    print(color)   // one iteration per color\n}",
            whenToUse: L10n(
                vi: "Là từ vựng để nói về **một bước** khi mô tả hay gỡ lỗi một vòng lặp.",
                en: "It's the vocabulary for **a single step** when you describe or debug a loop."
            ),
            tags: [], related: ["loop", "array"]
        ),

        .init(
            id: "recursion", topicId: "control-flow",
            title: L10n(vi: "Đệ quy (Recursion)", en: "Recursion"),
            cardDefinition: L10n(
                vi: "Một hàm giải bài toán bằng cách **tự gọi lại chính nó** trên phần nhỏ hơn.",
                en: "A function that solves a problem by **calling itself** on a smaller piece."
            ),
            whatItReallyMeans: L10n(
                vi: "Giống búp bê gỗ Nga lồng nhau: mở con ngoài, bên trong lại có con nhỏ hơn, mở tiếp… đến con cuối cùng không mở được nữa thì **dừng**. Mỗi bước xử lý một phần rồi giao phần còn lại cho chính nó. Luôn cần một điểm dừng, nếu không sẽ lặp mãi.",
                en: "Like Russian nesting dolls: open the outer one, there's a smaller one inside, open that… until the last one won't open and you **stop**. Each step handles one piece and hands the rest to itself. You always need a stopping point, or it goes forever."
            ),
            diagram: DiagramSpec(.nesting,
                [L10n(vi: "factorial(3)", en: "factorial(3)"),
                 L10n(vi: "factorial(2)", en: "factorial(2)"),
                 L10n(vi: "factorial(1) = 1", en: "factorial(1) = 1")],
                accent: .purple,
                caption: L10n(vi: "Mỗi lớp gọi lại chính nó trên phần nhỏ hơn — tới lớp cuối thì dừng.",
                              en: "Each layer calls itself on a smaller piece — the last one stops.")),
            codeExample: "func factorial(_ n: Int) -> Int {\n    if n <= 1 { return 1 }\n    return n * factorial(n - 1)\n}",
            whenToUse: L10n(
                vi: "Khi bài toán tự nhiên **tách thành phiên bản nhỏ hơn** của chính nó — duyệt cây, dữ liệu lồng nhau.",
                en: "When a problem naturally **breaks into smaller versions** of itself — walking a tree, nested data."
            ),
            tags: [], related: ["function", "loop"]
        ),

        .init(
            id: "conditional", topicId: "control-flow",
            title: L10n(vi: "Điều kiện (Conditional)", en: "Conditional"),
            cardDefinition: L10n(
                vi: "Một câu hỏi **đúng hay sai** — chính là câu mà `if` đặt ra.",
                en: "A **true-or-false question** — the very thing an `if` asks."
            ),
            whatItReallyMeans: L10n(
                vi: "Trước khi rẽ nhánh, code cần một câu hỏi có câu trả lời đúng/sai, ví dụ `age >= 18`. Câu hỏi đó là điều kiện; câu trả lời quyết định nhánh nào được chạy. Điều kiện luôn rút gọn về `true` hoặc `false`.",
                en: "Before it forks, the code needs a question with a true/false answer, like `age >= 18`. That question is the condition; its answer decides which branch runs. A condition always boils down to `true` or `false`."
            ),
            diagram: DiagramSpec(.fork,
                [L10n(vi: "age ≥ 18?", en: "age ≥ 18?"),
                 L10n(vi: "người lớn", en: "adult"),
                 L10n(vi: "chưa đủ tuổi", en: "not yet")],
                accent: .blue),
            codeExample: "let isAdult = age >= 18\nif isAdult { /* show full content */ }",
            whenToUse: L10n(
                vi: "Bất cứ khi nào code cần **quyết định** dựa trên một câu hỏi đúng/sai.",
                en: "Whenever code needs to **make a decision** from a true/false question."
            ),
            tags: [], related: ["if-else", "boolean"]
        ),

        .init(
            id: "break-continue", topicId: "control-flow",
            title: L10n(vi: "Break / Continue", en: "Break / Continue"),
            cardDefinition: L10n(
                vi: "Hai cách bẻ lái vòng lặp: **dừng hẳn** (break) hoặc **bỏ qua sang vòng sau** (continue).",
                en: "Two ways to bend a loop: **stop it entirely** (break) or **skip to the next pass** (continue)."
            ),
            whatItReallyMeans: L10n(
                vi: "Đang lặp qua một danh sách mà gặp món hỏng: `continue` nghĩa là *\"bỏ món này, làm tiếp món sau\"*; `break` nghĩa là *\"thôi, dừng cả vòng lặp luôn\"*. Một cái bỏ qua một bước, một cái kết thúc toàn bộ.",
                en: "Mid-loop you hit a bad item: `continue` means *\"skip this one, carry on with the next\"*; `break` means *\"stop the whole loop right now\"*. One skips a single step, the other ends the entire thing."
            ),
            diagram: DiagramSpec(.cycle,
                [L10n(vi: "xét từng món", en: "check each item"),
                 L10n(vi: "break = dừng cả vòng", en: "break = stop the loop")],
                accent: .orange),
            codeExample: "for n in 1...10 {\n    if n == 5 { break }        // stop the loop\n    if n % 2 == 0 { continue } // skip evens\n    print(n)                   // 1, 3\n}",
            whenToUse: L10n(
                vi: "Trong vòng lặp, khi một điều kiện nghĩa là *\"xong rồi\"* (break) hoặc *\"món này bỏ qua\"* (continue).",
                en: "Inside loops, when a condition means *\"we're done\"* (break) or *\"this one doesn't count\"* (continue)."
            ),
            tags: [], related: ["loop", "if-else"]
        ),

        .init(
            id: "error-handling", topicId: "control-flow",
            title: L10n(vi: "Xử lý lỗi (try / catch)", en: "Error handling (try / catch)"),
            cardDefinition: L10n(
                vi: "Một kế hoạch B: **thử** một việc có thể hỏng, và **bắt** lỗi để xử lý thay vì để app sập.",
                en: "A plan B: **try** something that might fail, and **catch** the error to handle it instead of crashing."
            ),
            whatItReallyMeans: L10n(
                vi: "Vài việc có thể thất bại ngoài tầm kiểm soát — mạng rớt, file không tồn tại. Bạn bọc việc đó trong `try`; chạy ngon thì đi tiếp, hỏng thì nhảy sang `catch` để xử lý nhẹ nhàng (báo người dùng, thử lại) thay vì để cả chương trình đổ.",
                en: "Some actions can fail outside your control — the network drops, a file isn't there. You wrap that action in `try`; if it works you continue, if it fails you jump to `catch` and handle it gracefully (warn the user, retry) instead of letting the whole program fall over."
            ),
            diagram: DiagramSpec(.fork,
                [L10n(vi: "chạy có ổn không?", en: "did it work?"),
                 L10n(vi: "dùng kết quả", en: "use the result"),
                 L10n(vi: "catch & khắc phục", en: "catch & recover")],
                accent: .orange,
                caption: L10n(vi: "Chạy ngon → đi tiếp. Hỏng → nhảy vào `catch`.",
                              en: "Works → carry on. Fails → jump into `catch`.")),
            codeExample: "do {\n    let data = try load(file)\n    use(data)\n} catch {\n    print(\"Couldn't load: \\(error)\")\n}",
            whenToUse: L10n(
                vi: "Quanh **bất kỳ việc nào có thể hỏng** mà bạn không kiểm soát — đọc file, gọi mạng, phân tích dữ liệu.",
                en: "Around **anything that can fail** outside your control — reading files, network calls, parsing data."
            ),
            tags: [], related: ["conditional", "if-else", "async-await"]
        ),

        .init(
            id: "guard-early-return", topicId: "control-flow",
            title: L10n(vi: "Guard / thoát sớm", en: "Guard / early return"),
            cardDefinition: L10n(
                vi: "Kiểm tra điều kiện **ngay đầu** hàm và **thoát ra sớm** nếu không thỏa — phần còn lại khỏi phải lo.",
                en: "Check a condition **at the top** of a function and **bail out early** if it fails — so the rest doesn't have to worry."
            ),
            whatItReallyMeans: L10n(
                vi: "Thay vì bọc cả thân hàm trong một `if` lồng sâu, bạn kiểm tra trước: *\"không có tên? thoát ngay.\"* Qua được cửa đó thì mọi dòng phía dưới biết chắc điều kiện đã đúng. Code phẳng hơn, dễ đọc hơn — như người gác cửa chặn trường hợp xấu ngay từ đầu.",
                en: "Instead of wrapping the whole body in a deeply nested `if`, you check up front: *\"no name? leave now.\"* Past that gate, every line below knows the condition already holds. The code stays flat and readable — like a bouncer turning away the bad cases at the door."
            ),
            diagram: DiagramSpec(.fork,
                [L10n(vi: "tên bị rỗng?", en: "name is empty?"),
                 L10n(vi: "thoát ngay", en: "return early"),
                 L10n(vi: "chạy tiếp yên tâm", en: "continue safely")],
                accent: .teal,
                caption: L10n(vi: "Trường hợp xấu → thoát ngay. Còn lại → chạy yên tâm.",
                              en: "Bad case → leave now. Otherwise → run with confidence.")),
            codeExample: "func greet(_ name: String?) {\n    guard let name else { return }\n    print(\"Hi, \\(name)\")   // name is safe here\n}",
            whenToUse: L10n(
                vi: "Ở **đầu hàm**, để loại các trường hợp xấu (rỗng, nil, sai) trước khi làm việc chính.",
                en: "At the **top of a function**, to rule out bad cases (empty, nil, invalid) before the real work."
            ),
            tags: [], related: ["if-else", "conditional", "null"]
        ),
    ]
}
