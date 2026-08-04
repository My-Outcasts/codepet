# Virtual Company — Test Runbook

Quy trình test hệ multi-agent, từ rẻ nhất đến đắt nhất. Chạy theo thứ tự tầng: nếu tầng dưới đỏ thì đừng đốt tiền API ở tầng trên.

| Tầng | Chạy gì | Cần API key | Chi phí | Khi nào chạy |
|---|---|---|---|---|
| 0 | `npm test` (unit, fake caller) | không | $0 | mỗi lần sửa code |
| 1 | `npm run verify:company` (fixture cố định, pass/fail) | có | ~$0.10–0.30 | trước khi deploy |
| 2 | `npm run try:company` (câu hỏi thật, đọc bằng mắt) | có | ~$0.10–0.30/run | khi đánh giá *chất lượng* agent |
| 3 | curl endpoint SSE | có + Firebase ID token | như tầng 2 | trước khi giao cho FE |

---

## Tầng 0 — Logic (miễn phí, không gọi model)

```bash
cd functions
npx jest company            # 13 suite, 196 test
npx jest                    # toàn bộ backend
```

Tầng này khoá được: conflict detection (thuần code), budget ceiling, kill switch,
blackboard, schema validation, thứ tự event SSE. **Nếu một hành vi có thể test ở
tầng 0 thì đừng test nó bằng tiền API.**

Baseline hiện tại: 13/13 suite pass, 196/196 test pass (~4s).

---

## Tầng 1 — Staging verification (pass/fail nghiêm ngặt)

```bash
cd functions
ANTHROPIC_API_KEY=sk-... npm run verify:company
```

Chứng minh 3 thứ mà fake không chứng minh được:

1. **Prompt cache thật sự bật** — `cache_read_input_tokens > 0` ở call thứ 2 trở đi.
   Fail ở đây = shared prefix không byte-identical (thường do role prompt lọt vào
   block 0 của `composeAgentSystem`) hoặc prefix tụt dưới cache floor.
2. **Model luôn gọi forced tool** — không có call nào trả text tự do.
3. **Chain 5 phase ra được brief dùng được**, kèm chi phí đo thật.

Exit code:

| Code | Nghĩa |
|---|---|
| 0 | PASS |
| 1 | FAIL — đọc dòng `FAIL:` |
| 2 | INCONCLUSIVE — router chọn escape hatch nên phase 2–5 bị skip, chưa kiểm được cache. **Không phải bug.** |

---

## Tầng 2 — Feel test (đánh giá chất lượng, đọc bằng mắt)

### Setup context thật một lần

Output nhạt hay sắc phụ thuộc gần như hoàn toàn vào founder context. Tạo file
(đừng commit, đây là số thật):

```bash
cd functions
cat > my-founder.json <<'JSON'
{
  "profile": "Solo founder, technical. Tự build được sản phẩm, không có background design/sales. Đã ship 1 sản phẩm trước đó.",
  "stage": "Codepet chưa launch, đang chuẩn bị TestFlight + App Store. Chưa có doanh thu, chưa có pricing page.",
  "constraints": [
    "Không thuê người quý này.",
    "Phải ship App Store trong tháng này.",
    "UI do người khác làm — mình chỉ làm logic + backend."
  ],
  "language": "vi"
}
JSON
```

### Chạy

```bash
ANTHROPIC_API_KEY=sk-... npm run try:company -- --founder ./my-founder.json "câu hỏi thật"
ANTHROPIC_API_KEY=sk-... npm run try:company -- --founder ./my-founder.json --stress "câu hỏi thật"
```

### Bộ 6 case — mỗi case ép một nhánh khác nhau

| # | Câu hỏi | Nhánh cần thấy |
|---|---|---|
| 1 | "Codepet nên free-with-ads hay one-time $9.99 khi launch, biết tôi chỉ còn 1 tháng?" | `multi_agent` → có conflict → negotiation → brief |
| 2 | "Đặt tên tab thứ 4 là Insights hay Progress?" | `single_agent` — escape hatch, KHÔNG spin 4 agent |
| 3 | "Tôi nên làm gì tiếp theo?" | `needs_clarification` + `missing_info` có nội dung |
| 4 | "Nên cắt Compendium khỏi MVP để ship kịp App Store không?" | 2 dept có thể ALIGNED → conflicts toàn ALIGNED, **không có** negotiation_round, brief vẫn ra |
| 5 | Case 4 + `--stress` | red team chạy dù đã đồng thuận |
| 6 | "Nên bỏ 3 tuần build web version trước khi launch macOS app?" | có `hard_blocker` (constraint "ship trong tháng này"), có thể ra `unresolved` |

