# Baseline-аудит

Из корня репозитория:

```bash
python3 tests/audit/run_audit.py .
```

Нужны Python 3, `iverilog`, `vvp`. Проверено с Icarus Verilog 13.0 на macOS ARM64. Исходный проект не редактируется, компиляция идёт во временный каталог.

Сценарии: FIFO (20000 тактов), DDS A4/backpressure, PWM, button_ctrl, reset, VGA; затем элаборация двух top и исходного TB.

**Reset и VGA намеренно проверяют воспроизведение известных дефектов.** Успешный выход не означает исправность этих подсистем. Board top и исходный TB проверяются на элаборацию; функциональная проверка нового MIDI UART тракта находится в `tests/midi`.

Reset-тест ускорен `CNT_WIDTH=4`; логика потери lock не меняется. 96013 DDS-сэмплов соответствуют примерно 2 секундам выходного звука, а не времени симуляции при тестовом clk.

`clk_wiz_0_stub.sv` объявляет порты и не моделирует PLL. Здесь нет синтеза, timing/CDC sign-off, стенда или аналогового аудио. SDL не запускался.

После исправлений добавить регрессионные проверки правильного поведения и обновить режимы запуска. Сохранить baseline-логи. Этот скрипт не является достаточным зелёным CI-критерием готовности плеера.

`baseline_logs/audit_results.txt` содержит отдельные сценарии, `audit_build_results.txt` — элаборацию, `audit_reproduction.txt` — повторный прогон. Личные абсолютные пути заменены на `<workspace>`; функциональные результаты сохранены.


MIDI regression: `tb_midi_protocol.sv` проверяет реальные значения MicroLab, running status, каналы, USB-payload и backpressure/ошибки; `tb_usb_midi_voice.sv` проверяет payload→wavetable, частоту A4 и velocity. Это тесты на границе уже полученных данных, не тест USB enumeration, PIC24 или физического J5. Контракт: `doc/MIDI_PROTOCOL.md`.

Keyboard regression: `tests/keyboard/tb_ps2_keyboard_digit.sv` проверяет PS/2 Set-2 цифры 0–9 для верхнего ряда и цифрового блока, а также игнорирование break/extended событий; `tb_sevseg_digit_mask.sv` проверяет отображение только в AN[0] с остальными разрядами погашенными. Это RTL simulation, не замена Vivado implementation или проверки реальной клавиатуры.
