# Инженерный отчёт и Handoff для агента: Архитектура клавиатурного ввода и синтезатора (Milestone 1)

> **Для:** Агента-разработчика / интегратора ветки `origin/feature/keyboard-note-synth`  
> **От:** Агента-интегратора ветки `release`  
> **Статус:** Этап верифицирован в Icarus Verilog (`tests/audit/run_audit.py .` -> 100% PASS). Ветка `release` зафиксирована в коммитах `0c85b61` и `8e0f374`.

---

## 1. Контекст и границы этапа (Milestone 1)

В соответствии с правилом поэтапной разработки:
1. Мы фокусируемся **строго на этапе клавиатурного ввода и базового синтезатора тона**.
2. В top-level [audio_nexys_a7.sv](file:///c:/Users/zeets/VScode/audio_nexys_a7/src/top/audio_nexys_a7.sv) убран преждевременный неподтверждённый код MIDI UART (`UART_TXD_IN`, `midi_wavetable`, `midi_uart_receiver`), чтобы не нарушать границы этапа до физической проверки на стенде.
3. Сохранён 100% функционал:
   * **7-сегментный индикатор**: отображает введённую с клавиатуры цифру 0–9 строго на разряде `AN[0]`, остальные разряды погашены (`digit_mask = 8'h01`). До первого нажатия цифры индикатор полностью погашен (`8'h00`).
   * **4 ряда клавиатуры**:
     * Ряд `1..7` -> C1..B1 (`note_index 0..6`, `note_octave = 3'd0`)
     * Ряд `Q..U` -> C2..B2 (`note_index 0..6`, `note_octave = 3'd1`)
     * Ряд `A..J` -> C3..B3 (`note_index 0..6`, `note_octave = 3'd2`)
     * Ряд `Z..M` -> C4..B4 (`note_index 0..6`, `note_octave = 3'd3`)
   * **Кнопки платы**: `BTNC` (Play/Pause демо), `BTNL/BTNR` (листание демо-ноты), `BTNU/BTND` (громкость), `CPU_RESETN` (сброс).
   * **Аппаратные свойства**: `AUD_PWM` удерживается как open-drain (`0/Z`), VGA 800×600@60Hz имеет точное выравнивание гасящих интервалов (`vs_mismatch = 0`).

---

## 2. Детальный разбор архитектурных дефектов и их исправлений

### Дефект №1: Опасный многобитный CDC (Clock Domain Crossing) между 5 МГц и 49 МГц
* **Исходная реализация коллеги:**
  В модуле `audio_nexys_a7.sv` декодер `ps2_keyboard_digit` тактировался от `clk_5mhz0d`. Сигналы `keyboard_note_index` [2:0], `keyboard_note_octave` [2:0], `keyboard_note_event` и `keyboard_note_down` передавались в звуковой домен `clk_audio` (49.15865 МГц) с помощью обычных двухтриггерных синхронизаторов:
  ```verilog
  // ИСХОДНЫЙ КОД (ОШИБКА):
  keyboard_note_index_sync1 <= keyboard_note_index;
  keyboard_note_index_sync2 <= keyboard_note_index_sync1;
  keyboard_note_octave_sync1 <= keyboard_note_octave;
  keyboard_note_octave_sync2 <= keyboard_note_octave_sync1;
  ```
* **Почему это критический дефект:**
  1. Согласно `AGENTS.md` и правилам проектирования под Xilinx 7-Series: *«Для многобитного CDC нужен согласованный handshake, корректный async FIFO или подходящая память с протоколом. Два FF на каждый бит не обеспечивают атомарность шины»*.
  2. Разница задержек трассировки (skew) между отдельными битами шины приводит к тому, что в домене 49 МГц биты защёлкиваются в разные такты. При смене ноты (например, с 001 на 010) приёмник кратковременно фиксирует ложные значения (000 или 011), что слышно как высокочастотные щелчки и глитчи питча.
  3. Импульс `keyboard_note_event`, сформированный в домене 5 МГц, длится 200 нс, что составляет ~10 тактов домена 49 МГц.
* **Исправление в `release`:**
  1. Линии `PS2_CLK` и `PS2_DATA` с внешнего моста PIC24 имеют частоту всего 10–16 кГц. Модуль [ps2_keyboard_digit.sv](file:///c:/Users/zeets/VScode/audio_nexys_a7/src/rtl/ps2_keyboard_digit.sv) переведён на прямое тактирование от **`clk_audio` (49.15865 МГц)**!
  2. Это дало **Zero CDC** для всего звукового тракта: `note_index`, `note_octave`, `note_down` и строб управления генератором обновляются в одном и том же аудиодомене абсолютно атомарно за 1 такт!
  3. Для передачи 4-битной цифры на индикатор (в домен `clk_5mhz0d`) применён надёжный **Toggle CDC Handshake**:
     ```verilog
     // В домене clk_audio: фиксируем цифру и переключаем флаг
     always_ff @(posedge clk_audio or negedge aud_rst_n) begin
       if (!aud_rst_n) begin
         digit_toggle_audio  <= 1'b0;
         digit_audio_latched <= 4'd0;
       end else if (keyboard_digit_valid) begin
         digit_audio_latched <= keyboard_digit;
         digit_toggle_audio  <= ~digit_toggle_audio;
       end
     end

     // В домене clk_5mhz0d: синхронизируем 1-битный флаг через 2-FF и обновляем регистр
     always_ff @(posedge clk_5mhz0d or negedge rst_n) begin
       if (!rst_n) begin
         digit_toggle_sync   <= 2'b00;
         digit_toggle_sync_d <= 1'b0;
         digit_display       <= 4'd0;
         keyboard_digit_seen <= 1'b0;
       end else begin
         digit_toggle_sync   <= {digit_toggle_sync[0], digit_toggle_audio};
         digit_toggle_sync_d <= digit_toggle_sync[1];
         if (digit_toggle_sync[1] ^ digit_toggle_sync_d) begin
           digit_display       <= digit_audio_latched;
           keyboard_digit_seen <= 1'b1;
         end
       end
     end
     ```
     Поскольку человек нажимает клавиши с интервалом > 50 мс, значение `digit_audio_latched` стабильно на протяжении миллионов тактов. Передача через toggle гарантирует отсутствие пропусков и метастабильности.

---

### Дефект №2: Потеря состояния при нажатии нескольких клавиш (монофоническое затирание)
* **Исходная реализация коллеги:**
  Использовался единственный 8-битный регистр `held_note_scan_code`.
  Сценарий сбоя:
  1. Музыкант зажимает клавишу `1` (C1) — она звучит.
  2. Не отпуская клавишу `1`, музыкант нажимает клавишу `2` (D1) — регистр перезаписывается значением `2`.
  3. Музыкант отпускает клавишу `2` — модуль видит break-код `F0 1E`, сбрасывает `note_down <= 0` и **полностью выключает звук**.
  4. При этом палец музыканта всё ещё держит клавишу `1`, но звука нет! При последующем отпускании клавиши `1` break-код игнорируется, так как регистр уже пуст.
* **Исправление в `release`:**
  В модуле [ps2_keyboard_digit.sv](file:///c:/Users/zeets/VScode/audio_nexys_a7/src/rtl/ps2_keyboard_digit.sv) реализован аппаратный стек удержанных клавиш (`held_stack` на 8 элементов) с приоритетом последней нажатой ноты (**Last-Note Priority с Legato Recall**):
  * **При нажатии (Make code):** Если скан-кода ещё нет в стеке, он помещается на вершину (`held_stack[held_count]`), и модуль немедленно начинает играть эту ноту.
  * **При отпускании активной ноты:** Верхний элемент удаляется из стека. Если в стеке ещё остаются ранее зажатые клавиши, модуль мгновенно переключается на предыдущую удержанную ноту (`held_stack[held_count-2]`), сохраняя звучание (`note_down = 1`). Это чистое музыкальное легато!
  * **При отпускании более старой ноты:** Если из аккорда отпущена клавиша, не являющаяся текущей верхней, она удаляется из глубины стека со сдвигом, а текущая звучащая нота **не прерывается**.
  * **Отключение звука (`note_down = 0`):** Происходит строго тогда, когда музыкант отпустил последнюю удерживаемую клавишу (`held_count == 0`).
  * Для обратной совместимости с простыми тестами добавлен параметр `LEGATO_STACK` (1 = включён стек с легато, 0 = простой монофонический режим).

---

### Дефект №3: Дребезг Typematic Auto-Repeat клавиатуры
* **Исходная реализация коллеги:**
  Любая стандартная USB/PS/2 клавиатура при удержании клавиши свыше 500 мс начинает слать автоповторы скан-кода с частотой ~30 Гц (каждые 33 мс).
  В исходном коде каждый автоповтор заново выставлял `note_event <= 1'b1`. При подключении огибающей (ADSR) или счётчиков это приводило к пулемётному перезапуску фазы Attack.
* **Исправление в `release`:**
  В логике обработки Make-кода добавлена проверка: если пришедший код совпадает с текущей активной нотой (`held_stack[held_count-1] == byte_data`), он классифицируется как typematic repeat и подавляется: `note_event` не импульсирует повторно во время удержания.

---

### Дефект №4: Делитель динамической индикации и логические такты
* **Исходная реализация коллеги:**
  Тактовый сигнал для [sevseg_ctrl.sv](file:///c:/Users/zeets/VScode/audio_nexys_a7/src/rtl/sevseg_ctrl.sv) брался с выхода триггера счётчика `digital_clock_divider[12]`. В ПЛИС Xilinx Artix-7 использование выходов логических триггеров в качестве тактовых сигналов (`posedge`) нарушает дерево тактирования (BUFG), вызывает clock skew и ошибки timing closure.
* **Исправление в `release`:**
  Модуль [sevseg_ctrl.sv](file:///c:/Users/zeets/VScode/audio_nexys_a7/src/rtl/sevseg_ctrl.sv) теперь тактируется от системного `clk_5mhz0d`. Внутри модуля используется синхронный строб разрешения счёта (`if (&scan_divider)` с параметром `SCAN_DIV_BITS = 13`).
  Также поддержан порт `digit_mask`: при `digit_mask[i] == 0` анод выключен, сегменты погашены (`7'b1111111`).

---

## 3. Состав файлов и структура тестов

Ветка `release` содержит:
```
src/
├── rtl/
│   ├── ps2_keyboard_digit.sv       # Исправленный PS/2 декодер со стеком и фильтрацией repeat
│   ├── sevseg_ctrl.sv              # Синхронный контроллер индикации с digit_mask и clock enable
│   ├── tone_generator.sv           # DDS генератор тона C1-B4 со сдвигом октав
│   ├── display_ctrl.sv             # Исправленный контроллер VGA (vs_mismatch = 0)
│   ├── reset_button_debouncer.sv   # Исправленный сброс (асинхр. захват, синхр. снятие)
│   └── ...
├── top/
│   ├── audio_nexys_a7.sv           # Топ-модуль без CDC в аудиодомене
│   └── audio_nexys_a7.xdc          # XDC с PULLUP на F4/B2 и clock_groups
tests/
├── audit/
│   ├── run_audit.py                # Автоматический запуск полной проверки (Icarus)
│   └── audit_tb.sv                 # Тесты baseline блоков
└── keyboard/
    ├── tb_ps2_keyboard_digit.sv    # Тест всех 28 скан-кодов нот, цифр 0-9 и keypad
    ├── tb_ps2_keyboard_stack.sv    # Тест стека: легато, stale release, repeat, трезвучие
    └── tb_sevseg_digit_mask.sv     # Тест маскирования AN[0] и гашения остальных разрядов
doc/
├── KEYBOARD_NOTE_SYNTH.md          # Спецификация раскладки и инструкция
└── AGENT_HANDOFF_KEYBOARD.md       # Данный документ передачи архитектуры
```

---

## 4. Как подтянуть изменения и запустить верификацию

1. Подтяните ветку `release` из `origin`:
   ```bash
   git fetch origin release
   git merge origin/release
   ```
2. Запустите автоматический аудит проекта:
   ```bash
   python tests/audit/run_audit.py .
   ```
   Ожидаемый результат: все тесты (`fifo`, `audio`, `pwm`, `buttons`, `reset`, `vga`, `tb_ps2_keyboard_digit`, `tb_ps2_keyboard_stack`, `tb_sevseg_digit_mask`, `top elaboration`) завершаются со статусом **PASS** (код возврата 0).