### Rubric — output tốt vs slop

Đọc và tick. Dưới 5/7 là prompt có vấn đề, không phải "model hôm nay hơi kém".

- [ ] `real_question` **khác** câu hỏi gốc — nó reframe được, không chỉ nhại lại
- [ ] 2 dept khác nhau về **nội dung**, không chỉ khác giọng điệu
- [ ] Mỗi dept nói được `cost_to_my_dept` cụ thể (đánh đổi thật, không phải "cần thêm effort")
- [ ] `conflicts` phản ánh đúng thứ 2 position vừa nói — không phải conflict bịa
- [ ] `tradeoff_founder_must_own` là một quyết định **chỉ founder quyết được**, không phải chi tiết kỹ thuật
- [ ] `kill_criteria` có **số đo được** ("dưới 20 người trả tiền sau 2 tuần"), không phải "nếu không hiệu quả"
- [ ] `next_action` làm được trong tuần này

Cờ đỏ (thấy là dừng, sửa prompt):
- confidence toàn 5/5 → agent không biết mình đang đoán
- mọi dept đều đồng ý ở case 1 → false consensus, `devils_advocate` trigger đang hỏng
- brief lặp lại câu hỏi thay vì trả lời
- `what_we_dont_know` để trống

### Ghi lại

Mỗi run lưu output + chi phí (script đã in `N model calls · $X · cache tokens`).
So sánh giữa các lần sửa prompt — không có baseline thì không biết prompt mới tốt hơn hay chỉ khác.

---

## Tầng 3 — Endpoint SSE (biên giao cho FE)

Hợp đồng: `docs/superpowers/specs/virtual-company-sse-contract.md` — test theo doc đó, không theo source.

### Lấy ID token

`scripts/get-id-token.ts` mint token thật từ Identity Toolkit REST. Web API key tự
đọc từ `GoogleService-Info.plist` nên không cần config gì. Chỉ token ra stdout,
mọi thứ khác ra stderr → capture được bằng `$(...)`.

```bash
cd functions
ID_TOKEN=$(npm run -s token -- --email you@murror.app --password 'pw')   # tài khoản có sẵn
ID_TOKEN=$(npm run -s token)                                            # anonymous
npm run -s token -- --json                                              # kèm uid + expiresIn
npm run -s token -- --email qa@murror.app --password 'pw' --signup      # tạo user QA riêng
```

Lưu ý:
- **Anonymous sign-in đang TẮT trên `devpet-8f4b1`** → `npm run -s token` không có
  flag sẽ fail với `ADMIN_ONLY_OPERATION`. Hoặc bật ở Firebase console →
  Authentication → Sign-in method, hoặc dùng `--email/--password`.
- Token sống **1 giờ**, là credential thật của project — đừng paste vào ticket/commit.
- Script gọi API thật, **không chạy được với auth emulator**.
- Mỗi lần anonymous sign-in tạo một uid mới → rate limit (`100k/uid/ngày`) reset theo uid,
  đừng dùng anonymous để test riêng 429.

### Chạy stream

```bash
curl -N -X POST https://us-central1-devpet-8f4b1.cloudfunctions.net/virtualCompanyRun \
  -H "Authorization: Bearer $ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"request":"...","language":"vi","founder":{"profile":"...","stage":"...","constraints":[]},"stress_test":false}'
```

Checklist:

- [ ] `run_started` luôn đến trước
- [ ] `routing` đến ngay (FE render làm content, không phải spinner)
- [ ] Tất cả `agent_start` đến **trước** mọi `agent_position`
- [ ] `agent_position` đến theo thứ tự hoàn thành, không theo thứ tự request
- [ ] `telemetry` có `cost_estimate_usd`
- [ ] `done` luôn là frame cuối khi thành công
- [ ] Escape hatch: chỉ `run_started → routing → telemetry → done` với `skipped` được set

Lỗi trả JSON, **không mở stream** — test từng cái:

