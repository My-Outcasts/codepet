# Codepet — PRD Định hình lại sản phẩm (v1)

**Ngày:** 2026-06-26
**Trạng thái:** Bản thiết kế chờ duyệt
**Bối cảnh:** App Codepet hiện tại (macOS, dạy code cho người mới bằng pixel-pet) không đáp ứng kỳ vọng của sếp. Tài liệu này định hình lại Codepet dựa trên phản hồi chiến lược của sếp.

---

## 0. Tin nhắn nguồn của sếp (giữ nguyên để đối chiếu)

> "Codepet phải mạnh hơn nữa mới có thể đi xa được, càng lâu thì càng mất lửa của sự kiện và những ai đã đến nghe."
> "Mình nên bỏ cái tư duy MVP đi. Ở VN không áp dụng được đâu."
> "Giá trị cốt lõi chưa rõ nét và đọc quá nhiều."
> "Anh làm AI code, có rất nhiều kinh nghiệm học được và mình phải thể hiện được nó: quản lý token, quản lý agent, chất lượng design và cách iterate, góc nhìn kinh doanh và xây thương hiệu, các skill khi set up như design review, khi brainstorm phải nghĩ start/during/end của một trải nghiệm, quan tâm test/eval để an toàn cho người dùng mỗi feature, cách document hiệu quả, track data thế nào để hiểu performance, collect feedback thế nào."
> "Codepet cần hiểu tất cả và làm sao cho dễ dàng nhất cho người điều khiển Claude Code có thể làm."
> "Codepet là sản phẩm rất tiềm năng và dễ thành công thương mại hơn nhiều — cơ hội rất lớn nếu làm đúng, vì tương lai ai cũng phải dùng AI nhưng không phải ai cũng biết làm hiệu quả nhất."

**Tín hiệu bổ sung (cách sếp tư duy mỗi ngày):** sếp liên tục đẻ ra các "flow tối ưu việc làm với AI" — ví dụ: auto health-check trên production; tester log bug vào Notion → Claude Code đọc → tự fix. Đây là minh họa cho *kiểu tư duy* của sếp (đòn bẩy, automation thực chiến), **không** phải danh sách feature v1.

---

## 1. North Star — Bộ lọc gu của sếp

Mọi quyết định sản phẩm (design, scope, copy, kỹ thuật) phải lọt qua 4 bộ lọc này. Nếu một feature không thỏa, cắt hoặc làm lại.

1. **Medium is the message.** Codepet dạy người ta build sản phẩm xuất sắc bằng AI → bản thân Codepet phải *là bằng chứng sống* của playbook đó. Cách ta làm ra Codepet chính là quảng cáo thuyết phục nhất cho Codepet.
2. **Đòn bẩy, không phải bài học.** Giá trị là AI **làm việc thật thay người dùng**, không phải kiến thức để đọc. Đo bằng "việc AI tự làm được", không phải "bài đã học".
3. **Sắc — ít chữ — có chính kiến.** Người dùng *làm theo nhịp*, không *đọc*. Nếu một màn hình bắt đọc nhiều → sai. (Đây là lỗi cốt tử của app cũ.)
4. **Mạnh nhưng kịp lửa.** Bỏ tư duy MVP mỏng; ra thứ đủ tin và đủ sắc. Nhưng đi theo nhịp tuần, không phải tháng — kẻo nguội lửa sự kiện.

---

## 2. Core value

> **Codepet biến Claude Code từ thứ-bạn-ngồi-gõ-lệnh → thành một đội tự động làm việc thật cho bạn, theo đúng playbook thực chiến của sếp.**

Khoảng trống thị trường: *tương lai ai cũng phải dùng AI, nhưng không phải ai cũng biết đấu dây AI vào quy trình thật để nó chạy thay mình.* Codepet đứng đúng vào khoảng trống đó.

**Chuyển hoá cốt lõi (chung cho mọi nhóm người dùng):**
Từ *"vọc AI cho ra cái chạy được"* → *"build/vận hành bằng AI như một người làm nghề thực thụ"* (có quy trình, kỷ luật token & agent, eval an toàn, data & feedback, có thương hiệu).

---

## 3. Người dùng

**Beachhead (mũi nhọn v1):** Người **mới** dùng Claude Code — biết dùng AI cơ bản nhưng làm lộn xộn: đốt token mù, không quy trình, không eval, không document.

