//-----------------------------------------------------------------------------
// sgen_uart top: MicroBlaze block design (system_wrapper) + custom 400 MHz
// waveform engine (sine/ramp, 16-bit) -> dual-port wbuf ->
//
//   system_wrapper
//     .sysclk   : 50 MHz board clock (D27)
//     .wgen_clk : 400 MHz (clk_wiz clk_out2, to wave_gen)
//     .clk_100  : 100 MHz (clk_wiz clk_out1, MicroBlaze/AXI domain)
//     .ctrl[3:0]: axi_gpio ch1 out: [0]wave_en [1]wave_sel [2]wave_start
//                                       [3]rd_en (reader)
//     .sts[1:0] : axi_gpio ch2 in: [0]wave_done [1]rd_done
//     .s_axis   : 32-bit AXIS slave (reader -> FIFO -> DMA S2MM -> acq BRAM)
//
// Data flow: wave_gen(400M) -> wbuf -> reader(100M) -> FIFO -> DMA ->
//            acq BRAM -> MicroBlaze -> JTAG UART -> PC (visualized)
//-----------------------------------------------------------------------------
`timescale 1ns / 1ps

module sgen_uart_top (
    input  wire sysclk          // 50 MHz board clock, D27
);

    // ---- system_wrapper (MicroBlaze BD) ----
    wire        wgen_clk;       // 400 MHz
    wire        clk_100;        // 100 MHz
    wire [3:0]  ctrl;           // from axi_gpio ch1
    wire [1:0]  sts;            // to axi_gpio ch2
    wire [31:0] s_axis_tdata;   // 32-bit AXIS (sample in [15:0], upper zero)
    wire        s_axis_tvalid;
    wire        s_axis_tready;

    system_wrapper u_sys (
        .sysclk         (sysclk),
        .wgen_clk       (wgen_clk),
        .clk_100        (clk_100),
        .ctrl           (ctrl),
        .sts            (sts),
        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready)
    );

    // ---- waveform generation (400 MHz domain) ----
    // synchronizers: ctrl (100M) -> 400M
    reg [3:0] ctrl_s1, ctrl_s2;
    always @(posedge wgen_clk) begin
        ctrl_s1 <= ctrl;
        ctrl_s2 <= ctrl_s1;
    end

    wire        wr_en;
    wire [9:0]  wr_addr;
    wire [15:0] wr_data;
    wire        w_done;

    wave_gen #(.N(1024), .AW(10), .W(16)) u_wavegen (
        .clk     (wgen_clk),
        .rst_n   (1'b1),
        .en      (ctrl_s2[0]),
        .sel     (ctrl_s2[1]),
        .start   (ctrl_s2[2]),
        .done    (w_done),
        .wr_en   (wr_en),
        .wr_addr (wr_addr),
        .wr_data (wr_data)
    );

    // ---- dual-port sample buffer (write 400M / read 100M) ----
    wire [15:0] rd_rdata;
    wire [9:0]  rd_raddr;
    wbuf #(.AW(10), .W(16)) u_wbuf (
        .wclk  (wgen_clk),
        .we    (wr_en),
        .waddr (wr_addr),
        .wdata (wr_data),
        .rclk  (clk_100),
        .raddr (rd_raddr),
        .rdata (rd_rdata)
    );

    // ---- 100 MHz stream-out (BRAM -> AXIS(32b) -> FIFO -> DMA) ----
    wire [15:0] s_axis_tdata16;
    wire        s_axis_tvalid16;
    wire        rd_done;

    reader #(.N(1024), .AW(10), .W(16)) u_reader (
        .rclk        (clk_100),
        .rst_n       (1'b1),
        .enable      (ctrl[3]),          // rd_en (100M domain)
        .raddr       (rd_raddr),
        .rdata       (rd_rdata),
        .fifo_tdata  (s_axis_tdata16),
        .fifo_tvalid (s_axis_tvalid16),
        .fifo_tready (s_axis_tready),
        .done        (rd_done)
    );

    // sample in the low 16 bits of the 32-bit AXIS word
    assign s_axis_tdata  = {16'd0, s_axis_tdata16};
    assign s_axis_tvalid = s_axis_tvalid16;

    // ---- 400M -> 100M status synchronizers ----
    reg w_done_s1, w_done_s2, rd_done_s1, rd_done_s2;
    always @(posedge clk_100) begin
        w_done_s1 <= w_done;
        w_done_s2 <= w_done_s1;
        rd_done_s1 <= rd_done;
        rd_done_s2 <= rd_done_s1;
    end
    assign sts[0] = w_done_s2;    // wave generator done
    assign sts[1] = rd_done_s2;   // reader done

endmodule