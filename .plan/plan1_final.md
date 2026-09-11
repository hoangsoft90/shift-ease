# ShiftEase — Kế hoạch tổng hợp cuối cùng (Plan Final)

> Tổng hợp từ: `plan1.md` (ý tưởng gốc) + 5 bản review AI (`plan1_review1` → `plan1_review5`)
> Mục đích: chốt định hướng sản phẩm, làm tài liệu khởi động cho `plan2` (đặc tả kỹ thuật chi tiết) và quá trình build bằng AI agents.

---

## 0. Verdict

**NÊN LÀM — nhưng không triển khai `plan1.md` nguyên trạng.**

Ý tưởng gốc xác định đúng "painkiller": người làm ca cần công cụ quản lý lịch + cân bằng cuộc sống. Nhưng plan gốc mắc lỗi **scope creep nghiêm trọng** (Calendar + Roster + Health AI + Sleep + Nutrition + Workout + Payroll + B2B cùng lúc) và **đánh giá thấp đối thủ hiện tại**.

Định hướng đúng, được cả 5 review đồng thuận:

> **ShiftEase = Personal Operating System for Shift Workers**, xoay quanh 3 trụ cột **Work – Life – Money**, thắng không phải nhờ nhiều tính năng hơn đối thủ mà nhờ: **(1) nhập liệu nhanh hơn hẳn, (2) tính đúng tuyệt đối (DST/timezone/pay), (3) UX đơn giản tới mức "ridiculously easy".**

---

## 1. Target Persona (chốt)

**Nurse / Healthcare shift worker**, 25–45 tuổi, tại bệnh viện lớn ở **Mỹ, Anh, hoặc Đức**:

- Ca xoay 3 kíp (day/evening/night), overtime thường xuyên
- Có thể làm nhiều nguồn thu nhập (bệnh viện chính + clinic/agency)
- Có gia đình, cần đồng bộ lịch với vợ/chồng/con
- Nhận lịch từ nơi làm việc qua **ảnh chụp, PDF, Excel** — không phải nhập tay
- Dễ lan truyền trong môi trường làm việc (word-of-mouth giữa đồng nghiệp)

Lộ trình mở rộng sau PMF: Nurses → Healthcare nói chung → Police/Firefighter → Factory/FIFO → Retail/Hospitality → shift workers nói chung.

**Phạm vi địa lý MVP: Mỹ, Anh, Đức.** Đông Á (Nhật/Hàn) chính thức loại khỏi MVP — để dành cho giai đoạn mở rộng sau, tránh gánh thêm localization phức tạp ngay từ đầu.

---

## 2. Core Problem Statement

> "Người làm ca khó nhìn thấy bức tranh tổng thể về công việc – thời gian rảnh – thu nhập, vì lịch thay đổi liên tục, việc nhập lịch vào công cụ hiện có quá mất công, và các app hiện tại thường sai giờ (DST/timezone) hoặc quá rườm rà."

---

## 3. Bối cảnh cạnh tranh (không được đánh giá thấp)

Đây là điểm bị các review sau (2–5) bỏ sót nhưng review1 chỉ ra rất quan trọng: đối thủ **đã mạnh hơn** những gì plan gốc giả định.

| Đối thủ | Tình trạng |
|---|---|
| **Supershift** | 1M+ downloads (Android), 4.7★/29.8K reviews; 4.9★/5.3K trên iOS. Đã có multiple shifts/day, widgets, cloud sync, calendar integration, PDF export, offline/no-account |
| **MyShiftPlanner** | Đã có rotation patterns, custom roster builder, calendar sync, partner overlay, leave tracking, overtime, pay calculation, team edition |
| **Spark, WorkRoster, FIFO Clock, Timeshifter, ShiftRecover** | Các ngách chuyên biệt khác đã hoạt động |

**Hệ quả chiến lược quan trọng nhất:** "Shift Pattern + Roster Planner" **không phải USP**, mà là **table stakes**. Pattern+Exception Engine, Partner Overlay, Availability Finder — vốn được xem là USP trong các review — thực chất **nhiều đối thủ đã có gần đủ**. USP thật sự chỉ còn nằm ở:

1. **Độ chính xác kỹ thuật tuyệt đối** (đối thủ mắc lỗi DST/timezone — đây là "tử huyệt" đã biết của Supershift)
2. **Trải nghiệm nhập liệu** (chưa app nào làm tốt OCR/import — khoảng trống thị trường thật)
3. **Sự đơn giản UX tuyệt đối** — đúng với tên gọi "Ease"

`plan2` phải lấy 3 điểm này làm trục differentiation chính thức, không chỉ liệt kê tính năng như plan gốc.

---

## 4. MVP Roadmap (P0 / P1 / P2 / P3)

| Nhóm | Tính năng | Ưu tiên | Ghi chú |
|---|---|---|---|
| **Core Calendar** | Shift templates, multiple shifts/day, overnight shift, rotation patterns, custom pattern builder, generate future occurrences, edit/delete, bulk edit, undo, notes, color coding, multiple jobs | **P0** | Nền tảng cốt lõi, nhưng là table-stakes, không phải USP |
| **Time Engine** | DST-safe, multi-timezone, shiftDate semantic, offline-first | **P0** | Đây là nơi tạo moat kỹ thuật thật sự |
| **UX/UI** | "Today" screen làm home, week/month view, widgets, search/filter, dark mode | **P0** | Today screen thay Calendar view làm màn hình mở đầu |
| **Smart Import** | OCR từ ảnh/PDF, import Excel/CSV với mapping cột | **P0/P1** | Rào cản lớn nhất khiến người dùng bỏ cuộc nếu thiếu — nên đẩy càng sớm càng tốt |
| **Notifications** | Shift reminder, commute reminder, weekly summary | **P0** | |
| **Money** | Pay Rule Engine linh hoạt (base rate, night/weekend differential, overtime rules), income dashboard | **P1** | Động lực retention và conversion rất mạnh |
| **Life Sync** | Availability Finder, Partner/Family Overlay (share link, Privacy mode: Busy/Free/Recovery), iCal/Webcal export | **P1** | USP thực tế, nhưng lưu ý: đối thủ cũng đã có gần đủ — chỉ thắng nếu UX mượt hơn hẳn |
| **Smart Features** | Pattern auto-detection, shift-change detection (báo khi employer đổi lịch, ảnh hưởng availability/thu nhập/recovery) | **P2** | |
| **Wellness (nhẹ, rule-based)** | Nhắc nghỉ sau ca đêm, thống kê giờ làm/nghỉ, cảnh báo chuỗi ca dài | **P2** | KHÔNG sleep tracking, KHÔNG phân tích Apple Health, KHÔNG gợi ý dinh dưỡng — ranh giới cứng để tránh trôi dạt lại thành Health AI |
| **Colleague Sharing (B2C2B nhẹ)** | Share lịch read-only với đồng nghiệp, đánh dấu "open to swap" | **P2** | Giới hạn cứng: KHÔNG approval flow, KHÔNG admin — nếu không sẽ trôi dạt thành B2B |
| **Health AI** | Circadian optimization, nutrition, workout, medical risk | ❌ **P3 (loại khỏi MVP)** | Rủi ro pháp lý + kéo app sang category khác |
| **B2B / Team** | Quản lý đội nhóm, duyệt đơn nghỉ, báo cáo | ❌ **P3 (loại khỏi MVP)** | Biến app thành WFM SaaS, không hợp B2C |

---

## 5. Domain Model & Time Engine (phải viết spec kỹ trước khi code)

### Nguyên tắc cốt lõi: phân biệt `shiftDate` vs `Timestamp`

Ca đêm 22:00 ngày 01/09 → 06:00 ngày 02/09, về tâm lý người dùng là **"ca đêm ngày 01/09"**. Data Schema bắt buộc lưu:

- `shift_date` (String, "2026-09-01"): góc nhìn người dùng
- `start_datetime_utc` / `end_datetime_utc`: UTC timestamp để tính chính xác số giờ
- `timezone`: múi giờ nơi làm việc