**Tầm nhìn rộng:** ba nhóm cùng *một* chuyển hoá, chỉ khác điểm xuất phát:
- Nhóm 1 — người mới dùng Claude Code (beachhead).
- Nhóm 2 — non-dev muốn build sản phẩm bằng AI (câu chuyện thương mại mạnh nhất).
- Nhóm 3 — dev muốn lên pro (gần trải nghiệm sếp nhất).

**Cách hóa giải mâu thuẫn "play pro của sếp" vs "người mới":**
Đóng gói play pro của sếp sao cho **người mới cài-một-phát-là-chạy**, không cần hiểu dây bên trong. Người mới không tự nghĩ ra flow — họ cài Codepet và *bỗng nhiên có nó*. Hai nhóm còn lại "lớn dần vào trong" cùng một sản phẩm, chỉ khác độ sâu.

---

## 4. Kiến trúc sản phẩm

Hai mảnh + một cầu nối:

### 4.1 Plugin Claude Code — *nơi việc xảy ra*
Đóng gói playbook của sếp bằng đúng hệ mở rộng có sẵn của Claude Code:

| Điều sếp muốn | Cơ chế Claude Code |
|---|---|
| Quản lý token | Statusline (token realtime) + hooks cảnh báo |
| Quản lý agent | Subagents / Agent tool / workflows |
| Design review | Skill / slash command |
| Brainstorm start/during/end | Skill |
| Test / eval an toàn | Skill / command chạy trước khi ship |
| Document hiệu quả | Skill / command |
| Track data performance | Hooks log sự kiện ra analytics |
| Collect feedback | Slash command / hook |

→ Tất cả gói thành một **Claude Code plugin** (bundle skills + hooks + commands + agents + MCP + statusline). Cài một phát là dùng được.

### 4.2 App macOS (Codepet hiện tại, tái định nghĩa) — *dashboard đồng hành*
Việc build diễn ra trong Claude Code; app macOS là nơi nhìn bức tranh lớn xuyên các phiên:
- Con pet (linh hồn/thương hiệu) và trạng thái của nó.
- Lịch sử phiên làm việc.
- Xu hướng token / chi phí.
- "Đòn bẩy đã tạo" (việc AI tự làm, bug tự fix, thời gian tiết kiệm).
- Thành tựu, kỹ năng đã thành thạo.

### 4.3 Cầu nối
Hooks trong plugin **log sự kiện** → app macOS **đọc & hiển thị** (pet phản ứng, chỉ số cập nhật, thành tựu mở khóa). Cơ chế truyền dữ liệu cụ thể (file log cục bộ / Firestore / local IPC) sẽ chốt ở bước kế hoạch triển khai.

---

## 5. Xương sống trải nghiệm — Vòng START / DURING / END

Đúng lời sếp ("khi brainstorm phải nghĩ start/during/end"). Mỗi lần người dùng ngồi xuống build = một "trải nghiệm" 3 chặng. **Play là nội dung đổ vào vòng này.**

- **START** (trước khi gõ dòng đầu): brainstorm có cấu trúc (làm gì / cho ai / xong là gì) → plan → đặt ngân sách token. Pet "thức dậy" cùng mục tiêu phiên.
- **DURING** (trong lúc build): statusline token + pet phản ứng; nhắc gọi/điều phối agent đúng lúc; design-review checkpoint trước khi đi quá xa; giữ nhịp, chống lạc đề.
- **END** (trước khi gọi "xong"): eval an toàn cho feature vừa làm → sinh & chuẩn hóa document → log data + thu feedback → pet tổng kết phiên.
- Một số play (pro, về sau) chạy **nền tự động** — canh production, Notion→autofix — tạo đòn bẩy ngay cả khi người dùng ngủ.

---

## 6. Con pet — phải *kiếm được* chỗ đứng

Pet **không** phải Tamagotchi trang trí. Pet là **hiện thân của đòn bẩy**: khỏe/vui khi AI làm được nhiều việc thật cho bạn; lo lắng khi bạn đốt token vô ích. Nó là linh hồn & thương hiệu, nhưng tối giản tuyệt đối về chữ.

⚠️ **Rủi ro cần canh:** pet là chỗ dễ tái phạm lỗi "đọc quá nhiều". Nguyên tắc: pet *biểu cảm bằng trạng thái/hình ảnh/số liệu*, không bằng đoạn văn.

---

## 7. Phạm vi v1

**Triết lý scope:** Play là vô hạn và thuộc về sếp (mỗi ngày một cái mới). Vì vậy **không** scope v1 quanh vài play cụ thể. Thứ thật sự build ở v1 là **CỖ MÁY** biến play hằng ngày của sếp thành trải nghiệm cài-một-phát cho người mới.

