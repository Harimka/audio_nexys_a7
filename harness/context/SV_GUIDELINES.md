# РУКОВОДСТВО ПО СИНТЕЗИРУЕМОМУ SYSTEMVERILOG ДЛЯ ПЛИС (FPGA)

Этот документ содержит базовые законы и шаблоны написания чистого кода на **SystemVerilog**, который без ошибок и предупреждений синтезируется в **Vivado** для ПЛИС **Xilinx Artix-7** (плата Nexys A7-100T).

---

## 1. Главные законы синтеза в ПЛИС

### Закон 1: Присваивания (`=` против `<=`)
* В последовательностных блоках **`always_ff @(posedge clk)`** — **ТОЛЬКО неблокирующее присваивание (`<=`)**!
* В комбинационных блоках **`always_comb`** и **`assign`** — **ТОЛЬКО блокирующее присваивание (`=`)**!
* **Запрет:** Никогда не используйте `=` внутри `always_ff` и никогда не смешивайте `=` и `<=` для одного сигнала.

### Закон 2: Защита от паразитных защелок (No Latches)
* В `always_comb` сигнал обязан получать значение при любых условиях.
* **Золотой шаблон:** Всегда в первой строчке `always_comb` задавайте значение по умолчанию:
  ```systemverilog
  always_comb begin
      color = 12'h000; // 1. Дефолт на весь экран (фон)
      if (in_box) begin
          color = 12'h0F0; // 2. Перезапись, если попали в окно
      end
  end
  ```
* Каждый оператор `case` обязан содержать ветку `default:`.

### Закон 3: Тактовые сигналы и разрешение такта (Clock Enable)
* **Запрещено:** Делать новый клок из счетчика или логических вентилей (`@(posedge counter[20])`). Это приводит к паразитным задержкам и сбоям синхронизации.
* **Правильно:** Использовать строб разрешения такта (**Clock Enable**):
  ```systemverilog
  always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
          sample <= '0;
      end else if (tick_48khz) begin
          sample <= next_sample;
      end
  end
  ```

### Закон 4: Междоменная передача (CDC)
* В проекте 3 частоты: 100 МГц (`sys_clk`), ~49 МГц (`clk_audio`), 40/50 МГц (`pixel_clk`).
* Сигналы между ними нельзя соединять напрямую проводом.
* Одиночные флаги (1 бит) $\rightarrow$ 2-триггерный синхронизатор (2-FF).
* Шины, сэмплы и графика $\rightarrow$ двухпортовая память **Dual-Port RAM** или асинхронное FIFO.

### Закон 5: Аппаратные ограничения проекта
* **Вывод `AUD_PWM`:** только **`0`** или **`1'bz`** (`assign AUD_PWM = p ? 1'bz : 1'b0;`). Активную `1` выдавать запрещено.
* **MicroBlaze и Block Design:** запрещены условиями хакатона.

---

## 2. Что нельзя писать в коде для ПЛИС (Несинтезируемые конструкции)

Следующие вещи существуют только для симуляторов на ПК и **сломают синтез в Vivado**:
* ❌ Задержки по времени (`#5ns`, `#10`)
* ❌ Динамическое выделение памяти (`new()`, динамические массивы)
* ❌ Классы и виртуальные методы (`class`, `virtual function`) внутри модулей
* ❌ Бесконечные циклы `while(1)` без тактирования
* ❌ Параллельные ветки `fork ... join`

---

## 3. Эталонный шаблон модуля SystemVerilog

```systemverilog
`timescale 1ns / 1ps

module template_module #(
    parameter int DATA_WIDTH = 16
)(
    input  logic                  clk,       // Тактовый сигнал домена
    input  logic                  rst_n,     // Сброс (активный 0)
    
    // Входные сигналы
    input  logic                  enable,
    input  logic [DATA_WIDTH-1:0] data_in,
    
    // Выходные сигналы
    output logic [DATA_WIDTH-1:0] data_out,
    output logic                  valid_out
);

    // 1. Внутренние регистры
    logic [DATA_WIDTH-1:0] data_reg;
    logic                  valid_reg;

    // 2. Логика по такту (Память / Flip-Flops)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_reg  <= '0;
            valid_reg <= 1'b0;
        end else if (enable) begin
            data_reg  <= data_in; // Всегда <=
            valid_reg <= 1'b1;
        end else begin
            valid_reg <= 1'b0;
        end
    end

    // 3. Выходные провода
    assign data_out  = data_reg;
    assign valid_out = valid_reg;

endmodule
```
