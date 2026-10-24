# ТЕКУЩИЙ СТАТУС ПРОЕКТА, ЦЕЛЕВАЯ ЗАДАЧА И КАРТА ФАЙЛОВ

Этот документ служит стартовой точкой для любого агента. Здесь зафиксировано: **что требуется сделать**, **что уже есть в репозитории**, **какие дефекты воспроизводятся** и **где искать исходники и документацию**.

---

## 1. Целевая задача проекта (Hackathon Target)

**Цель:** Создать интерактивный музыкальный синтезатор на базе ПЛИС Xilinx Artix-7 (плата Nexys A7-100T) на чистом SystemVerilog. 
Управление осуществляется с обычной компьютерной клавиатуры (USB HID через штатный контроллер платы PIC24/PS2) с динамической визуализацией на экране VGA 800×600.

### Формула оценки хакатона:
$$\text{Итог} = \text{Звук} \times K_1 + \text{VGA} \times K_2 + \text{Периферия} \times K_3 + \text{Презентация}$$

| Направление | Макс. балл | Множитель | Целевой результат для максимума баллов |
|---|---:|---|---|
| **Звук (Audio)** | 45 | $K_1$ | Таблично-волновой синтез (Wavetable) по нотам клавиатуры, потоковый тракт `valid/ready`, 48 кГц, 10-бит PWM. |
| **VGA Видео** | 25 | $K_2$ | Динамический осциллограф звука (бегущая форма волны), пианино с подсветкой нажатых клавиш, UI синтезатора 800×600. |
| **Периферия** | 20 | $K_3$ | Подключение обычной клавиатуры через порт USB Host (PS/2 пины F4/B2), переключение октав/тембров, индикация на 7-сегментнике. |
| **Презентация** | 10 | Нет | Понимание архитектуры командой, модульность RTL кода. |

> $K_1, K_2, K_3$ — индивидуальные коэффициенты понимания решения командой (от 0.0 до 1.0).

---

## 2. Что уже реализовано в репозитории

1. **Базовый звуковой тракт:**
   * DDS синтезатор одиночных нот (`src/rtl/tone_generator.sv`): генерация тестовой ноты A4 (440 Гц), поддержка удержания фазы при backpressure.
   * Одноканальное FIFO сэмплов (`src/rtl/fifo.sv`).
   * 10-битный PWM модулятор (`src/rtl/pwm.sv`): безопасное формирование ШИМ в режиме 0/Z.
2. **Базовый видеовывод VGA 800×600:**
   * Контроллер развертки (`src/rtl/display_ctrl.sv`): формирование синхросигналов HS/VS и активной зоны.
   * Статический генератор картинки (`src/rtl/vga_demo.sv`): отображение логотипа и надписей.
   * Знакогенератор (`src/rtl/font_rom.sv`) и ROM логотипа (`src/rtl/sber_logo_rom.sv`).
3. **Периферия и управление:**
   * Модуль кнопок (`src/rtl/button_ctrl.sv`) и подавитель дребезга (`src/rtl/button_debouncer.sv`).
   * Контроллер 8-разрядного 7-сегментного индикатора (`src/rtl/sevseg_ctrl.sv`).
   * Модуль формирования сброса (`src/rtl/reset_button_debouncer.sv`, `src/rtl/reset_sync.sv`).
