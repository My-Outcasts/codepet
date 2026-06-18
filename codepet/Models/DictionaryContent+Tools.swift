import Foundation

extension DictionaryContent {

    static let toolsTerms: [DictionaryTerm] = [

        .init(
            id: "git", topicId: "tools",
            title: L10n(vi: "Git", en: "Git"),
            cardDefinition: L10n(
                vi: "Công cụ **chụp ảnh** mọi thay đổi code, để bạn xem lại, hoàn tác hoặc chia sẻ.",
                en: "A tool that **snapshots** every code change, so you can review, undo, or share."
            ),
            whatItReallyMeans: L10n(
                vi: "Mỗi lần bạn lưu một bước, git ghi lại một bức ảnh của toàn bộ dự án kèm lời ghi chú. Chuỗi ảnh đó là **lịch sử** — bạn quay về bất kỳ điểm nào, so sánh hai điểm, hay tách nhánh để thử hướng mới mà không sợ hỏng bản chính.",
                en: "Each time you save a step, git records a photo of the whole project with a note. That chain of photos is your **history** — go back to any point, compare two of them, or branch off to try a new direction without risking the main copy."
            ),
            diagram: DiagramSpec(.timeline,
                [L10n(vi: "bắt đầu", en: "start"),
                 L10n(vi: "thêm lời chào", en: "add greeting"),
                 L10n(vi: "sửa lỗi", en: "fix a bug")],
                accent: .gold,
                caption: L10n(vi: "Mỗi tấm ảnh là một bản lưu bạn có thể quay lại.",
                              en: "Each photo is a save you can return to.")),
            codeExample: "git add file.swift\ngit commit -m \"Add greeting view\"",
            whenToUse: L10n(
                vi: "Trên **mọi dự án**, từ ngày đầu. Kể cả làm một mình — git là lưới an toàn khi thử nghiệm đi sai.",
                en: "On **every project**, from day one. Even solo — git is your safety net when an experiment goes sideways."
            ),
            tags: [], related: ["commit", "branch", "pull-request", "repository"]
        ),

        .init(
            id: "commit", topicId: "tools",
            title: L10n(vi: "Commit", en: "Commit"),
            cardDefinition: L10n(
                vi: "**Một bản lưu** trong git, kèm câu mô tả bạn vừa đổi gì.",
                en: "**One saved snapshot** in git, with a note describing what changed."
            ),
            whatItReallyMeans: L10n(
                vi: "Mỗi commit là một bức ảnh có chú thích: *\"xây xong tường phía Đông\"*, *\"thêm mái đỏ\"*. Xếp các commit lại, bạn thấy cả câu chuyện dự án lớn lên thế nào. Commit nhỏ và chú thích rõ giúp sau này dễ quay về đúng điểm cần.",
                en: "Each commit is a captioned photo: *\"finished the east wall\"*, *\"added the red roof\"*. Line the commits up and you see the whole story of how the project grew. Small commits with clear notes make it easy to walk back to the exact point you need."
            ),
            diagram: DiagramSpec(.timeline,
                [L10n(vi: "tường Đông", en: "east wall"),
                 L10n(vi: "mái đỏ", en: "red roof"),
                 L10n(vi: "sửa cửa", en: "fix window")],
                accent: .gold),
            codeExample: "git add file.swift\ngit commit -m \"Add greeting view\"",
            whenToUse: L10n(
                vi: "Commit **sớm và thường xuyên**. Nhiều commit nhỏ dễ đọc và dễ hoàn tác hơn một commit khổng lồ.",
                en: "Commit **early and often**. Many small commits are easier to read and undo than one giant one."
            ),
            tags: [], related: ["git", "branch"]
        ),

        .init(
            id: "branch", topicId: "tools",
            title: L10n(vi: "Nhánh (Branch)", en: "Branch"),
            cardDefinition: L10n(
                vi: "Một **bản song song** của dự án, nơi bạn thử việc mới mà không đụng tới bản chính.",
                en: "A **parallel copy** of the project where you try new work without touching the main one."
            ),
            whatItReallyMeans: L10n(
                vi: "Muốn thử một ý mới mà sợ làm hỏng cái đang chạy? Tạo một nhánh — như chép dự án sang một bàn phụ để nghịch. Bản chính (`main`) vẫn nguyên. Thích thì *gộp* nhánh trở lại; không thích thì bỏ đi, bản chính chưa từng bị đụng.",
                en: "Want to try a new idea but afraid of breaking what works? Make a branch — like copying the project to a side table to tinker. The main copy (`main`) stays untouched. Like it? *Merge* the branch back. Don't? Toss it, and main was never disturbed."
            ),
            diagram: DiagramSpec(.timeline,
                [L10n(vi: "main", en: "main"),
                 L10n(vi: "nhánh mới", en: "new branch"),
                 L10n(vi: "gộp lại", en: "merge back")],
                accent: .purple),
            codeExample: "git checkout -b new-feature\n// ... work, commit ...\ngit checkout main\ngit merge new-feature",
            whenToUse: L10n(
                vi: "Cho **bất kỳ thay đổi không nhỏ** — tính năng, sửa lỗi, thử nghiệm. Giữ `main` luôn sạch.",
                en: "For **any non-trivial change** — feature, bugfix, experiment. Keep `main` clean at all times."
            ),
            tags: [], related: ["git", "commit", "pull-request", "merge-conflict"]
        ),

        .init(
            id: "pull-request", topicId: "tools",
            title: L10n(vi: "Pull request", en: "Pull request"),
            cardDefinition: L10n(
                vi: "Một **lời đề nghị gộp** một nhánh vào nhánh khác, mở ra để mọi người xem trước.",
                en: "A **proposal to merge** one branch into another, opened up for people to review first."
            ),
            whatItReallyMeans: L10n(
                vi: "Trước khi đặt phần mới vào bản chính, bạn mời đồng đội xem: *\"đây là thứ tôi vừa làm, ổn không?\"*. Họ góp ý, bạn sửa, máy chạy kiểm tra tự động — rồi mới gộp. Đó là một khoảnh khắc dừng lại có chủ đích để **bắt lỗi sớm**.",
                en: "Before placing the new work into the main copy, you invite teammates to look: *\"here's what I made — does it look right?\"*. They comment, you fix, automated checks run — then it merges. It's a deliberate pause to **catch problems early**."
            ),
            diagram: DiagramSpec(.timeline,
                [L10n(vi: "đề xuất", en: "propose"),
                 L10n(vi: "xem xét", en: "review"),
                 L10n(vi: "gộp", en: "merge")],
                accent: .teal),
            codeExample: nil,
            whenToUse: L10n(
                vi: "Trên **mọi đội nhóm**, và cả khi làm một mình nếu muốn một khoảnh khắc dừng trước khi gộp.",
                en: "On **any team**, and even solo when you want a moment of pause before merging."
            ),
            tags: [], related: ["branch", "git"]
        ),

        .init(
            id: "terminal", topicId: "tools",
            title: L10n(vi: "Terminal", en: "Terminal"),
            cardDefinition: L10n(
                vi: "Một cửa sổ nơi bạn **gõ lệnh chữ** và máy tính chạy chúng — không cần nút bấm.",
                en: "A window where you **type text commands** and the computer runs them — no buttons needed."
            ),
            whatItReallyMeans: L10n(
                vi: "Giao diện app bóng bẩy là bàn lễ tân; terminal là đi thẳng vào trong. Kém màu mè hơn, nhưng bạn ra lệnh trực tiếp, viết kịch bản để máy làm hàng loạt, và làm những việc lặp đi lặp lại nhanh hơn nhiều so với click chuột.",
                en: "The pretty app UI is the front desk; the terminal is walking straight into the back. Less flashy, but you give orders directly, write scripts to do things in bulk, and run repetitive tasks far faster than clicking."
            ),
            diagram: DiagramSpec(.commandFlow,
                [L10n(vi: "ls", en: "ls"),
                 L10n(vi: "file1   file2   file3", en: "file1   file2   file3")],
                accent: .gold,
                caption: L10n(vi: "Gõ một lệnh, máy chạy ngay và trả lại kết quả.",
                              en: "Type a command, the computer runs it and shows the result.")),
            codeExample: "ls          # list files here\ncd projects # go into projects/\npwd         # where am I?",
            whenToUse: L10n(
                vi: "Cho việc **lặp lại, viết được kịch bản, hoặc nằm sâu quá để click** — chạy build, di chuyển nhiều file, nói chuyện với git.",
                en: "For anything **repetitive, scriptable, or buried too deep to click** — running builds, moving many files, talking to git."
            ),
            tags: [], related: ["git", "package-manager", "command"]
        ),

        .init(
            id: "package-manager", topicId: "tools",
            title: L10n(vi: "Trình quản lý gói (Package manager)", en: "Package manager"),
            cardDefinition: L10n(
                vi: "Công cụ **tải và cập nhật** các thư viện của người khác mà dự án bạn cần dùng.",
                en: "A tool that **downloads and updates** the other people's libraries your project relies on."
            ),
            whatItReallyMeans: L10n(
                vi: "Cần một tính năng có sẵn? Thay vì tự viết lại, bạn *đặt* nó từ một kho online bằng một lệnh. Trình quản lý gói tải nó về, kéo theo những thứ nó cần, và ghi sổ đúng phiên bản — nên người khác mở dự án của bạn sẽ nhận lại y hệt bộ thư viện đó.",
                en: "Need a ready-made feature? Instead of rewriting it, you *order* it from an online catalog with one command. The package manager downloads it, pulls in whatever it depends on, and records the exact versions — so anyone else who opens your project gets the very same set of libraries."
            ),
            diagram: DiagramSpec(.commandFlow,
                [L10n(vi: "npm install react", en: "npm install react"),
                 L10n(vi: "react + các gói nó cần", en: "react + its dependencies")],
                accent: .teal,
                caption: L10n(vi: "Một lệnh tải về thư viện và mọi thứ nó cần.",
                              en: "One command fetches the library and everything it needs.")),
            codeExample: "npm install react      # JavaScript\nbrew install ffmpeg    # macOS apps\nswift package add ...  # Swift",
            whenToUse: L10n(
                vi: "Trên **bất kỳ dự án nào** lớn hơn một file. An toàn hơn nhiều so với chép thư viện bằng tay.",
                en: "On **any project** beyond a single file. Far safer than copying library files by hand."
            ),
            tags: [], related: ["terminal", "env-var", "dependency"]
        ),

        .init(
            id: "merge-conflict", topicId: "tools",
            title: L10n(vi: "Xung đột gộp (Merge conflict)", en: "Merge conflict"),
            cardDefinition: L10n(
                vi: "Khi hai nhánh **sửa cùng một dòng** theo hai cách khác nhau, git không tự chọn được — nó nhờ **bạn** quyết.",
                en: "When two branches **change the same line** differently, git can't choose — it asks **you** to decide."
            ),
            whatItReallyMeans: L10n(
                vi: "Thường git tự gộp được vì hai người sửa hai chỗ khác nhau. Nhưng nếu cả hai cùng sửa *đúng một dòng*, git dừng lại và đánh dấu cả hai phiên bản, chờ bạn chọn giữ cái nào (hoặc trộn lại). Không phải lỗi — chỉ là một quyết định máy không dám làm thay bạn.",
                en: "Usually git merges fine because two people edited different spots. But if both changed *the very same line*, git stops and marks both versions, waiting for you to pick which to keep (or blend them). It's not a bug — just a decision the machine won't make for you."
            ),
            diagram: DiagramSpec(.fork,
                [L10n(vi: "cùng dòng, hai bản sửa", en: "same line, two edits"),
                 L10n(vi: "giữ bản của bạn", en: "keep yours"),
                 L10n(vi: "giữ bản của họ", en: "keep theirs")],
                accent: .gold,
                caption: L10n(vi: "Git đánh dấu cả hai bản và để bạn chọn.",
                              en: "Git marks both versions and lets you choose.")),
            codeExample: "<<<<<<< HEAD\nlet color = \"purple\"\n=======\nlet color = \"teal\"\n>>>>>>> new-feature",
            whenToUse: L10n(
                vi: "Xuất hiện khi **gộp nhánh** mà hai bên đụng cùng dòng. Bình tĩnh đọc cả hai, chọn, rồi commit.",
                en: "Shows up when **merging branches** that touched the same line. Calmly read both, choose, then commit."
            ),
            tags: [], related: ["branch", "git", "commit"]
        ),

        .init(
            id: "env-var", topicId: "tools",
            title: L10n(vi: "Biến môi trường (Env var)", en: "Environment variable"),
            cardDefinition: L10n(
                vi: "Một giá trị **để bên ngoài code** — như khóa API hay mật khẩu — để không bị lộ trong mã nguồn.",
                en: "A value kept **outside your code** — like an API key or password — so it never sits in the source."
            ),
            whatItReallyMeans: L10n(
                vi: "Code cần một khóa bí mật để gọi dịch vụ, nhưng *viết thẳng khóa vào code* là nguy hiểm — ai xem code cũng thấy. Thay vào đó bạn để khóa trong một file `.env` riêng (không commit lên git) và code đọc nó lúc chạy. Cùng một code chạy ở máy bạn và trên server, chỉ khác giá trị nạp vào.",
                en: "Your code needs a secret key to call a service, but *writing the key into the code* is risky — anyone who sees the code sees it. Instead you keep the key in a separate `.env` file (never committed to git) and the code reads it at runtime. The same code runs on your machine and on the server — only the values fed in differ."
            ),
            diagram: DiagramSpec(.labeledBox,
                [L10n(vi: "API_KEY 🔒", en: "API_KEY 🔒"), L10n(vi: "sk-•••••", en: "sk-•••••")],
                accent: .gold,
                caption: L10n(vi: "Tên nằm trong code, giá trị thật nạp từ bên ngoài.",
                              en: "The name lives in code, the real value is loaded from outside.")),
            codeExample: "# .env  (never commit this)\nAPI_KEY=sk-12345\n\n// in code\nlet key = ProcessInfo.processInfo\n    .environment[\"API_KEY\"]",
            whenToUse: L10n(
                vi: "Cho **bí mật** (khóa, mật khẩu) và **cấu hình khác nhau** giữa máy dev và server.",
                en: "For **secrets** (keys, passwords) and **config that differs** between your dev machine and the server."
            ),
            tags: [], related: ["constant", "terminal", "package-manager"]
        ),

        .init(
            id: "directory", topicId: "tools",
            title: L10n(vi: "Thư mục (Directory)", en: "Directory"),
            cardDefinition: L10n(
                vi: "Một **cái cặp đựng hồ sơ** chứa các file — và cả thư mục con khác.",
                en: "A **folder** that holds files — and other folders inside it."
            ),
            whatItReallyMeans: L10n(
                vi: "\"Thư mục\" và \"folder\" là cùng một thứ: một chỗ có tên để gom file cho gọn. Thư mục lồng nhau nhiều tầng tạo thành cây thư mục — `dự-án/ → src/ → App.swift`. Đường dẫn (path) chính là lối đi xuyên qua cây đó tới đúng file bạn cần.",
                en: "\"Directory\" and \"folder\" are the same thing: a named place to group files together. Directories nest inside each other into a tree — `project/ → src/ → App.swift`. A path is the route through that tree to the exact file you want."
            ),
            diagram: nil,
            codeExample: "myapp/\n  src/\n    App.swift\n  README.md",
            whenToUse: L10n(
                vi: "Để **sắp xếp dự án** — nhóm code, ảnh, tài liệu vào các thư mục riêng cho dễ tìm.",
                en: "To **organize a project** — group code, images, and docs into separate folders so things are easy to find."
            ),
            tags: [], related: ["terminal", "file", "repository"]
        ),

        .init(
            id: "file", topicId: "tools",
            title: L10n(vi: "Tập tin (File)", en: "File"),
            cardDefinition: L10n(
                vi: "Một **tài liệu có tên** lưu trên máy — code, ảnh, văn bản, bất cứ gì.",
                en: "A single **named document** saved on disk — code, an image, text, anything."
            ),
            whatItReallyMeans: L10n(
                vi: "Mỗi file có một cái tên và một phần đuôi (ví dụ `App.swift`). Phần đuôi `.swift` cho máy biết bên trong là loại gì. Code của bạn sống trong các file; sửa file rồi lưu lại chính là cách bạn thay đổi chương trình.",
                en: "Each file has a name and an extension (e.g. `App.swift`). The `.swift` part tells the computer what kind of content is inside. Your code lives in files; editing a file and saving is how you change the program."
            ),
            diagram: DiagramSpec(.labeledBox,
                [L10n(vi: "App.swift", en: "App.swift"), L10n(vi: "</> code", en: "</> code")],
                accent: .teal,
                caption: L10n(vi: "Tên + đuôi ở ngoài, nội dung ở trong.",
                              en: "Name + extension outside, content inside.")),
            codeExample: nil,
            whenToUse: L10n(
                vi: "Là **đơn vị cơ bản** bạn làm việc cùng mỗi ngày — mở, sửa, lưu, commit.",
                en: "It's the **basic unit** you work with every day — open, edit, save, commit."
            ),
            tags: [], related: ["directory", "file-extension", "commit"]
        ),

        .init(
            id: "file-extension", topicId: "tools",
            title: L10n(vi: "Phần mở rộng (File extension)", en: "File extension"),
            cardDefinition: L10n(
                vi: "Phần **đuôi sau dấu chấm** trong tên file — `.js`, `.tsx` — cho biết file thuộc loại gì.",
                en: "The **suffix after the dot** in a filename — `.js`, `.tsx` — that signals the file's type."
            ),
            whatItReallyMeans: L10n(
                vi: "`App.tsx` có phần mở rộng `.tsx`: nhìn vào là biết đây là file TypeScript dùng kèm React. Phần đuôi quyết định icon, cách tô màu cú pháp, và công cụ nào xử lý file. Đổi đuôi không đổi nội dung, nhưng có thể làm máy hiểu sai loại file.",
                en: "`App.tsx` has the extension `.tsx`: you can tell at a glance it's a TypeScript file used with React. The suffix decides the icon, the syntax coloring, and which tool handles the file. Renaming the extension doesn't change the content, but it can make tools treat the file as the wrong type."
            ),
            diagram: DiagramSpec(.labeledBox,
                [L10n(vi: ".tsx", en: ".tsx"), L10n(vi: "TS + React", en: "TS + React")],
                accent: .blue,
                caption: L10n(vi: "Đuôi file cho biết ngôn ngữ và công cụ đi kèm.",
                              en: "The extension tells you the language and tooling.")),
            codeExample: "App.tsx     → TypeScript + React\nstyles.css  → CSS\ndata.json   → JSON",
            whenToUse: L10n(
                vi: "Để **nhận ra loại file** ngay từ tên — và biết ngôn ngữ/công cụ nào đi kèm.",
                en: "To **recognize a file's type** straight from its name — and which language/tool goes with it."
            ),
            tags: [], related: ["file", "javascript", "typescript"]
        ),

        .init(
            id: "repository", topicId: "tools",
            title: L10n(vi: "Kho mã (Repository)", en: "Repository (repo)"),
            cardDefinition: L10n(
                vi: "**Thư mục dự án mà git theo dõi** — toàn bộ code của bạn cộng với lịch sử thay đổi.",
                en: "The **project folder git tracks** — all your code plus its full history of changes."
            ),
            whatItReallyMeans: L10n(
                vi: "Khi bạn khởi tạo git trong một thư mục, nó thành một repo: ngoài các file hiện tại, git còn giữ mọi commit từ trước tới giờ. Repo nằm ở máy bạn (local) và thường có một bản trên mạng (ví dụ GitHub) để chia sẻ và sao lưu. Người ta hay gọi tắt là \"repo\".",
                en: "When you start git in a folder, it becomes a repo: beyond the current files, git keeps every commit ever made. A repo lives on your machine (local) and usually has a copy online (e.g. GitHub) for sharing and backup. People shorten it to \"repo\"."
            ),
            diagram: DiagramSpec(.timeline,
                [L10n(vi: "khởi tạo", en: "init"),
                 L10n(vi: "nhiều commit", en: "many commits"),
                 L10n(vi: "hiện tại", en: "now")],
                accent: .gold,
                caption: L10n(vi: "Cả dự án + toàn bộ lịch sử, gói trong một repo.",
                              en: "The whole project + its full history, in one repo.")),
            codeExample: "git init        # turn a folder into a repo\ngit clone <url> # copy an existing repo",
            whenToUse: L10n(
                vi: "Mỗi dự án là **một repo**. Đó là nơi git sống và giữ toàn bộ lịch sử của bạn.",
                en: "Every project is **one repo**. It's where git lives and keeps your whole history."
            ),
            tags: [], related: ["git", "clone", "commit"]
        ),

        .init(
            id: "clone", topicId: "tools",
            title: L10n(vi: "Sao chép (Clone)", en: "Clone"),
            cardDefinition: L10n(
                vi: "**Tải về bản sao của bạn** từ một repo (thường trên mạng) để làm việc ngay tại máy mình.",
                en: "Make your **own local copy** of a repository (usually online) so you can work on it on your machine."
            ),
            whatItReallyMeans: L10n(
                vi: "Khác với tải một file lẻ, `git clone` kéo về **toàn bộ** repo — mọi file và cả lịch sử commit. Sau đó bạn có một bản đầy đủ ở máy, sửa thoải mái, rồi đẩy (push) thay đổi trở lại bản trên mạng. Đây là bước đầu tiên khi tham gia một dự án có sẵn.",
                en: "Unlike downloading a single file, `git clone` pulls down the **entire** repo — every file plus the full commit history. You then have a complete copy locally, edit freely, and push changes back to the online copy. It's the first step when you join an existing project."
            ),
            diagram: DiagramSpec(.twoSides,
                [L10n(vi: "Repo trên mạng", en: "Remote repo"),
                 L10n(vi: "GitHub", en: "GitHub"),
                 L10n(vi: "Bản của bạn", en: "Your copy"),
                 L10n(vi: "ở máy bạn", en: "on your machine")],
                accent: .teal,
                caption: L10n(vi: "Kéo cả repo từ trên mạng về máy bạn.",
                              en: "Pull the whole repo from online down to your machine.")),
            codeExample: "git clone https://github.com/you/app.git",
            whenToUse: L10n(
                vi: "Khi **bắt đầu với một dự án đã có** — clone về rồi mới sửa.",
                en: "When **starting from an existing project** — clone it down, then work."
            ),
            tags: [], related: ["repository", "git", "branch"]
        ),

        .init(
            id: "command", topicId: "tools",
            title: L10n(vi: "Lệnh (Command)", en: "Command"),
            cardDefinition: L10n(
                vi: "Một **dòng chữ ra lệnh** bạn gõ vào terminal để máy làm một việc cụ thể.",
                en: "A typed **instruction** you give the computer in the terminal to do one specific thing."
            ),
            whatItReallyMeans: L10n(
                vi: "Mỗi lệnh thường gồm: tên lệnh + vài tùy chọn. `ls -la` nghĩa là *\"liệt kê file\"* (`ls`) *\"kèm chi tiết và cả file ẩn\"* (`-la`). Bạn gõ lệnh, nhấn Enter, máy chạy và in kết quả. Ghép nhiều lệnh lại là bạn đang tự động hoá công việc.",
                en: "A command is usually the command's name + a few options. `ls -la` means *\"list files\"* (`ls`) *\"with details and hidden ones\"* (`-la`). You type it, press Enter, and the computer runs it and prints the result. String commands together and you're automating work."
            ),
            diagram: DiagramSpec(.commandFlow,
                [L10n(vi: "ls -la", en: "ls -la"),
                 L10n(vi: "App.swift   README.md", en: "App.swift   README.md")],
                accent: .gold,
                caption: L10n(vi: "Gõ một lệnh, máy chạy và trả lại kết quả.",
                              en: "Type a command, the computer runs it and shows the result.")),
            codeExample: "ls -la         # list files, detailed\ngit status     # what changed?\nnpm install    # fetch dependencies",
            whenToUse: L10n(
                vi: "Mỗi khi bạn muốn máy làm một việc **nhanh, lặp lại được, hoặc viết thành kịch bản** — thay vì click.",
                en: "Whenever you want the computer to do something **fast, repeatable, or scriptable** — instead of clicking."
            ),
            tags: [], related: ["terminal", "package-manager", "git"]
        ),

        .init(
            id: "dependency", topicId: "tools",
            title: L10n(vi: "Thư viện phụ thuộc (Dependency)", en: "Dependency"),
            cardDefinition: L10n(
                vi: "**Code của người khác mà dự án bạn cần** để chạy — một thư viện bạn dựa vào.",
                en: "**Someone else's code your project needs** to run — a library you rely on."
            ),
            whatItReallyMeans: L10n(
                vi: "Thay vì tự viết mọi thứ, bạn dùng lại thư viện có sẵn (ví dụ React). Dự án của bạn *phụ thuộc* vào nó — thiếu là code không chạy. Trình quản lý gói ghi lại danh sách dependency và đúng phiên bản, để ai mở dự án cũng tải về y hệt. Quá nhiều dependency thì dự án nặng và khó bảo trì hơn.",
                en: "Instead of writing everything yourself, you reuse existing libraries (e.g. React). Your project *depends* on them — without them the code won't run. The package manager records the list of dependencies and their exact versions, so anyone who opens the project gets the same set. Too many dependencies makes a project heavier and harder to maintain."
            ),
            diagram: DiagramSpec(.twoSides,
                [L10n(vi: "Dự án của bạn", en: "Your project"),
                 L10n(vi: "cần →", en: "needs →"),
                 L10n(vi: "react", en: "react"),
                 L10n(vi: "một thư viện", en: "a library")],
                accent: .pink,
                caption: L10n(vi: "Dự án dựa vào code của người khác để chạy.",
                              en: "Your project leans on someone else's code to run.")),
            codeExample: "// package.json\n\"dependencies\": {\n  \"react\": \"^18.0.0\"\n}",
            whenToUse: L10n(
                vi: "Khi bạn **dùng lại công sức của người khác** thay vì viết lại — gần như mọi dự án thật đều có.",
                en: "When you **reuse others' work** instead of rewriting it — nearly every real project has them."
            ),
            tags: [.react, .nodeBackend], related: ["package-manager", "repository"]
        ),
    ]
}
