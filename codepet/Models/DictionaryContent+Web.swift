import Foundation

extension DictionaryContent {

    static let webTerms: [DictionaryTerm] = [

        .init(
            id: "html", topicId: "web",
            title: L10n(vi: "HTML", en: "HTML"),
            cardDefinition: L10n(
                vi: "Ngôn ngữ mô tả **bộ khung** của một trang web — tiêu đề, đoạn văn, nút bấm.",
                en: "The language that lays out the **skeleton** of a web page — headings, paragraphs, buttons."
            ),
            whatItReallyMeans: L10n(
                vi: "HTML chỉ lo phần *cấu trúc*: cái này là tiêu đề lớn, cái kia là một đoạn văn, chỗ này là nút bấm. Chưa có màu, chưa có font đẹp, chưa có hiệu ứng — vẫn xem được, chỉ là trần trụi. Phần làm đẹp để CSS lo.",
                en: "HTML only handles *structure*: this is a big heading, that's a paragraph, here's a button. No colors, no nice fonts, no effects yet — still readable, just bare. The styling is CSS's job."
            ),
            diagram: DiagramSpec(.layers,
                [L10n(vi: "HTML · bộ khung", en: "HTML · structure"),
                 L10n(vi: "CSS · lớp sơn", en: "CSS · styling"),
                 L10n(vi: "bottom", en: "bottom")],
                accent: .orange,
                caption: L10n(vi: "HTML là lớp khung bên dưới — phần chữ và bố cục.",
                              en: "HTML is the structure layer underneath — content and layout.")),
            codeExample: "<h1>Hello</h1>\n<p>Welcome to my page.</p>\n<button>Click me</button>",
            whenToUse: L10n(
                vi: "Là **lớp nền của mọi trang web**. Bất cứ giao diện web nào cũng bắt đầu từ HTML.",
                en: "It's the **foundation of every web page**. Any web interface starts as HTML."
            ),
            tags: [.react], related: ["css", "frontend-backend", "component", "javascript"]
        ),

        .init(
            id: "css", topicId: "web",
            title: L10n(vi: "CSS", en: "CSS"),
            cardDefinition: L10n(
                vi: "Ngôn ngữ **làm đẹp** trang web — màu sắc, font chữ, khoảng cách, bố cục.",
                en: "The language that **styles** a web page — colors, fonts, spacing, layout."
            ),
            whatItReallyMeans: L10n(
                vi: "Nếu HTML là bộ khung nhà thì CSS là sơn, đèn và đồ nội thất. Cùng một khung HTML, đổi CSS là ra hai trang trông khác hẳn nhau. Cấu trúc giữ nguyên, vẻ ngoài thay đổi hoàn toàn.",
                en: "If HTML is the house's frame, CSS is the paint, lighting, and furniture. Same HTML frame, swap the CSS and you get two pages that look completely different. Structure stays, appearance flips."
            ),
            diagram: DiagramSpec(.layers,
                [L10n(vi: "HTML · bộ khung", en: "HTML · structure"),
                 L10n(vi: "CSS · lớp sơn", en: "CSS · styling"),
                 L10n(vi: "top", en: "top")],
                accent: .pink,
                caption: L10n(vi: "CSS là lớp phủ bên trên — màu sắc, font, vẻ ngoài.",
                              en: "CSS is the layer on top — colors, fonts, the look.")),
            codeExample: "h1 {\n    color: purple;\n    font-size: 32px;\n}",
            whenToUse: L10n(
                vi: "Mỗi khi bạn muốn một trang web **trông ra dáng** thay vì là chữ đen trên nền trắng.",
                en: "Any time you want a web page to **look designed** instead of black text on white."
            ),
            tags: [.react], related: ["html"]
        ),

        .init(
            id: "http", topicId: "web",
            title: L10n(vi: "HTTP", en: "HTTP"),
            cardDefinition: L10n(
                vi: "Bộ **quy tắc đưa thư** mà trình duyệt và máy chủ dùng để trao đổi trang web và dữ liệu.",
                en: "The **mail rules** browsers and servers use to swap web pages and data."
            ),
            whatItReallyMeans: L10n(
                vi: "Giống dịch vụ bưu chính của web. Trình duyệt gửi một *yêu cầu* — *\"cho tôi xin trang /home\"* — và máy chủ gửi lại một *câu trả lời* kèm trang đó và một mã trạng thái (`200 OK` nghĩa là ổn). Mở một trang là hàng chục lá thư bay qua lại trong vài giây.",
                en: "Like a postal service for the web. The browser sends a *request* — *\"could I have the /home page?\"* — and the server sends back a *response* with that page and a status code (`200 OK` means all good). Opening one page is dozens of letters flying back and forth in seconds."
            ),
            diagram: DiagramSpec(.requestResponse,
                [L10n(vi: "trình duyệt", en: "browser"),
                 L10n(vi: "GET /home", en: "GET /home"),
                 L10n(vi: "máy chủ", en: "server"),
                 L10n(vi: "200 OK", en: "200 OK")],
                accent: .blue,
                caption: L10n(vi: "Yêu cầu đi ra, câu trả lời đi về.",
                              en: "Request goes out, response comes back.")),
            codeExample: "GET /api/users/42 HTTP/1.1\nHost: example.com\n\n200 OK\n{ \"name\": \"Ada\" }",
            whenToUse: L10n(
                vi: "Là cách **mọi thứ trên web nói chuyện với nhau**. Hiểu nó giúp bạn gỡ lỗi mạng dễ hơn.",
                en: "It's how **everything on the web talks**. Understanding it makes network bugs far easier to debug."
            ),
            tags: [.nodeBackend, .api], related: ["api", "json"]
        ),

        .init(
            id: "api", topicId: "web",
            title: L10n(vi: "API", en: "API"),
            cardDefinition: L10n(
                vi: "Một **cách định sẵn** để chương trình này xin dữ liệu (hoặc nhờ làm việc) từ chương trình kia.",
                en: "A **defined way** for one program to ask another for data (or to do a job)."
            ),
            whatItReallyMeans: L10n(
                vi: "Một chương trình mở ra vài \"điểm gọi\" cố định, ví dụ `getWeather`. Bạn gửi yêu cầu tới đúng điểm đó và nhận lại dữ liệu theo khuôn đã thỏa thuận — còn ruột bên trong nó vẫn đóng kín. API là bản hợp đồng: gọi thế nào, nhận lại gì.",
                en: "A program exposes a few fixed \"call points\", say `getWeather`. You send a request to exactly that point and get back data in an agreed shape — while its insides stay sealed off. An API is the contract: how to call, what you get back."
            ),
            diagram: DiagramSpec(.requestResponse,
                [L10n(vi: "app của bạn", en: "your app"),
                 L10n(vi: "getWeather", en: "getWeather"),
                 L10n(vi: "API thời tiết", en: "Weather API"),
                 L10n(vi: "{ temp: 31 }", en: "{ temp: 31 }")],
                accent: .blue),
            codeExample: "GET https://api.weather.com/today?city=Hanoi\n→ { \"temp\": 31, \"sky\": \"clear\" }",
            whenToUse: L10n(
                vi: "Bất cứ khi nào **hai chương trình cần nói chuyện** — app của bạn gọi một dịch vụ bên ngoài.",
                en: "Whenever **two programs need to talk** — your app calling an outside service."
            ),
            tags: [.api, .nodeBackend], related: ["http", "json"]
        ),

        .init(
            id: "json", topicId: "web",
            title: L10n(vi: "JSON", en: "JSON"),
            cardDefinition: L10n(
                vi: "Một **định dạng chữ đơn giản** để ghi dữ liệu có cấu trúc — dùng khắp nơi trên web.",
                en: "A **simple text format** for structured data — used everywhere on the web."
            ),
            whatItReallyMeans: L10n(
                vi: "JSON viết dữ liệu thành các cặp *tên: giá trị*, dễ đọc với cả người lẫn máy: `{ \"name\": \"Ada\", \"age\": 36 }`. Có thể lồng nhau. Gần như mọi ngôn ngữ lập trình đều đọc/ghi được JSON sẵn, nên nó là cách phổ biến nhất để gửi dữ liệu giữa app và máy chủ.",
                en: "JSON writes data as *name: value* pairs that both people and machines read easily: `{ \"name\": \"Ada\", \"age\": 36 }`. It can nest. Nearly every programming language reads and writes JSON out of the box, so it's the most common way to send data between an app and a server."
            ),
            diagram: DiagramSpec(.keyValue,
                [L10n(vi: "name: \"Ada\"", en: "name: \"Ada\""),
                 L10n(vi: "age: 36", en: "age: 36"),
                 L10n(vi: "skills: [ … ]", en: "skills: [ … ]")],
                accent: .blue,
                caption: L10n(vi: "Dữ liệu viết thành cặp tên: giá trị — người và máy đều đọc được.",
                              en: "Data written as name: value pairs — both people and machines read it.")),
            codeExample: "{\n  \"name\": \"Ada\",\n  \"age\": 36,\n  \"skills\": [\"math\", \"coding\"]\n}",
            whenToUse: L10n(
                vi: "Cho **hầu hết dữ liệu** trao đổi giữa app và máy chủ. Người đọc được, máy hiểu được.",
                en: "For **most data** exchanged between app and server. Humans read it, machines parse it."
            ),
            tags: [.api, .nodeBackend], related: ["api", "http"]
        ),

        .init(
            id: "frontend-backend", topicId: "web",
            title: L10n(vi: "Frontend vs Backend", en: "Frontend vs Backend"),
            cardDefinition: L10n(
                vi: "**Frontend** là phần người dùng nhìn và bấm. **Backend** là phần chạy ngầm trên máy chủ, lo dữ liệu.",
                en: "**Frontend** is what users see and click. **Backend** is what runs behind the scenes on a server, handling data."
            ),
            whatItReallyMeans: L10n(
                vi: "Frontend là mặt tiền: nút bấm, màu sắc, bố cục — thứ bạn chạm vào. Backend là hậu trường: kiểm tra mật khẩu, lưu dữ liệu, tính toán — thứ không ai thấy nhưng nếu hỏng thì cả app đứng. Bạn bấm `Đăng nhập` (frontend) → nó nhờ backend kiểm tra → backend trả lời đúng/sai.",
                en: "Frontend is the storefront: buttons, colors, layout — what you touch. Backend is backstage: checking passwords, saving data, doing the math — unseen, but if it breaks the whole app freezes. You click `Login` (frontend) → it asks the backend to check → the backend answers yes/no."
            ),
            diagram: DiagramSpec(.twoSides,
                [L10n(vi: "Frontend", en: "Frontend"),
                 L10n(vi: "nút, màu, bố cục", en: "buttons, colors, layout"),
                 L10n(vi: "Backend", en: "Backend"),
                 L10n(vi: "dữ liệu, kiểm tra", en: "data, checks")],
                accent: .pink,
                caption: L10n(vi: "Mặt tiền bạn chạm vào ↔ hậu trường chạy ngầm.",
                              en: "The storefront you touch ↔ the backstage running hidden.")),
            codeExample: nil,
            whenToUse: L10n(
                vi: "Là khung tư duy hữu ích trên **mọi dự án web**. Ranh giới rõ giúp nhiều người làm song song mà không đạp lên nhau.",
                en: "A useful mental model on **any web project**. Clear boundaries let people work in parallel without stepping on each other."
            ),
            tags: [.react, .nodeBackend], related: ["html", "api", "component"]
        ),

        .init(
            id: "component", topicId: "web",
            title: L10n(vi: "Component", en: "Component"),
            cardDefinition: L10n(
                vi: "Một **mảnh giao diện đóng gói sẵn** bạn dùng lại nhiều lần — và lồng vào nhau để dựng cả trang.",
                en: "A **self-contained piece of UI** you reuse — and nest inside each other to build a whole page."
            ),
            whatItReallyMeans: L10n(
                vi: "Thay vì viết cả trang thành một khối khổng lồ, bạn cắt nó thành các mảnh có tên: một `Button`, một `Card`, một `Header`. Mỗi mảnh lo phần của mình và có thể chứa mảnh nhỏ hơn. Sửa `Button` một lần, mọi nơi dùng nó đều đổi theo. Đó là cách chơi Lego của giao diện.",
                en: "Instead of writing a page as one giant blob, you cut it into named pieces: a `Button`, a `Card`, a `Header`. Each piece minds its own part and can hold smaller pieces inside it. Fix the `Button` once and every place that uses it updates. It's the Lego approach to UI."
            ),
            diagram: DiagramSpec(.labeledBox,
                [L10n(vi: "Card", en: "Card"), L10n(vi: "🧩 UI", en: "🧩 UI")],
                accent: .pink,
                caption: L10n(vi: "Một mảnh UI có tên — dựng một lần, dùng nhiều nơi, lồng được vào nhau.",
                              en: "A named piece of UI — build once, use everywhere, nest them together.")),
            codeExample: "function Card({ title }) {\n  return <div className=\"card\">{title}</div>\n}\n// reuse it: <Card title=\"Hello\" />",
            whenToUse: L10n(
                vi: "Trên **mọi giao diện hiện đại** (React, SwiftUI, Vue). Cắt UI thành mảnh nhỏ có tên rồi ghép lại.",
                en: "On **any modern UI** (React, SwiftUI, Vue). Cut the UI into small named pieces and compose them."
            ),
            tags: [.react], related: ["html", "state", "frontend-backend"]
        ),

        .init(
            id: "state", topicId: "web",
            title: L10n(vi: "Trạng thái (State)", en: "State"),
            cardDefinition: L10n(
                vi: "Dữ liệu **mà giao diện đang theo dõi** — đổi nó, màn hình tự vẽ lại để khớp.",
                en: "The data the **UI is watching** — change it, and the screen redraws itself to match."
            ),
            whatItReallyMeans: L10n(
                vi: "State là *tình hình hiện tại*: đang ở tab nào, giỏ hàng có mấy món, đèn bật hay tắt. Điểm hay: bạn không tự đi sửa màn hình — bạn chỉ đổi state, và khung giao diện **tự cập nhật** theo. Như chỉnh số trên điều khiển điều hòa: bạn đổi con số, máy tự điều chỉnh.",
                en: "State is the *current situation*: which tab you're on, how many items in the cart, light on or off. The magic: you don't update the screen yourself — you just change the state, and the UI framework **re-renders** to match. Like a thermostat: you change the number, the system adjusts itself."
            ),
            diagram: DiagramSpec(.labeledBox,
                [L10n(vi: "count", en: "count"), L10n(vi: "3", en: "3")],
                accent: .purple,
                caption: L10n(vi: "Đổi giá trị → giao diện tự vẽ lại.",
                              en: "Change the value → the UI redraws itself.")),
            codeExample: "const [count, setCount] = useState(0)\n// setCount(count + 1) → the UI updates",
            whenToUse: L10n(
                vi: "Cho **bất cứ gì trên màn hình sẽ thay đổi** khi người dùng tương tác — bộ đếm, ô nhập, công tắc bật/tắt.",
                en: "For **anything on screen that changes** as the user interacts — counters, inputs, toggles."
            ),
            tags: [.react], related: ["variable", "component", "boolean"]
        ),

        .init(
            id: "javascript", topicId: "web",
            title: L10n(vi: "JavaScript", en: "JavaScript"),
            cardDefinition: L10n(
                vi: "Ngôn ngữ làm cho trang web **biết phản hồi** — bấm, gõ, cập nhật mà không tải lại trang.",
                en: "The language that makes web pages **interactive** — clicking, typing, and updating without reloading."
            ),
            whatItReallyMeans: L10n(
                vi: "HTML dựng khung, CSS làm đẹp, còn JavaScript (JS) lo **hành vi**: bấm nút thì có chuyện gì xảy ra, dữ liệu mới hiện lên thế nào. Ban đầu JS chỉ chạy trong trình duyệt, nay chạy cả ở máy chủ (Node). File JS có đuôi `.js` (hoặc `.jsx` khi dùng React).",
                en: "HTML builds the structure, CSS styles it, and JavaScript (JS) handles **behavior**: what happens when you click a button, how new data appears. It started in the browser but now also runs on servers (Node). JS files end in `.js` (or `.jsx` with React)."
            ),
            diagram: nil,
            codeExample: "button.onclick = () => {\n  alert(\"Hi!\")\n}",
            whenToUse: L10n(
                vi: "Cho **mọi phần tương tác** trên web — và ngày càng nhiều ở phía máy chủ.",
                en: "For **any interactivity** on the web — and increasingly on the server too."
            ),
            tags: [.react, .nodeBackend], related: ["html", "css", "typescript"]
        ),

        .init(
            id: "typescript", topicId: "web",
            title: L10n(vi: "TypeScript", en: "TypeScript"),
            cardDefinition: L10n(
                vi: "**JavaScript có dán nhãn kiểu** — bắt lỗi trước khi chạy bằng cách kiểm tra kiểu dữ liệu.",
                en: "**JavaScript with type labels** — it catches mistakes before you run by checking data types."
            ),
            whatItReallyMeans: L10n(
                vi: "TypeScript (TS) là JavaScript cộng phần khai báo kiểu: bạn nói `name` là chuỗi, `age` là số. Trước khi chạy, TS soát xem bạn có dùng sai kiểu ở đâu không, nhờ đó bắt được nhiều lỗi ngớ ngẩn sớm. Cuối cùng TS biên dịch trở lại thành JavaScript thường để trình duyệt chạy. File TS có đuôi `.ts` (hoặc `.tsx` với React).",
                en: "TypeScript (TS) is JavaScript plus type declarations: you say `name` is a string, `age` is a number. Before running, TS checks whether you've used a type wrong anywhere, catching many silly mistakes early. In the end TS compiles back to plain JavaScript for the browser to run. TS files end in `.ts` (or `.tsx` with React)."
            ),
            diagram: nil,
            codeExample: "function greet(name: string): string {\n  return \"Hi, \" + name\n}",
            whenToUse: L10n(
                vi: "Trên **dự án lớn hơn** nơi việc bắt lỗi kiểu sớm tiết kiệm nhiều thời gian gỡ lỗi.",
                en: "On **larger projects** where catching type mistakes early saves a lot of debugging time."
            ),
            tags: [.react], related: ["javascript", "html"]
        ),
    ]
}