4. **Инфраструктура симуляции:**
   * Baseline-аудит на Icarus Verilog: [`tests/audit/run_audit.py`](file:///c:/Users/zeets/VScode/audio_nexys_a7/tests/audit/run_audit.py).
   * Verilator C++ эмулятор с выводом реального звука через SDL2: `src/sim/main_audio.cpp`.
   * Скрипт создания проекта Vivado: `src/tcl/deploy.tcl`.

---

## 3. Что НЕ реализовано (Фронт основных работ)

1. **Музыкальные файлы и мелодии:** Сейчас играет только одна непрерывная нота DDS. Нет секвенсора мелодий (ROM-таблицы нот/длительностей), нет парсера WAV или SD-контроллера.
2. **Динамическая визуализация VGA:** Графика статична. Нет связи между звуковым сэмплом и экраном (нужно реализовать осциллограф/спектрограмму).
3. **Интерфейс пользователя (UI):** Нет меню переключения режимов и визуального статуса трека.
4. **Сквозная аппаратная проверка на плате:** Прошивка и запуск на реальном железе Nexys A7 еще не проводились.

---

## 4. Статус известных дефектов (Исправлены и верифицированы)

| Дефект | Файл | Суть проблемы | Статус исправления |
|---|---|---|---|
| **Потеря захвата PLL (Reset bug)** | `src/rtl/reset_button_debouncer.sv` | При падении `locked` до 0 сигнал `rst_n` оставался в 1. | **ИСПРАВЛЕН:** асинхронный сброс `rst_n <= 1'b0` по `!pll_locked`, синхронное снятие по `clk_5mhz`. Тест проходит. |
| **Смещение кадрового гашения (VGA bug)** | `src/rtl/display_ctrl.sv` | VS импульс был смещен на 2110 пиксельных тактов. | **ИСПРАВЛЕН:** логика `next_v_count >= v_pixels + v_fp`, расхождение `vs_mismatch = 0`. Тест проходит. |
| **Ошибка элаборации и timescale TB** | `src/tb/tb_audio_nexys_a7.sv` | Конструкция `.*` без портов VGA, период клока `#2` (250 МГц вместо 100 МГц). | **ИСПРАВЛЕН:** добавлен `timescale 1ns/1ps`, клок 100 МГц (`#5`), завершение симуляции. |

---

## 5. Полная карта файлов репозитория

### Исходные коды RTL (`src/rtl/`)
* [`src/rtl/tone_generator.sv`](file:///c:/Users/zeets/VScode/audio_nexys_a7/src/rtl/tone_generator.sv) — DDS генератор звуковых частот.
* [`src/rtl/fifo.sv`](file:///c:/Users/zeets/VScode/audio_nexys_a7/src/rtl/fifo.sv) — потоковый буфер сэмплов `valid/ready`.
* [`src/rtl/pwm.sv`](file:///c:/Users/zeets/VScode/audio_nexys_a7/src/rtl/pwm.sv) — 10-битный ШИМ-модулятор (0/Z).
* [`src/rtl/display_ctrl.sv`](file:///c:/Users/zeets/VScode/audio_nexys_a7/src/rtl/display_ctrl.sv) — генератор синхросигналов VGA 800×600.
* [`src/rtl/vga_demo.sv`](file:///c:/Users/zeets/VScode/audio_nexys_a7/src/rtl/vga_demo.sv) — вывод картинки на экран.
* [`src/rtl/button_ctrl.sv`](file:///c:/Users/zeets/VScode/audio_nexys_a7/src/rtl/button_ctrl.sv) — обработка кнопок и переключателей.
* [`src/rtl/sevseg_ctrl.sv`](file:///c:/Users/zeets/VScode/audio_nexys_a7/src/rtl/sevseg_ctrl.sv) — динамическая индикация семисегментника.
* [`src/rtl/reset_button_debouncer.sv`](file:///c:/Users/zeets/VScode/audio_nexys_a7/src/rtl/reset_button_debouncer.sv) — логика кнопки сброса и контроля PLL.

### Top-level и ограничения (`src/top/`)
* [`src/top/audio_nexys_a7.sv`](file:///c:/Users/zeets/VScode/audio_nexys_a7/src/top/audio_nexys_a7.sv) — верхний уровень проекта для платы.
* [`src/top/audio_nexys_a7.xdc`](file:///c:/Users/zeets/VScode/audio_nexys_a7/src/top/audio_nexys_a7.xdc) — пины и тайминги для Vivado.

### Документация (`doc/`)
* [`doc/REQUIREMENTS.md`](file:///c:/Users/zeets/VScode/audio_nexys_a7/doc/REQUIREMENTS.md) — требования хакатона, система баллов, неизвестные.
* [`doc/AGENT_TASKS.md`](file:///c:/Users/zeets/VScode/audio_nexys_a7/doc/AGENT_TASKS.md) — роли агентов и зоны ответственности.
* [`doc/ANALYSIS.md`](file:///c:/Users/zeets/VScode/audio_nexys_a7/doc/ANALYSIS.md) — подробнейший технический разбор каждого модуля RTL.
* [`doc/DEPENDENCIES.md`](file:///c:/Users/zeets/VScode/audio_nexys_a7/doc/DEPENDENCIES.md) — зависимости (Vivado, Verilator, SDL2, Icarus).
* [`AGENTS.md`](file:///c:/Users/zeets/VScode/audio_nexys_a7/AGENTS.md) — фундаментальные правила для разработчиков и агентов.
