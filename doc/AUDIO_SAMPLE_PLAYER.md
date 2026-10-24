# Модуль воспроизведения аудиофайла из памяти (BRAM Audio Sample Player)

**Ветка:** `feature/sample-memory-player`  
**Статус:** Реализовано, верифицировано в Icarus Verilog (`python tests/audit/run_audit.py .` -> 100% PASS).

---

## 1. Назначение и архитектура

Модуль предназначен для хранения и воспроизведения оцифрованного аудиофрагмента (сэмпла) из встроенной блочной памяти (Block RAM) ПЛИС Artix-7 (`xc7a100tcsg324-1`).

```mermaid
flowchart LR
    MEM_FILE[sample_data.mem\n4096 samples 16-bit] -->|readmemh| ROM[audio_sample_rom\nBRAM RAMB36/18]
    ROM -->|dout[15:0]\n1-clock latency| PLY[audio_sample_player\nBackpressure & Loop FSM]
    
    subgraph AudioEngine["Аудиодомен clk_audio (49.15865 MHz)"]
        SW0{SW 0}
        PLY -->|mem_sample[15:0]\nmem_sample_valid| SW0
        TONE[tone_generator\nKeyboard Synth] -->|tone_sample[15:0]\nvalid| SW0
        SW0 -->|sample[15:0]| VOL[Volume Multiplier\nBTNU / BTND]
        VOL --> FIFO[FIFO Buffer\n256 samples]
        FIFO --> PWM[PWM 48 kHz\nAUD_PWM 0/Z]
    end

    CTRL[Управление] -->|SW 0: 0=Synth, 1=Sample| SW0
    CTRL -->|BTNC / Key: play_trigger| PLY
    CTRL -->|SW 1: loop_en| PLY
    CTRL -->|BTND: stop_cmd| PLY
```

---

## 2. Инженерные свойства и соответствие `AGENTS.md`

1. **Тактовый домен и сброс:**
   * Тактирование: `clk_audio` (49.15865 МГц) — строго синхронно с трактом аудио FIFO/PWM. Ноль CDC на звуковом пути.
   * Сброс: `aud_rst_n` (синхронное снятие сброса).
2. **Память и синтез в BRAM:**
   * Модуль [audio_sample_rom.sv](file:///c:/Users/zeets/VScode/audio_nexys_a7/src/rtl/audio_sample_rom.sv) использует директиву `(* ram_style = "block" *)`, гарантирующую синтез в аппаратные блоки RAMB18E1/RAMB36E1 Vivado.
   * Латентность чтения: ровно 1 такт (`always_ff @(posedge clk) if (en) dout <= mem[addr]`).
3. **Безопасный Handshake и Backpressure (`ready && valid`):**
   * При заполнении FIFO (`ready == 0`) строб `en` памяти BRAM комбинационно снимается.
   * Адрес и текущий сэмпл на выходе **замораживаются**. Нет потери тактов, нет пропуска сэмплов, нет фазового дребезга.
4. **Формат аудио:**
   * 16 бит offset-binary (0..65535, середина 32768), полностью совместимый с существующим PWM и умножителем громкости.

---

## 3. Управление на плате Nexys A7

| Переключатель / Кнопка | Режим / Действие | Описание |
|---|---|---|
| `SW[0]` | **0** | Режим синтезатора (DDS Tone Generator + клавиатура 4 октавы). |
| `SW[0]` | **1** | **Режим проигрывателя сэмплов из BRAM.** |
| `BTNC` (в режиме `SW0=1`) | Запуск проигрывания | Нажатие кнопки Center запускает воспроизведение звука с начала (адрес 0). |
| `SW[1]` | Режим повтора (Loop) | `0` = однократное воспроизведение (One-shot), `1` = непрерывный цикл (Loop). |
| `BTND` (в режиме `SW0=1`) | Остановка | Прерывает воспроизведение, сбрасывая в тишину (32768). |
| Клавиши клавиатуры | Триггер сэмпла | При нажатии любой ноты на клавиатуре запускается проигрывание сэмпла. |
| `BTNU / BTND` | Громкость | Цифровое масштабирование амплитуды (0..15). |

---

## 4. Утилита конвертации WAV в память (`tools/wav_to_mem.py`)

Для загрузки любого реального звука (речь, сэмпл инструмента, перкуссия) добавлена консольная утилита:
```bash
# Конвертировать реальный WAV-файл:
python tools/wav_to_mem.py my_sound.wav -o src/rtl/sample_data.mem -n 4096

# Или сгенерировать чистый синтетический тембр колокольчика (A4 440 Гц + обертоны):
python tools/wav_to_mem.py --synth -o src/rtl/sample_data.mem -n 4096
```

---

## 5. Верификация

Запуск полного аудита ветки:
```bash
python tests/audit/run_audit.py .
```

Проверки в `tests/audio/tb_audio_sample_player.sv`:
- `[TEST 1]` One-shot playback: потактовое соответствие всех 64 сэмплов golden memory, строб `playback_end`, корректный останов в IDLE.
- `[TEST 2]` Backpressure handling: заморозка на 10 циклов при `ready=0`, отсутствие изменения данных, корректное возобновление без пропусков.
- `[TEST 3]` Loop mode playback: непрерывный переход с последнего сэмпла на адрес 0.
- `[TEST 4]` Immediate stop: мгновенный сброс в тишину (16'h8000) по `stop_cmd`.