| Test | Cách ép | Mong đợi |
|---|---|---|
| Sai method | `curl -X GET` | 405 `method_not_allowed` |
| Không token | bỏ header Authorization | 401 `invalid_token` |
| Payload thiếu field | bỏ `founder.stage` | 400 `invalid_payload` + `detail` chỉ đúng field |
| Kill switch | set Firestore `config/virtual_company` → `{enabled: false}` | 503 `feature_disabled`. **Nhớ set lại `true` sau khi test** |
| Budget ceiling | không ép được bằng câu hỏi thật (ceiling 200k tok / $1.50) | đã cover ở tầng 0 (`companyBudget.test.ts`); nếu muốn thấy `run_stopped` thật thì hạ tạm `MAX_RUN_COST_USD` xuống `0.01` |

Ghi chú: kill switch **default = enabled** khi doc không tồn tại hoặc đọc lỗi — một Firestore blip không được làm sập feature. Rate limit `DAILY_LIMIT = 100_000/uid/ngày`, thực tế không chặn khi test tay.

---

---

## Chạy real — thứ tự cụ thể

### Chuẩn bị key một lần

Dùng `functions/local.env` (đã gitignore). Các script không tự đọc nó, nên source thủ công:

```bash
cd functions
echo 'ANTHROPIC_API_KEY=sk-ant-...' > local.env   # một lần
set -a; . ./local.env; set +a                     # mỗi shell mới
```

**Đừng đặt tên file là `.env`.** `firebase deploy` tự nạp mọi file `.env*` trong
`functions/` thành env var **thường**, rồi đụng với khai báo `secrets:
["ANTHROPIC_API_KEY"]` của `onRequest` và deploy chết ngay:

```
HTTP 400: Secret environment variable overlaps non secret
          environment variable: ANTHROPIC_API_KEY
```

Đã dính đúng lỗi này một lần khi deploy `virtualCompanyRun` (2026-08-03).

### Chi phí thật cần biết trước

Model tiering: intake = Haiku 4.5, department agents = Sonnet 5, red team + synthesis = Opus 5.

| Loại run | Số model call | Chi phí ước |
|---|---|---|
| Escape hatch (case 2, 3) | 1 (Haiku) | < $0.01 |
| Full multi_agent (case 1) | 6–8 | ~$0.15–0.30 |
| Cả 6 case tầng 2 | ~25 | ~$1 |
| Tầng 1 verify | 6–8 | ~$0.20 |

Ceiling cứng mỗi run: 200k token / $1.50 — vượt là `run_stopped`, không cắt im lặng.

### Thứ tự chạy

```bash
cd functions
set -a; . ./local.env; set +a

npx jest company                                          # 1. tầng 0, free
npm run verify:company                                     # 2. tầng 1, pass/fail
npm run try:company -- --founder ./my-founder.json "..."   # 3. tầng 2, 6 case
npm run try:company -- --founder ./my-founder.json --stress "..."
```

Sửa `my-founder.json` trước khi chạy tầng 2 — file đang có mấy chỗ `TODO:` (runway,
số beta user, constraint tài chính). Để nguyên `TODO` thì agent sẽ đoán, và bạn sẽ
đánh giá sai chất lượng của nó.

### Tầng 3 — endpoint đã deploy (2026-08-03)

`virtualCompanyRun` đã live tại `us-central1`, xác minh bằng curl: POST không token
→ 401, GET → 405. Secret `ANTHROPIC_API_KEY` có sẵn trong project (v4 ENABLED).

Deploy lại thì dùng **deploy có filter**, đừng deploy cả codebase trừ khi cố ý:

```bash
npx firebase deploy --only functions:virtualCompanyRun --project devpet-8f4b1
```

Filter tránh việc ship kèm thay đổi prompt sang các function khác đang chạy.

---

## Kết quả run thật đầu tiên (2026-08-03)

`npm run verify:company` — **FAIL**. Phase 1→4 chạy đúng, chết ở phase 5. Chi phí ~$0.19.

Phần chạy đúng: intake reframe được câu hỏi (PMF thay vì pricing), chọn đúng
product + finance, 2 dept trả lời độc lập, conflict detection bắt `BLOCKER` thật,
negotiation hội tụ trong 1 round, red team đúng là không trigger (2 dept cùng hướng).

### Bug 1 — synthesis reject brief của chính mình (deterministic)

```
Error: unusable decision brief from chief_of_staff:
  kill_criteria requires at least one observable event
```

