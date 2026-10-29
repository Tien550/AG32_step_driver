# Tài Liệu Kỹ Thuật — Mạch Điều Khiển Động Cơ Bước 1 Trục (AG32 Bipolar Stepper Driver)

[![PlatformIO](https://img.shields.io/badge/PlatformIO-agrv_sdk-orange.svg)](https://platformio.org/)
[![SoC](https://img.shields.io/badge/SoC-AGM%20AG32VF303-blue.svg)](http://www.alta-gate.com/)
[![FPGA Core](https://img.shields.io/badge/FPGA-2K%20LUTs%20CPLD-purple.svg)]()
[![Gate Driver](https://img.shields.io/badge/Gate%20Driver-IRS2111S-red.svg)](https://www.infineon.com/)
[![Thực Nghiệm](https://img.shields.io/badge/Th%E1%BB%B1c%20Nghi%E1%BB%87m-10%2F10%20Testcases%20(H1--H12)-success.svg)](docs/LAB_TESTCASES_AND_RESULTS.md)
[![Mô Phỏng](https://img.shields.io/badge/M%C3%B4%20Ph%E1%BB%8Fng-12%2F12%20Pass-brightgreen.svg)](docs/VERIFICATION.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Dự án thiết kế bộ điều khiển động cơ bước 2 pha lưỡng cực (Bipolar Stepper Driver) 1 trục chuẩn công nghiệp, tích hợp trên chip lai **AGM AG32VF303** (kết hợp lõi vi điều khiển 32-bit RISC-V RV32IMAFC @ 100 MHz và khối logic khả trình CPLD/FPGA ~2,000 LUTs).

Dự án được nghiên cứu, phát triển và chuẩn hóa dựa trên phân tích mạch thực tế của các dòng máy công nghiệp (driver CPLD hãng **Siruba** và bo điều khiển trục X máy may **Brother 430D**).

---

## 1. Tính Năng Nổi Bật

- **Kiến Trúc SoC Lai MCU + CPLD/FPGA:**
  - Toàn bộ máy trạng thái băm xung (chopper FSM), bảng tra sin/cos vi bước (LUT), bộ tạo dead-time và chốt bảo vệ quá dòng được xử lý 100% bằng phần cứng FPGA độc lập ở tần số **100 MHz (độ phân giải 10 ns)**, giải phóng hoàn toàn CPU.
- **FSM Băm Xung Dòng Đỉnh Pha Trộn (Peak-Current Mixed-Decay Chopper):**
  - Kết hợp **Fast Decay** (áp ngược chủ động dập tắt dòng trong $5.0\text{ }\mu\text{s}$) và **Slow Decay** (tuần hoàn dòng qua van dưới trong $15.0\text{ }\mu\text{s}$) ở tần số băm 30 kHz.
  - Loại bỏ hoàn toàn hiện tượng méo dạng sóng và trễ dòng ở góc phần tư giảm của hình sin, giúp motor quay êm và không bị giật/bỏ bước.
- **Tối Ưu Hóa Triệt Tiêu Zero-Crossing:**
  - Đổi mức biên độ nhỏ nhất của bảng LUT từ `0` thành `2` ($0.413\text{ V}$ bias). Hiện tượng kẹt bước/mất mô-men tại điểm chuyển giao cực tính (Zero-Crossing deadband) bị triệt tiêu hoàn toàn.
  - Loại bỏ các logic phụ phức tạp (`zc_mode`), tinh giản máy trạng thái xuống đúng **6 state chuẩn**.
- **Tầng Công Suất Half-Bridge Kép (IRS2111S):**
  - Mỗi cuộn dây sử dụng 2 IC driver IRS2111S (**U19, U20, U21, U22**) với dead-time phần cứng tích hợp sẵn (typ 650 ns), bổ sung thêm dead-time phần mềm (800 ns) cấu hình qua thanh ghi CPLD.
  - Tầng đệm cổng đảo **7407** ($a', b', c', d' \rightarrow a, b, c, d$) giao tiếp giữa CPLD và chân `IN` của IRS2111S.
- **Phần Cứng Nguồn Cấp & Mạch DAC R-2R 4-bit:**
  - 3 đường nguồn độc lập: **Nguồn Đỏ 15V** (kích Gate FET), **Nguồn Tím 36V-48V** (nguồn động lực motor), **Nguồn Lam 0V** (GND).
  - Tín hiệu DAC 4-bit từ CPLD đi qua **IC đệm U7** rồi vào mạng trở R-2R, tạo điện áp tham chiếu analog dạng Sine/Cos tại **`TP10` (Coil A)** và **`TP11` (Coil B)**.
  - Đường hồi tiếp đi qua điện trở bảo vệ $10\text{ k}\Omega$ trước khi vào IC Comparator so sánh với điện trở shunt đo dòng.
- **Độ Phân Giải Vi Bước Đa Dạng & Chuyển Đổi Động:**
  - Hỗ trợ chế độ 16 vi bước (16-step: $\pm 1$ bước/xung) và 8 vi bước (8-step: $\pm 2$ bước/xung).
  - Chế độ Run (100% dòng) và Hold (50% dòng khi dừng, **giảm 75% nhiệt lượng tỏa ra**) chuyển đổi tức thời qua chân `runhold_x`.
  - Khảo sát thực nghiệm trường hợp chuyển đổi độ phân giải động giữa chừng (Testcase 9 với 2 chân trigger PIN_51 và PIN_52).
- **Bảo Vệ Quá Dòng Phần Cứng Siêu Nhanh (80 ns Blanking Filter):**
  - Chân so sánh quá dòng `cmp_ov_c_x` đi qua bộ lọc số 8 chu kỳ xung nhịp (80 ns @ 100 MHz) để lọc sạch xung gai đóng cắt MOSFET.
  - Tự động chốt ngắt phần cứng, kéo toàn bộ chân điều khiển gate về mức `0` (kích hoạt toàn bộ MOSFET nhánh dưới dẫn, xả an toàn năng lượng cuộn dây về mass).
- **Cấu Hình Động Qua Bus AHB-Lite:** Vi điều khiển RISC-V có thể ghi/đọc trực tiếp các thanh ghi cấu hình thời gian băm xung qua địa chỉ `0x60000000`.

---

## 2. Sơ Đồ Khối Kiến Trúc Hệ Thống

```
                           AGM AG32VF303 SoC
 +-------------------------------------------------------------------+
 |  RISC-V 32-bit Core (100 MHz)                                     |
 |  (main.c / SDK - Cấu hình thời gian băm xung qua AHB)            |
 +---------------------------------+---------------------------------+
                                   | AHB-Lite Bus (0x60000000)
                                   v
 +-------------------------------------------------------------------+
 |                       Khối Logic CPLD/FPGA                        |
 |                                                                   |
 |  [input_sync] <--- Tín hiệu vào (PUL, DIR, EN, RUNHOLD, MODE)     |
 |         |                                                         |
 |         +---------> [microstep_seq] (Bộ đếm bước 4-bit)           |
 |                           |                                       |
 |                           v                                       |
 |                 [microstep_lut (Sin/Cos)]                         |
 |                    |                 |                            |
 |              Pha A (0 deg)     Pha B (90 deg)                     |
 |                    |                 |                            |
 |                    v                 v                            |
 |              [coil_drv A]      [coil_drv B]                       |
 |             +-------------+   +-------------+                     |
 |             |  vref_dac   |   |  vref_dac   | ===> U7 Buffer      |
 |             | hbridge_fsm |   | hbridge_fsm | ===> 7407 Inverters |
 |             +-------------+   +-------------+                     |
 |                    ^                 ^        ===> 4-bit R-2R DAC |
 |                    +--------+--------+        ===> 4x IRS2111S    |
 |                             |                      (U19,U20,      |
 |                       [chop_timer]                 (U21,U22)      |
 |                       (Bộ đếm chu kỳ 30 kHz)                      |
 |                             |                                     |
 |  [oc_guard] <--- PIN_17 (So sánh quá dòng)                        |
 |       |                                                           |
 |       +------------> Ngắt an toàn toàn bộ Gate nếu quá dòng       |
 +-------------------------------------------------------------------+
```

---

## 3. Bảng Phân Bổ Chân Phần Cứng (`mapping.ve`)

### Tín hiệu điều khiển & Trạng thái

| Tên chân | Số chân CPLD | Hướng | Chế độ kéo | Ý nghĩa chức năng |
| :--- | :---: | :---: | :---: | :--- |
| `axis_en` | **PIN_1** | Vào | Không | Kích hoạt trục: HIGH = Chạy; LOW = Tắt driver (khóa van dưới) |
| `pul_x` | **PIN_96** | Vào | **PULLUP** | Xung bước: Cạnh lên kích dịch 1 vi bước |
| `dir_x` | **PIN_15** | Vào | Không | Chiều quay: LOW = Quay thuận (+); HIGH = Quay nghịch (-) |
| `runhold_x` | **PIN_78** | Vào | **PULLUP** | Mức dòng: HIGH = Run (100% dòng); LOW = Hold (50% dòng) |
| `microstep_x` | **PIN_16** | Vào | Không | Độ phân giải: HIGH = 16 vi bước; LOW = 8 vi bước |
| `cmp_ov_c_x` | **PIN_17** | Vào | **PULLDOWN** | Báo quá dòng: HIGH = Lỗi quá dòng, chốt ngắt hệ thống |

### Cuộn A (Pha Sin — $0^\circ$)

| Tên chân | Số chân CPLD | Hướng | Tầng phần cứng kết nối | Chức năng |
| :--- | :---: | :---: | :--- | :--- |
| `cmp_x_a` | **PIN_95** | Vào (PULLUP) | Đầu ra Comparator A | Báo dòng chạm ngưỡng $V_{\text{ref\_A}}$ (Active LOW) |
| `q1_x_a` | **PIN_92** | Ra | U19 IRS2111S (qua 7407) | Điều khiển Gate nhánh trái cuộn A (1 = Kích High-side) |
| `q3_x_a` | **PIN_88** | Ra | U20 IRS2111S (qua 7407) | Điều khiển Gate nhánh phải cuộn A (1 = Kích High-side) |
| `dac_out_x_a[3:0]` | **PIN_86, 84, 82, 80** | Ra | U7 Buffer $\rightarrow$ R-2R Pha A | Đầu ra DAC 4-bit tạo điện áp tham chiếu $V_{\text{ref\_A}}$ (`TP10`) |

### Cuộn B (Pha Cosin — $90^\circ$)

| Tên chân | Số chân CPLD | Hướng | Tầng phần cứng kết nối | Chức năng |
| :--- | :---: | :---: | :--- | :--- |
| `cmp_x_b` | **PIN_93** | Vào (PULLUP) | Đầu ra Comparator B | Báo dòng chạm ngưỡng $V_{\text{ref\_B}}$ (Active LOW) |
| `q1_x_b` | **PIN_91** | Ra | U21 IRS2111S (qua 7407) | Điều khiển Gate nhánh trái cuộn B (1 = Kích High-side) |
| `q3_x_b` | **PIN_87** | Ra | U22 IRS2111S (qua 7407) | Điều khiển Gate nhánh phải cuộn B (1 = Kích High-side) |
| `dac_out_x_b[3:0]` | **PIN_85, 83, 81, 79** | Ra | U7 Buffer $\rightarrow$ R-2R Pha B | Đầu ra DAC 4-bit tạo điện áp tham chiếu $V_{\text{ref\_B}}$ (`TP11`) |

---

## 4. Máy Trạng Thái Băm Xung Mixed Decay (Chopper FSM)

Trong mỗi chu kỳ băm xung ($33.33\text{ }\mu\text{s}$ @ 30 kHz), FSM của từng cuộn dây lần lượt chuyển qua 6 trạng thái:

```
[S_OFF] ---> [S_DT_ON] ---> [S_DRIVE] ---> [S_DT_OFF] ---> [S_FAST] ---> [S_SLOW] ---> [S_OFF]
```

1. **`S_DT_ON` (Dead-time bật):** Khóa cả 2 van High-side trong $800\text{ ns}$ để chống ngắn mạch cầu trước khi cấp dòng.
2. **`S_DRIVE` (Kích dòng chủ động):** Cấp toàn bộ điện áp nguồn DC vào cuộn dây theo chiều xác định bởi `sign_bit`. Trạng thái này kết thúc khi comparator báo dòng đạt ngưỡng (`cmp = 0`) hoặc chạm giới hạn thời gian cực đại (`drive_max`).
3. **`S_DT_OFF` (Dead-time tắt):** Khóa cả 2 van High-side trong $800\text{ ns}$ trước khi chuyển sang dập dòng.
4. **`S_FAST` (Dập dòng nhanh):** Cấp ngược điện áp nguồn vào cuộn dây trong khoảng $5.0\text{ }\mu\text{s}$ (`cur_fast_th`) theo chiều ngược với chiều đã kích ở `S_DRIVE` (lưu trong `decay_sign`). Giúp triệt tiêu nhanh từ thông tích lũy trong cuộn cảm.
5. **`S_SLOW` (Dập dòng chậm):** Cho cả 2 van Low-side dẫn thông trong khoảng $15.0\text{ }\mu\text{s}$ (`slow_th`) để dòng điện tuần hoàn tự nhiên qua nhánh dưới với độ gợn sóng cực nhỏ.
6. **`S_OFF` (Nghỉ chu kỳ):** Đợi tín hiệu `cycle_start` tiếp theo từ bộ đếm tổng.

---

## 5. Bản Đồ Thanh Ghi AHB-Lite (CPLD Register Map)

Địa chỉ cơ sở: **`0x60000000`**

| Địa chỉ Offset | Tên thanh ghi | Trường bit | Quyền | Giá trị mặc định | Quy đổi thực tế (@ 100 MHz SYSCLK) |
| :---: | :--- | :---: | :---: | :---: | :--- |
| `0x00` | `dead_cycles` | `[7:0]` | R/W | `79` | **800 ns** thời gian dead-time phần mềm |
| `0x04` | `fast_cycles` | `[11:0]` | R/W | `499` | **5.00 $\mu\text{s}$** thời gian dập dòng nhanh (Fast Decay) |
| `0x08` | `slow_cycles` | `[11:0]` | R/W | `1499` | **15.00 $\mu\text{s}$** thời gian dập dòng chậm (Slow Decay) |
| `0x0C` | `period_cycles`| `[11:0]` | R/W | `3332` | **33.33 $\mu\text{s}$** (Tần số băm xung **30.00 kHz**) |

### Mã nguồn C cấu hình từ Firmware (`src/main.c`):

```c
#include "main.h"

int main(void)
{
    board_init();
    INT_SetIRQThreshold(MIN_IRQ_PRIORITY);
    INT_EnableIRQ(BUT_GPIO_IRQ, PLIC_MAX_PRIORITY);

    // Cấu hình thông số băm xung qua bus AHB nội
    WR(0x00, 79u);    // dead_cycles   — 800 ns dead-time   (= 80 - 1)
    WR(0x04, 499u);   // fast_cycles   — 5 µs fast decay    (= 500 - 1)
    WR(0x08, 1499u);  // slow_cycles   — 15 µs slow decay   (= 1500 - 1)
    WR(0x0C, 3332u);  // period_cycles — 30 kHz chopper     (= 3333 - 1)

    while (1) {
        // Vòng lặp giám sát hệ thống
    }
}
```

---

## 6. Kết Quả Đo Kiểm Thực Tế Trên Máy Hiện Sóng (H1–H12)

| Mã test | Tên bài kiểm tra | Nội dung và kết quả thực tế | Ảnh chụp Oscillo | Trạng thái |
| :---: | :--- | :--- | :---: | :---: |
| **TC1** | 1/8 Microstep | 8 mức điện áp DAC, dòng điện cuộn dây đồng dạng với DAC_OUT | **H1** | **ĐẠT** |
| **TC2** | 1/16 Microstep | 16 mức điện áp, dòng mượt hơn, giảm rung giật và tiếng rít cơ khí | **H2** | **ĐẠT** |
| **TC3** | Chế độ RUN / HOLD | RUN ra 100% biên độ, HOLD ra 50% biên độ, **giảm 75% nhiệt tỏa ra** | **H3** | **ĐẠT** |
| **TC4** | Tín hiệu DIR & EN | Đảo chiều quay mượt; khi EN=0 hệ thống ngắt ngay, tắt cả DAC_OUT | — | **ĐẠT** |
| **TC5** | Báo quá dòng OV_C | Hệ thống khóa an toàn lập tức trong $< 80\text{ ns}$, cần RST lại | — | **ĐẠT** |
| **TC6** | Quét tần số PUL | Tăng tần số bước từ thấp đến khi motor đạt giới hạn kéo tại **$\approx 3.7\text{ kHz}$** | **H4, H5, H6, H7, H8** | **ĐẠT** |
| **TC7** | Zoom MIX-DECAY | Thời gian Fast Decay ($5\text{ }\mu\text{s}$) và Slow Decay ($15\text{ }\mu\text{s}$) khớp setting qua AHB | — | **ĐẠT** |
| **TC8** | Chu kỳ PWM băm xung | Chu kỳ PWM trên cuộn dây đo được đúng $33.33\text{ }\mu\text{s}$ (tần số **30.00 kHz**) | — | **ĐẠT** |
| **TC9** | Đổi vi bước tại seq=1 | Chuyển 16 sang 8 step tại step 1; 4 FET mát, đo bằng trigger chân 51/52 | **H9', H10** | **ĐẠT** |
| **TC10**| Phase-Shifted Chopping | Băm xung lệch pha $180^\circ$ giữa cuộn A và B giúp giảm gợn dòng tụ nguồn | **H11, H12** | **ĐẠT** |

Chi tiết hình ảnh dạng sóng và phân tích sâu xem tại [`docs/LAB_TESTCASES_AND_RESULTS.md`](docs/LAB_TESTCASES_AND_RESULTS.md).

---

## 7. Hướng Dẫn Biên Dịch và Nạp Mạch

### Yêu cầu môi trường:
- VS Code đã cài đặt extension **PlatformIO**.
- Gói công cụ **AgRV PlatformIO** (tương thích AGM AG32VF303).
- Mạch nạp Segger J-Link hoặc CMSIS-DAP / DAP-Link.

### Lệnh biên dịch trên PlatformIO CLI:
```powershell
# Biên dịch logic CPLD/FPGA và firmware MCU
pio run -e debug

# Nạp đồng thời bitstream FPGA và firmware MCU vào chip
pio run -e debug -t upload
```

---

## 8. Mục Lục Tài Liệu Chuyên Sâu

- [Kiến trúc chi tiết hệ thống (System Architecture)](docs/ARCHITECTURE.md)
- [Thiết kế phần cứng & Mạch nguồn (Hardware Circuit & Power Rails)](docs/HARDWARE_CIRCUIT.md)
- [Nguyên lý máy trạng thái băm xung Mixed Decay (FSM Chopper)](docs/FSM_CHOPPER.md)
- [Báo cáo 10 kịch bản test thực tế & Ảnh Oscillo H1–H12 (Lab Testcases)](docs/LAB_TESTCASES_AND_RESULTS.md)
- [Phân tích so sánh driver công nghiệp: Siruba & Brother 430D (Industrial Comparison)](docs/INDUSTRIAL_COMPARISON.md)
- [Sơ đồ chân và tính toán mạch điện (Pinout & Schematics)](docs/PINOUT_AND_SCHEMATIC.md)
- [Bản đồ thanh ghi & Driver API (Registers & C API)](docs/REGISTERS_API.md)
- [Báo cáo kiểm thử mô phỏng 12 test case (Verification Report)](docs/VERIFICATION.md)