### 7.1 Phải có (v1)
- **Engine + trải nghiệm:** vòng START/DURING/END + statusline token + pet/dashboard + khung plugin để play cắm vào.
- **3 play "mồi"** — suy ra từ nỗi đau người mới, chạy được ngày đầu (không cần production/Notion/team):

  1. **START — "Khởi động đúng" (Guided Kickoff).**
     *Đau:* prompt mơ hồ → AI đi lạc → mớ hỗn độn, tốn token.
     *Làm:* trước khi AI viết dòng nào, ép một nhịp ngắn (làm-gì / cho-ai / xong-là-gì → plan → ngân sách token). Pet thức dậy cùng mục tiêu.
     *Wow:* dự án đầu tiên chạy mượt thay vì loạn.

  2. **DURING — "Đồng hồ token sống" (Token Pet).**
     *Đau:* đốt token mù, không biết đang tiêu tiền, không có phanh.
     *Làm:* statusline token/chi phí realtime; pet phản ứng; gần chạm ngân sách thì cảnh báo + đề nghị nén context.
     *Wow:* lần đầu *nhìn thấy* tiền mình tiêu và cảm giác kiểm soát. (Chỗ pet kiếm được chỗ đứng.)

  3. **END — "Chốt an toàn" (Safe Close).**
     *Đau:* AI sửa code, người mới nhắm mắt nhận → vỡ build, không biết đúng/sai, không lưu vết.
     *Làm:* trước khi "xong", tự verify/eval + tổng kết phiên + sinh document phần đã đổi. Pet tổng kết: build gì, tốn bao nhiêu, an toàn chưa.
     *Wow:* tự tin, ít vỡ build, có dấu vết để học.

- **Dashboard macOS tối thiểu nhưng đẹp:** pet + lịch sử phiên + xu hướng token + đòn bẩy đã tạo.

### 7.2 Để sau (đường lớn dần)
- Thư viện play mở rộng — **mỗi ngày sếp đẻ play mới đổ vào** (Notion→autofix, auto health-check production… cho người dùng lên trình).
- Tính năng cho nhóm 2 (non-dev) và nhóm 3 (pro/team).
- Monetization (xem mục 9).

### 7.3 Không làm (YAGNI)
- Không bê nguyên app cũ "dạy code 16 skill / 7 nhân vật / hearts / coins" theo kiểu course. Giữ lại tài sản pixel-art & thương hiệu; bỏ mô hình "đọc bài học".

---

## 8. Đo lường thành công

- **Wow phút đầu:** cài → chạy được 1 play thật trong < 10 phút.
- **Đòn bẩy hiện hình:** số việc AI tự làm / token tiết kiệm / bug tự fix mỗi tuần.
- **Giữ chân:** số phiên/tuần, số play được cài.
- **Bằng chứng sống (North Star #1):** Codepet được build *bằng chính playbook của nó* — có log token, có eval, có document, có data.

---

## 9. Góc kinh doanh & thương hiệu (định hướng, chưa phải scope v1)

Sếp nhấn mạnh tiềm năng thương mại. Ghi nhận để không thiết kế chệch:
- Thư viện play là tài sản tăng dần theo ngày → lợi thế tích lũy, hợp mô hình subscription.
- Thương hiệu "Codepet" + con pet = mặt cảm xúc dễ lan, dễ marketing quanh sự kiện.
- Chi tiết pricing/positioning để ở vòng kế hoạch sau, không cản v1.

---

## 10. Áp lực thời gian

Đi nhanh — tinh thần **tuần, không phải tháng**. 3 play "mồi" chạy được trước; phần còn lại (thư viện, nhóm 2/3, monetization) xếp sau. Lý do: tránh nguội lửa sự kiện (lời sếp).

---

## 11. Câu hỏi mở / cần chốt ở bước kế hoạch

1. Cơ chế cầu nối dữ liệu plugin ↔ app macOS (file log cục bộ / Firestore / IPC)?
2. Môi trường Claude Code mục tiêu cho v1 (CLI/terminal trước, hay cả desktop/IDE)?
3. Đối chiếu 3 play "mồi" với sếp — sếp có muốn thay 1–2 play "tủ" cho người mới không?
4. Hình hài pixel-art mới của pet trong terminal (statusline) so với trong app macOS.
5. Số phận cụ thể của code app cũ: phần nào tái dùng cho dashboard, phần nào bỏ.