Đo bằng `scripts/diag-synthesis.ts` (3/3 run, không flaky): Opus trả `kill_criteria`
là **string**, không phải array. Nội dung hoàn toàn dùng được ("Zero of 30 beta users
complete a purchase within 14 days…"). Validator ở `synthesis.ts:96` filter phần tử
non-string → array rỗng → reject cả brief.

Hậu quả: mọi full multi_agent run đều chết ở bước đắt nhất (Opus, ~$0.07) sau khi đã
trả tiền cho 7 call trước đó. Fix là coerce `string → [string]`.

### Bug 2 — cache write nhưng không bao giờ read

Đo bằng `scripts/diag-cache.ts`, 3 call tuần tự cùng prefix:

| Probe | cache_write | cache_read |
|---|---|---|
| A product / position tool | 2305 | 0 |
| B finance / position tool | 0 | **2305** |
| C product / negotiation tool | 2117 | 0 |

Kết luận: **caching không hỏng** — A→B reuse 100%, shared prefix byte-identical giữa
các agent. Nhưng trong run thật `cache_read = 0` ở **mọi** call, vì:

1. Tool definition nằm **trước** system trong cache prefix → mỗi phase dùng tool khác
   nhau (`submit_position` / `submit_negotiation_turn` / synthesis) là một cache entry
   khác → không reuse được qua phase. Probe C chứng minh: block0 giống hệt nhau
   (`true`) mà vẫn write mới.
2. Phase 2 và phase 4 đều `Promise.allSettled` → các agent trong cùng phase chạy song
   song, entry chưa readable → tất cả đều write.

Nên trong một run 8 call, **không có một cơ hội read nào**. Hiện tại caching đang
*tốn thêm* tiền: mỗi write bị tính 1.25× input mà không thu lại gì.

Kéo theo 2 vấn đề nữa:
- `verify:company` assert `sawCacheRead` → **không thể pass** với kiến trúc hiện tại,
  bất kể code đúng hay sai. Gate tầng 1 hỏng theo thiết kế.
- Message FAIL của nó ("prefix không byte-identical / role prompt lọt vào block 0") sẽ
  **chẩn đoán sai** — đã đo, block0 giống hệt nhau.
- `priceOf()` trong cả 2 script bỏ qua `cache_creation_input_tokens` → báo chi phí
  thấp hơn thực tế.

### Bug 1 — ĐÃ FIX

`parseBriefToolInput` giờ đọc một string trần thành list 1 phần tử
(`synthesis.ts:96`), schema description nói rõ "Always an array". 2 test mới ở
`companySynthesis.test.ts`. Verify bằng call thật: Opus vẫn trả string, giờ parse OK.

### Bug 2 — ĐÃ FIX (fix cách đo, không fix cache)

Không đổi kiến trúc cache — đổi cách verify:
- Thêm **cache reuse probe** ở đầu `verify:company`: 2 call tuần tự, cùng tool, khác
  agent → assert call thứ 2 phải read. Đây là điều kiện *đo được*, và vẫn bắt đúng lỗi
  mà message FAIL cũ nói (role prompt lọt vào block 0).
- Assertion `sawCacheRead` trên cả run bị bỏ, còn lại là số liệu tham khảo.
- `priceOf()` ở cả 2 script giờ tính `cache_creation` ở 1.25× → chi phí báo đúng.

Phụ phẩm: probe warm sẵn prefix của position tool nên phase 2 đọc được cache thật
(11,667 token trong run PASS). Không phải mục tiêu, nhưng là tiền tiết kiệm thật.

### Bug 3 — agent rơi khỏi run vì thiếu field `stance` (~33%) — ĐÃ FIX

Case 1 tầng 2: `FINANCE ── failed: unknown stance: undefined` → run tụt xuống 1
department, **mất hết conflict + negotiation + red team**, tức là mất đúng phần giá
trị của feature. Brief vẫn ra và trung thực nói "only one department reported".

Đo bằng `scripts/diag-finance.ts`, 3 call thật:

| Run | stop_reason | out tokens | Kết quả |
|---|---|---|---|
| 1 | `tool_use` | 1079 | **FAIL** — thiếu cả `stance` và `evidence_needed` |
| 2 | `tool_use` | 1115 | OK |
| 3 | `tool_use` | 929 | OK |

`stop_reason = tool_use`, **không phải truncation** — Sonnet đơn giản là bỏ field
`stance` dù nó nằm trong `required` của schema. Tool input schema là hint, không phải
ràng buộc cứng.

Hậu quả xác suất: ~33%/agent → run 2 department có **~55% khả năng bị mất ít nhất một
bên**. Không có retry ở đâu trong `src/company/` (`grep retry\|attempt` → rỗng).

Fix: `runIndependentPass` retry đúng 1 lần khi parse fail, quote lại lý do reject vào
prompt, cộng usage của cả 2 call (cả 2 đều bị bill). 4 test mới.

**Đã thấy retry chạy thật** trong run PASS: phase 2 có 3 call cho 2 agent —
`product(in=786)` fail, `product(in=835)` retry thành công.

### Còn mở — conflict detection báo BLOCKER giả

Trong run PASS, synthesis tự nhận xét: *"the flagged BLOCKER is a routing artifact:
both filed hard blockers saying the same thing"*. `detectConflicts` gắn `BLOCKER` khi
một bên có `hard_blocker`, không kiểm hai blocker có **cùng hướng** hay không. Hệ quả:
negotiation chạy (2 call Sonnet) cho một tranh luận không tồn tại.

Chưa fix — cần quyết định: so sánh hướng blocker bằng code (khó, là văn bản tự do) hay
để nguyên và chấp nhận chi phí. Brief hiện xử lý trung thực nên đây là vấn đề chi phí,
không phải vấn đề tính đúng đắn.

---

## Tầng 3 — PASS end-to-end (2026-08-03)

Stream thật trên endpoint đã deploy, câu hỏi tiếng Việt:

```
run_started → routing → agent_start ×2 → agent_position ×2 → conflicts
            → brief → telemetry → done
```

| Hạng mục | Kết quả |
|---|---|
| `run_started` đầu tiên, `done` cuối cùng | ✓ |
| Mọi `agent_start` trước mọi `agent_position` | ✓ |
| `agent_meta` | ✓ `product→product`, `finance→fin` |
| `conflicts` toàn `ALIGNED` → **không** có `negotiation_round` | ✓ đúng contract |
| `telemetry.tokens_per_agent` + `cost_estimate_usd` | ✓ |
| `done.skipped = null` khi chạy đủ phase | ✓ |
| Brief đủ 9 field, `next_action.owner = "Founder"` | ✓ |
| 4 mã lỗi JSON (400 ×4, 401, 405) | ✓ |
| Escape hatch (`single_agent`, `needs_clarification`) | ✓ đã test ở tầng 2 |

Brief tiếng Việt ra số thật: *"ads cần ~500k impressions/tháng để ra $1,000 (eCPM $2), bất khả thi với 30 user"*.

### Bài học đắt nhất: `max_tokens` không phải hằng số dùng chung

`stop_reason=max_tokens` với `output_tokens` đúng bằng 2000 → JSON của tool bị cắt
giữa object, và field ở cuối biến mất. Ở parse site nó **giống hệt** lỗi model phớt
schema, nên dễ đi sửa sai chỗ.

Brief tiếng Việt cần **2000–2600** output token. Tiếng Anh vừa 2000 nên fixture tầng 1
pass hàng tuần trong khi đường `vi` chết. Giờ `max_tokens` khai theo từng phase
(`BRIEF_MAX_TOKENS = 4000`), và `stopReason` được trả về cùng kết quả để lỗi tự khai
là truncation.

Khi thiếu field: **patch đúng field đó**, đừng sinh lại cả brief. Sinh lại tái tạo
đúng điều kiện gây lỗi. Đo trên cùng một câu hỏi: **6/10 → 7/8 (1 patch) → 8/8 (2 patch)**.

---

## Trạng thái đã verify

| Thứ | Trạng thái |
|---|---|
| Tầng 0 — `npx jest` (toàn backend) | 28/28 suite, **417/417** test pass |
| Tầng 1 — `verify:company` | **PASS** — 9 call, $0.1959, probe reuse OK, retry hoạt động thật |
| Tầng 2 case 1 — full multi_agent | brief ra được, nhưng gặp bug 3 → chỉ 1 department. 4 call, $0.0936 |
| Tầng 2 case 2 — one-dimensional | **PASS** — `single_agent`, 1 call, $0.0046 |
| Tầng 2 case 3 — vague | **PASS** — `needs_clarification` + 5 câu hỏi cụ thể, 1 call, $0.0044 |
| Tầng 2 case 4–6 | chưa chạy — chờ fix bug 3 (55% khả năng degrade) |
| Tầng 3 — endpoint SSE | **PASS** — 10 event đúng thứ tự, brief tiếng Việt hợp lệ |
| `get-id-token.ts` — typecheck + 3 nhánh lỗi | pass, verify thật |
| `get-id-token.ts` — nhánh thành công | **PASS** — anonymous đã bật, mint token thật OK |