**Quy tắc bất biến:** Pay Engine phải tính từ `end_datetime_utc - start_datetime_utc`, **không bao giờ** dùng `local_end_time - local_start_time` (sai trong đêm DST).

**Lưu ý bổ sung:** khi user đổi vị trí/timezone trên điện thoại (đi công tác), các `ShiftOccurrence` đã tồn tại **không được tự động re-tính** theo timezone mới — timezone gắn cố định vào occurrence tại thời điểm tạo.

### Kiến trúc Pattern → Occurrence → Exception

- **Pattern (Baseline):** chu kỳ lặp lại (VD: 4-on/4-off, DuPont). Chỉ lưu quy luật (Anchor Date + Sequence Matrix)
- **Generated Occurrences:** lịch tự sinh cho ~12 tháng tới
- **Exception Layer:** override thực tế (PTO/Sick, Shift Swap, Overtime) — khi user sửa 1 ngày, các chu kỳ sau **không bị lệch**

### Data Schema đề xuất

```typescript
// 1. Shift Template
interface ShiftTemplate {
  id: string;
  name: string;           // "Day Shift", "Night Shift"
  code: string;            // "D", "N"
  color: string;
  startTime: string;       // "07:00"
  endTime: string;         // "19:00"
  breakDurationMinutes: number;
  payMultiplier: number;   // 1.0 ngày, 1.3 đêm
}

// 2. Shift Pattern
interface ShiftPattern {
  id: string;
  name: string;             // "4 ON - 4 OFF"
  cycleLengthDays: number;
  sequence: (string | null)[]; // ShiftTemplate IDs hoặc null (OFF)
  anchorDate: string;
}

// 3. Shift Occurrence
interface ShiftOccurrence {
  id: string;
  shiftDate: string;          // key hiển thị
  templateId: string;
  startDateTimeUtc: string;
  endDateTimeUtc: string;
  timezone: string;
  isException: boolean;
  exceptionType?: 'SWAP' | 'OVERTIME' | 'LEAVE' | 'CUSTOM';
  note?: string;
  actualPayEstimate?: number;
}

// 4. Pay Rule (theo Pay Template linh hoạt, không hard-code luật quốc gia)
interface PayRule {
  id: string;
  baseHourlyRate: number;
  nightDifferential?: { type: 'percent' | 'flat'; value: number };
  weekendDifferential?: { type: 'percent' | 'flat'; value: number };
  overtimeRules: { thresholdHours: number; period: 'day' | 'week'; multiplier: number }[];
}
```

### Pay Rule Template Library (bổ sung mới)

Không bắt user tự cấu hình từ đầu — cung cấp sẵn template theo ngành + quốc gia (VD: "US Hospital Nurse — California overtime rule", "UK NHS shift differential"). Nếu không có, người dùng mới sẽ bỏ qua bước cấu hình → tính lương sai → mất niềm tin ngay từ đầu (đúng lỗi khiến Supershift bị chê).

**Nguyên tắc hiển thị:** mọi số tiền hiển thị trên Today screen / Income dashboard đều gắn nhãn **"Ước tính — không phải bảng lương chính thức"** để tránh kỳ vọng sai và rủi ro trách nhiệm.

### Test Plan bắt buộc cho Time Engine (trước khi giao AI agent code)

- DST spring-forward: ca đêm bắc qua đêm chuyển giờ (chỉ dài 7 tiếng thay vì 8)
- DST fall-back: ca đêm bắc qua đêm lùi giờ (dài 9 tiếng)
- Overnight shift bắc qua nửa đêm chuẩn (không DST)
- Ca bắc qua ranh giới năm/tháng
- User đổi timezone thiết bị giữa chừng — occurrence cũ giữ nguyên timezone gốc
- Pattern có exception ở giữa chu kỳ — các occurrence sau exception không bị lệch anchor

---

## 6. Privacy & Compliance

