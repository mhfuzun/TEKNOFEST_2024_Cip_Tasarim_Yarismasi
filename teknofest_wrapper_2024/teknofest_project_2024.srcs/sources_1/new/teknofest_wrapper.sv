`timescale 1ns / 1ps
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Company:     TUBITAK - TUTEL
// Project:     TEKNOFEST CIP TASARIM YARISMASI
// Engineer:    -
// Version:     1.0
//*************************************************************************************************************************************************//
// Create Date: 
// Module Name: teknofest_wrapper
//
// Description: 
//
// Düzenlemeler: 
//  * (23/08/2024) - x
//      - SRAM boyut kontrolü için SRAM_MEM_SIZE_KB ve SRAM_MEM_DEPTH eklendi
//      - <u_programmer> modülü için uygun clock ve reset sinyalleri atandı
//      - Çekirdek - bellek arayüzü pinleri için yorumlar eklendi
//  
//
//*************************************************************************************************************************************************//
// Copyright 2024 TUTEL (IC Design and Training Laboratory - TUBITAK).
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


module teknofest_wrapper #(
    parameter USE_SRAM  = 0,
    parameter FAST_BOOT  = 0,
    parameter DDR_FREQ_HZ = 300_000_000,
    parameter UART_BAUD_RATE = 9600,
    parameter SRAM_MEM_SIZE_KB = 128,
    parameter SRAM_MEM_DEPTH = (SRAM_MEM_SIZE_KB*64) //(DEPTH = (TOTAL*1024*8)/128) => DEPTH = TOTAL_KB * 64
)(
    // Related to DDR MIG
    input logic sys_rst_n,
    input logic sys_clk, // TODO: SRAM kullanırken bunu cpu clock olarak kullan, yoksa DDR ui_clk
                        // DDR2 için 200Mhz (5ns period) clock bağlanır
    
    inout  [15:0] ddr2_dq,
    inout  [1:0]  ddr2_dqs_n,
    inout  [1:0]  ddr2_dqs_p,
    output [12:0] ddr2_addr,
    output [2:0]  ddr2_ba,
    output        ddr2_ras_n,
    output        ddr2_cas_n,
    output        ddr2_we_n,
    output        ddr2_reset_n, // ? I/O hatası vermekte
    output        ddr2_ck_p,
    output        ddr2_ck_n,
    output        ddr2_cke,
    output        ddr2_cs_n,
    inout  [1:0]  ddr2_dm,
    output        ddr2_odt
);

    localparam CPU_FREQ_HZ = (USE_SRAM) ? DDR_FREQ_HZ : (DDR_FREQ_HZ / 4); // MIG is configured 1:4

    typedef struct packed {
        logic         req;
        logic         gnt;
        logic         we;
        logic [31:0]  addr;
        logic [127:0] wdata;
        logic [15:0]  wstrb;
        logic [127:0] rdata;
        logic         rvalid;
    } mem_t;
    
    mem_t core_mem, programmer_mem, sel_mem;
    
    logic system_reset_n;
    logic programmer_active;
    logic ui_clk, ui_rst_n;
    
    wire core_clk = USE_SRAM ? sys_clk : ui_clk;

    wire core_rst_n = (FAST_BOOT | system_reset_n) && (USE_SRAM ? sys_rst_n : ui_rst_n);
    wire prog_rst_n = (USE_SRAM ? sys_rst_n : ui_rst_n);
    
    /////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////
    // Core'u burada cagirin. core_mem struct'?n? ba?lay?n.
    // core_clk ve core_rst_n sinyallerini baglamayi unutmayin.
    //      UART      //
    assign core_mem.req = 1'b0;             // -> okuma yazma isteği (core_mem.gnt = 1) olana kadar HIGH tutulur
    // core_mem.gnt                         // -> öncelikli olarak yazma, yoksa okuma isteğinin alındığı HIGH ile gösterilir
    assign core_mem.we = 1'b0;              // -> Yazma için açık tutulur (yazma yalnız (core_mem.req & core_mem.we & core_mem.gnt) anında gerçekleşir)
    assign core_mem.addr = 32'd0;           // -> okuma/yazma adresi
    assign core_mem.wdata = 128'h0;         // -> yazılacak veri
    assign core_mem.wstrb = 16'hFFFF;       // -> yazılacak veri için maske
    // core_mem.rdata                       // -> okunan veri
    // core_mem.rvalid                      // -> okuma isteği sonuçlandı sinyali (core_mem.rdata'nın geçerli olduğu zaman)
    /////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////
    
    programmer #(
        .UART_BAUD_RATE(UART_BAUD_RATE),
        .CPU_FREQ_HZ   (CPU_FREQ_HZ)
    )u_programmer (
        /*
            CPU_FREQ_HZ parametresi için uygun clock sinyali <core_clk>'dur.
            Çekirdekten ve programcı modülünden gelen yazma istekleri DDR yapısına seçildiği için 
            300Mhz DDR sinyali <sys_clk> imp. esnasında  çekirdekte gecikmelere sebep olmaktadır.
        */
        .clk                    (core_clk),
        /*
            core_rst_n sinyalinin yükleri arasında bu modülün çıktısı vardır (system_reset_n)
            bu yüzden daima resetleme durumunda kalır.

            sys_rst_n sinyali sram yerine ddr kullanıldığında PLL'e bağlı olduğu için
            PLL'den gelen core_clk sinyali ile kullanılması doğru değildir.
        */
        .rst_n                  (prog_rst_n),

        .mem_req                (programmer_mem.req),
        .mem_we                 (programmer_mem.we),
        .mem_gnt                (programmer_mem.gnt),
        .mem_addr               (programmer_mem.addr),
        .mem_wdata              (programmer_mem.wdata),
        .mem_wstrb              (programmer_mem.wstrb),
        .ram_prog_rx_i          (ram_prog_rx_i),
        .system_reset_no        (system_reset_n),
        .programming_active     (                 ),
        .programming_state_on   (programmer_active)
    );
    
    assign sel_mem.req   = programmer_active ? programmer_mem.req   : core_mem.req;
    assign sel_mem.we    = programmer_active ? programmer_mem.we    : core_mem.we;
    assign sel_mem.addr  = programmer_active ? programmer_mem.addr  : core_mem.addr;
    assign sel_mem.wdata = programmer_active ? programmer_mem.wdata : core_mem.wdata;
    assign sel_mem.wstrb = programmer_active ? programmer_mem.wstrb : core_mem.wstrb;
    
    assign programmer_mem.rvalid = 1'b0;
    assign programmer_mem.rdata  = '0;
    assign programmer_mem.gnt    = programmer_active && sel_mem.gnt;
    
    assign core_mem.rvalid = ~programmer_active && sel_mem.rvalid;
    assign core_mem.rdata  = {128{~programmer_active}} & sel_mem.rdata;
    assign core_mem.gnt    = ~programmer_active && sel_mem.gnt; // eski hali: programmer_active && sel_mem.gnt
    
    
    teknofest_memory #(
        .USE_SRAM   (USE_SRAM),
        .MEM_DEPTH  (SRAM_MEM_DEPTH)
    )u_teknofest_memory(
        .clk_i  (sys_clk),
        .rst_ni (sys_rst_n),
        .req    (sel_mem.req   ),
        .gnt    (sel_mem.gnt   ),
        .we     (sel_mem.we    ),
        .addr   (sel_mem.addr  ),
        .wdata  (sel_mem.wdata ),
        .wstrb  (sel_mem.wstrb ),
        .rdata  (sel_mem.rdata ),
        .rvalid (sel_mem.rvalid),
        .sys_rst (sys_rst_n),
        .sys_clk,
        .ui_clk,
        .ui_rst_n,
        .ddr2_dq,     
        .ddr2_dqs_n,  
        .ddr2_dqs_p,  
        .ddr2_addr,   
        .ddr2_ba,     
        .ddr2_ras_n,  
        .ddr2_cas_n,  
        .ddr2_we_n,   
        .ddr2_reset_n,
        .ddr2_ck_p,   
        .ddr2_ck_n,   
        .ddr2_cke,    
        .ddr2_cs_n,   
        .ddr2_dm,     
        .ddr2_odt     
    );
    
    
   

endmodule
