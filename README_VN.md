# Tài Liệu Kỹ Thuật — Mạch Điều Khiển Động Cơ Bước 1 Trục (AG32 Bipolar Stepper Driver)

[![PlatformIO](https://img.shields.io/badge/PlatformIO-agrv_sdk-orange.svg)](https://platformio.org/)
[![SoC](https://img.shields.io/badge/SoC-AGM%20AG32VF303-blue.svg)](http://www.alta-gate.com/)
[![FPGA Core](https://img.shields.io/badge/FPGA-2K%20LUTs%20CPLD-purple.svg)]()
[![Gate Driver](https://img.shields.io/badge/Gate%20Driver-IRS2111S-red.svg)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Dự án thiết kế bộ điều khiển động cơ bước lưỡng cực (Bipolar Stepper Driver) 1 trục hiệu năng cao, tích hợp trên chip lai **AGM AG32VF303** (kết hợp lõi vi điều khiển 32-bit RISC-V RV32IMAFC @ 100 MHz và khối logic khả trình CPLD/FPGA ~2,000 LUTs).

---

## 1. Tính Năng Nổi Bật

- **Kiến Trúc Lai MCU + FPGA:** Toàn bộ thuật toán băm xung dòng điện (current chopper), bảng tra sin/cos vi bước (LUT), bộ tạo dead-time và chốt bảo vệ quá dòng được xử lý 100% bằng phần cứng FPGA độc lập, không làm tốn tài nguyên chu kỳ CPU.
- **FSM Băm Xung Dòng Đỉnh Pha Trộn (Peak-Current Mixed-Decay Chopper):**
  - Kết hợp **Fast Decay** (dập tắt dòng ngược chủ động) và **Slow Decay** (tuần hoàn dòng qua van dưới).
  - Loại bỏ hoàn toàn hiện tượng méo dạng sóng và trễ dòng ở góc phần tư giảm của hình sin, giúp động cơ chạy cực êm và không bị giật/bỏ bước ở tốc độ cao.
- **Tầng Công Suất Half-Bridge Kép (IRS2111S):** Mỗi cuộn dây sử dụng 2 IC driver IRS2111S với dead-time tích hợp sẵn (typ 650 ns), bổ sung thêm dead-time phần mềm (800 ns) cấu hình qua thanh ghi.
- **Bộ Tạo Điện Áp Đặt DAC R-2R 4-bit:** Tạo điện áp tham chiếu $V_{\text{ref}}$ chính xác cho 2 cuộn dây A và B lệch pha vuông góc $90^\circ$.
- **Độ Phân Giải Vi Bước Đa Dạng (Microstepping):**
  - Hỗ trợ chế độ 16 vi bước (16-step: $\pm 1$ bước/xung) và 8 vi bước (8-step: $\pm 2$ bước/xung).
  - Hỗ trợ chế độ Run (100% dòng) và Hold (50% dòng khi dừng) chuyển đổi tức thời qua chân phần cứng.
- **Bảo Vệ Quá Dòng Phần Cứng Siêu Nhanh (80 ns Blanking):**
  - Chân so sánh quá dòng `cmp_ov_c_x` đi qua bộ lọc chống nhiễu kỹ thuật số 8 chu kỳ xung nhịp (80 ns @ 100 MHz).
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
 |  [input_sync] <--- Tín hiệu vào (PUL, DIR, EN, RUNHOLD, STEP_MODE)|
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
 |             |  vref_dac   |   |  vref_dac   | ===> DAC Out R-2R   |
 |             | hbridge_fsm |   | hbridge_fsm | ===> IRS2111S Gates |
 |             +-------------+   +-------------+                     |
 |                    ^                 ^                            |
 |                    +--------+--------+                            |
 |                             |                                     |
 |                       [chop_timer] (Bộ đếm chu kỳ 30 kHz)         |
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

| Tên chân | Số chân CPLD | Hướng | Kết nối phần cứng | Chức năng |
| :--- | :---: | :---: | :--- | :--- |
| `cmp_x_a` | **PIN_95** | Vào (PULLUP) | Đầu ra Comparator A | Báo dòng chạm ngưỡng $V_{\text{ref\_A}}$ (Active LOW) |
| `q1_x_a` | **PIN_92** | Ra | IRS2111S Nửa cầu Trái | Điều khiển Gate nhánh trái cuộn A (1 = Kích High-side) |
| `q3_x_a` | **PIN_88** | Ra | IRS2111S Nửa cầu Phải | Điều khiển Gate nhánh phải cuộn A (1 = Kích High-side) |
| `dac_out_x_a[3:0]` | **PIN_86, 84, 82, 80** | Ra | Mạng trở R-2R Pha A | Đầu ra DAC 4-bit tạo điện áp tham chiếu $V_{\text{ref\_A}}$ |

### Cuộn B (Pha Cosin — $90^\circ$)

| Tên chân | Số chân CPLD | Hướng | Kết nối phần cứng | Chức năng |
| :--- | :---: | :---: | :--- | :--- |
| `cmp_x_b` | **PIN_93** | Vào (PULLUP) | Đầu ra Comparator B | Báo dòng chạm ngưỡng $V_{\text{ref\_B}}$ (Active LOW) |
| `q1_x_b` | **PIN_91** | Ra | IRS2111S Nửa cầu Trái | Điều khiển Gate nhánh trái cuộn B (1 = Kích High-side) |
| `q3_x_b` | **PIN_87** | Ra | IRS2111S Nửa cầu Phải | Điều khiển Gate nhánh phải cuộn B (1 = Kích High-side) |
| `dac_out_x_b[3:0]` | **PIN_85, 83, 81, 79** | Ra | Mạng trở R-2R Pha B | Đầu ra DAC 4-bit tạo điện áp tham chiếu $V_{\text{ref\_B}}$ |

---

## 4. Máy Trạng Thái Băm Xung Mixed Decay (Chopper FSM)

Trong mỗi chu kỳ băm xung ($33.3\text{ }\mu\text{s}$ @ 30 kHz), FSM của từng cuộn dây lần lượt chuyển qua 6 trạng thái:

```
[S_OFF] ---> [S_DT_ON] ---> [S_DRIVE] ---> [S_DT_OFF] ---> [S_FAST] ---> [S_SLOW] ---> [S_OFF]
```

1. **`S_DT_ON` (Dead-time bật):** Khóa cả 2 van High-side trong $800\text{ ns}$ để chống ngắn mạch cầu trước khi cấp dòng.
2. **`S_DRIVE` (Kích dòng chủ động):** Cấp toàn bộ điện áp nguồn DC vào cuộn dây theo chiều xác định bởi `sign_bit`. Trạng thái này kết thúc khi comparator báo dòng đạt ngưỡng (`cmp = 0`) hoặc chạm giới hạn thời gian cực đại (`drive_max`).
3. **`S_DT_OFF` (Dead-time tắt):** Khóa cả 2 van High-side trong $800\text{ ns}$ trước khi chuyển sang dập dòng.
4. **`S_FAST` (Dập dòng nhanh):** Cấp ngược điện áp nguồn vào cuộn dây trong khoảng $5\text{ }\mu\text{s}$ (`cur_fast_th`) theo chiều ngược với chiều đã kích ở `S_DRIVE` (lưu trong `decay_sign`). Giúp triệt tiêu nhanh sức điện động cảm ứng và từ thông dư.
5. **`S_SLOW` (Dập dòng chậm):** Cho cả 2 van Low-side dẫn thông trong khoảng $15\text{ }\mu\text{s}$ (`slow_th`) để dòng điện tuần hoàn tự nhiên qua nhánh dưới với độ gợn sóng cực nhỏ.
6. **`S_OFF` (Nghỉ chu kỳ):** Đợi tín hiệu `cycle_start` tiếp theo từ bộ đếm tổng.

---

## 5. Bản Đồ Thanh Ghi AHB-Lite (CPLD Register Map)

Địa chỉ cơ sở: **`0x60000000`**

| Địa chỉ Offset | Tên thanh ghi | Trường bit | Quyền | Giá trị mặc định | Quy đổi thực tế (@ 100 MHz SYSCLK) |
| :---: | :--- | :---: | :---: | :---: | :--- |
| `0x00` | `dead_cycles` | `[7:0]` | R/W | `79` | **800 ns** thời gian dead-time phần mềm |
| `0x04` | `fast_cycles` | `[11:0]` | R/W | `499` | **5.0 $\mu\text{s}$** thời gian dập dòng nhanh (Fast Decay) |
| `0x08` | `slow_cycles` | `[11:0]` | R/W | `1499` | **15.0 $\mu\text{s}$** thời gian dập dòng chậm (Slow Decay) |
| `0x0C` | `period_cycles`| `[11:0]` | R/W | `3332` | **33.33 $\mu\text{s}$** (Tần số băm xung **30.00 kHz**) |

### Mã nguồn C cấu hình từ Firmware (`src/main.c`):

```c
#include "main.h"

int main(void)
{
    board_init();

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

## 6. Hướng Dẫn Biên Dịch và Nạp Mạch

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

## 7. Tài Liệu Chi Tiết

- [Kiến trúc chi tiết hệ thống (System Architecture)](docs/ARCHITECTURE.md)
- [Nguyên lý máy trạng thái băm xung Mixed Decay (FSM Chopper)](docs/FSM_CHOPPER.md)
- [Sơ đồ chân và thiết kế mạch điện phần cứng (Pinout & Schematics)](docs/PINOUT_AND_SCHEMATIC.md)
- [Bản đồ thanh ghi & Driver API (Registers & C API)](docs/REGISTERS_API.md)
- [Báo cáo kiểm thử mô phỏng (Verification Report)](docs/VERIFICATION.md)