- **Offline-first** làm mặc định; khi có cloud sync → **end-to-end encryption**
- Chia sẻ theo lớp: chỉ trạng thái `Busy/Free/Recovery` (bạn bè/đồng nghiệp) vs chi tiết ca đầy đủ (gia đình) — không hiển thị chi tiết công việc nhạy cảm mặc định
- Với thị trường châu Âu: cần quy trình xóa dữ liệu, xuất dữ liệu (GDPR), chính sách cookie rõ ràng
- Family/Partner sync không bắt buộc tài khoản: **Dynamic iCal/Webcal Link** để người thân subscribe trực tiếp trên lịch điện thoại của họ

---

## 7. Monetization

**Free**
- 1 job, basic patterns, calendar cơ bản, offline

**Pro**
- Unlimited jobs & patterns
- Pay Rule Engine + Income dashboard
- Family/Partner overlay, Availability Finder
- Widgets, calendar sync
- Smart Import (OCR/CSV)
- Cloud backup (optional, E2E encrypted)
- Wellness nhẹ (P2)

**Pricing:** $3.99/tháng · $29.99/năm · **$39.99 lifetime** (ưu tiên bán Lifetime giai đoạn đầu để tối ưu dòng tiền, chuyển hướng subscription sau khi có dữ liệu conversion). Có thể thêm gói "Supporter" (đóng góp tự nguyện) để tạo thiện cảm với early adopters.

---

## 8. Go-to-Market

- Content marketing: blog/video "Sống khỏe với ca kíp", "Cách tính overtime đúng", cheat sheet các pattern phổ biến (DuPont, 2-2-3, 4-on-4-off)
- Cộng đồng Reddit/Facebook cho shift workers
- Hợp tác nhẹ với influencer y tá/cứu hỏa
- ASO: `ShiftEase — Shift Calendar & Planner` (từ "Shift" trong tên không tự động đảm bảo rank cao — vẫn cần chiến lược ASO đầy đủ: title, subtitle, description, keywords, reviews)
- Tagline: **"Your shift. Your life."** hoặc **"Work your shifts. Live your life."**

---

## 9. Rủi ro chính & cách giảm thiểu

| Rủi ro | Mức độ | Giảm thiểu |
|---|---|---|
| Scope creep khi code | Cao | Tuân thủ nghiêm ngặt P0/P1/P2/P3, không thêm feature ngoài roadmap |
| DST/Timezone bug | Rất cao | Test suite đầy đủ theo mục 5 trước khi release |
| Nhập liệu kém → churn cao | Cao | Ưu tiên Smart Import ngay từ P0/P1 |
| Ảo tưởng về USP (đối thủ đã có sẵn) | Cao | Định kỳ đối chiếu tính năng với Supershift/MyShiftPlanner, tập trung vào 3 trục differentiation ở mục 3 |
| Tính lương sai → mất niềm tin | Cao | Pay Rule Template theo ngành/quốc gia + nhãn "ước tính" bắt buộc |
| "Wellness nhẹ" trôi dạt thành Health AI | Trung bình | Giới hạn cứng: chỉ rule-based, không AI, không medical claim |
| "Colleague sharing" trôi dạt thành B2B | Trung bình | Giới hạn cứng: chỉ read-only share link, không approval/admin flow |
| Privacy perception | Trung bình | Offline-first + E2E encryption khi sync + granular sharing |

---

## 10. Hành động tiếp theo cho `plan2`

`plan2` nên viết chi tiết kỹ thuật theo 8 phần:

1. Target Persona chi tiết (thói quen, pain points cụ thể)
2. Core Problem Statement + Differentiation (3 trục ở mục 3)
3. MVP Roadmap chi tiết theo P0–P3 (mục 4)
4. Domain Model + Time Engine spec đầy đủ (mục 5), bao gồm Test Plan
5. UX Architecture: wireframe cho "Today" screen và "Availability Finder"
6. Partner/Family Sharing Flow (Dynamic Webcal, Privacy Mode)
7. Monetization & Packaging chi tiết (mục 6–7)
8. Agent Execution Strategy: chia module độc lập (`core/time`, `core/pattern`, `ui/today`, `ui/calendar`, `payroll`, `sync`, `import`) để giao cho AI coding agents, có giám sát chặt đặc biệt ở module `core/time`.