`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 16.05.2024 10:08:31
// Design Name: 
// Module Name: tb_teknofest_wrapper
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
// Düzenlemeler: 
//  * (23/08/2024) - x
//      - hızlı yükleme işlemleri için FAST_BOOT seçeneği eklendi (UART programlama PASIF hale getirilir)
//      - anlaşılır olması için USER_CLOCK_FREQ_HZ, USER_CLOCK_PERIOD, PROGRAMMER_BAUDE_DIV parametleri eklendi
//      - sys_clk sinyali SRAM veya DDR ile çalışabilmesi için USE_SRAM ile seçim eklendi
//////////////////////////////////////////////////////////////////////////////////

module tb_teknofest_wrapper #(
    parameter int unsigned USE_SRAM = 0,
    parameter int unsigned FAST_BOOT = 0,
    parameter int unsigned SRAM_MEM_SIZE_KB = 128,
    parameter UART_BAUD_RATE = 750000,
    parameter DDR_FREQ_HZ = 300_000_000
)();

localparam USER_CLOCK_FREQ_HZ = (USE_SRAM) ? DDR_FREQ_HZ : (DDR_FREQ_HZ/4); // SRAM kullanıldığında FPGA clock doğrudan kullanılır, aksi halde DDR'a ait PLL clock'u kullanılır (4:1 oranı ile)
localparam USER_CLOCK_PERIOD = 10**9 / USER_CLOCK_FREQ_HZ; // SRAM kullanılmadığında PLL çıkışı clock'a ait sinyalin periodu hesaplanır, aksi halde FPGA clock'un periodu. 
localparam PROGRAMMER_BAUDE_DIV = (USER_CLOCK_FREQ_HZ / UART_BAUD_RATE) - 1;

logic sys_rst_n, sys_clk;
logic ram_prog_rx_i;

wire [15:0] ddr2_dq;
wire [1:0]  ddr2_dqs_n;
wire [1:0]  ddr2_dqs_p;
wire [12:0] ddr2_addr;
wire [2:0]  ddr2_ba;
wire        ddr2_ras_n;
wire        ddr2_cas_n;
wire        ddr2_we_n;
wire        ddr2_reset_n;
wire        ddr2_ck_p;
wire        ddr2_ck_n;
wire        ddr2_cke;
wire        ddr2_cs_n;
wire [1:0]  ddr2_dm;
wire        ddr2_odt;
    
localparam CLKIN_PERIOD = (USE_SRAM) ? 
    USER_CLOCK_PERIOD /* FPGA clock*/: 
    4.999/*200MHz DDR freq*/;
localparam RESET_PERIOD = 200; //in pSec 

teknofest_wrapper #(
    .USE_SRAM      (USE_SRAM),
    .FAST_BOOT     (FAST_BOOT),
    .UART_BAUD_RATE(UART_BAUD_RATE),
    .DDR_FREQ_HZ   (DDR_FREQ_HZ),
    .SRAM_MEM_SIZE_KB   (SRAM_MEM_SIZE_KB)
)u_dut(.*);

initial begin
    sys_rst_n = 1'b0;
    #RESET_PERIOD
    sys_rst_n = 1'b1;
end

initial
    sys_clk = 1'b0;
always
    sys_clk = #(CLKIN_PERIOD/2.0) ~sys_clk;
    
genvar i;
generate
    for(i=0; i<1; i=i+1) begin: gen_dram
        ddr2_model u_comp_ddr2
        (
           .ck      (ddr2_ck_p),
           .ck_n    (ddr2_ck_n),
           .cke     (ddr2_cke),
           .cs_n    (ddr2_cs_n),
           .ras_n   (ddr2_ras_n),
           .cas_n   (ddr2_cas_n),
           .we_n    (ddr2_we_n),
           .dm_rdqs (ddr2_dm[2*(i+1)-1:2*(i)]),
           .ba      (ddr2_ba),
           .addr    (ddr2_addr),
           .dq      (ddr2_dq[16*(i+1)-1:16*(i)]),
           .dqs     (ddr2_dqs_p[2*(i+1)-1:2*(i)]),
           .dqs_n   (ddr2_dqs_n[2*(i+1)-1:2*(i)]),
           .rdqs_n  (),
           .odt     (ddr2_odt)
        );
    end
endgenerate

localparam c_BIT_PERIOD      = PROGRAMMER_BAUDE_DIV * USER_CLOCK_PERIOD;

localparam ProgSize     = 4; // Number of 32 bits (4'ün katı olmalı)
logic [31:0] boot_program [ProgSize-1:0];

initial begin
  for(int i=0; i<ProgSize; i++) boot_program[i] = 32'(i);

  // dizinden memory dosyasının boot alanına yüklenmesi
  $readmemh(".\memfile.mem", boot_program);

  /*
    * UART beklenmeden programın yürütülmesine başlanır.
    * PROGRAMMER modülünün çekirdek üzerindeki reset anahtarı
    FAST_BOOT = 1 yapıldığında <teknofest_wrapper> modülü içerisinde kaldırılır.
  */
    if (FAST_BOOT == 1)
        for(int i=0; i<ProgSize; i+=4) u_dut.u_teknofest_memory.memory[i/4][127 : 0] = 
              {boot_program[i+3], boot_program[i+2], boot_program[i+1], boot_program[i]};
  end


    task send_uart_data;
        input [7:0] i_Data;
        integer     ii;
        begin
          // Send Start Bit
          ram_prog_rx_i = 1'b0;
          #(c_BIT_PERIOD);
          //#1000;
          
          // Send Data Byte
          for (ii=0; ii<8; ii=ii+1)
            begin
              ram_prog_rx_i = i_Data[ii];
              #(c_BIT_PERIOD);
            end
          
          // Send Stop Bit
          ram_prog_rx_i = 1'b1;
          #(c_BIT_PERIOD);
          //$display("[%0t] Sent byte: 0x%x", $realtime, i_Data);
         end
      endtask // UART_WRITE_BYTE

task send_prog_seq();
    $display("%0t Entering", $realtime);
    send_uart_data(.i_Data("T"));
    send_uart_data(.i_Data("E"));
    send_uart_data(.i_Data("K"));
    send_uart_data(.i_Data("N"));
    send_uart_data(.i_Data("O"));
    send_uart_data(.i_Data("F"));
    send_uart_data(.i_Data("E"));
    send_uart_data(.i_Data("S"));
    send_uart_data(.i_Data("T"));
  endtask
  
  task send32(input logic [31:0] datain);
    send_uart_data(datain[31:24]);
    send_uart_data(datain[23:16]);
    send_uart_data(datain[15:8]);
    send_uart_data(datain[7:0]);
  endtask
 
  
  task send_program();
    int i;
    logic [31:0] instr;
    send32(ProgSize);
    repeat(ProgSize) begin
      instr = boot_program[i];
      send32(instr);
      i = i+1;
    end
  endtask 
  
  initial begin
    ram_prog_rx_i = 1'b1;
    if (FAST_BOOT == 0) begin
      if(USE_SRAM == 0) begin
          @(posedge u_dut.u_teknofest_memory.init_calib_complete);
      end else
          #1000ns;

      $display("Starting to write instructions to DDR");
      send_prog_seq();
      send_program();
      $display("Program Yüklendi.");
    end
  end
  
 
    
    
endmodule
