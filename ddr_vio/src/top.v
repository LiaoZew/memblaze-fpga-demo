//-----------------------------------------------------------------------------
// ddr_vio: PL-only DDR3 read/write controlled by a Xilinx VIO.
//
//   VIO (clocked by ui_clk from MIG):
//     probe_out0[0]   rst          (1 = reset MIG sys_rst)
//     probe_out1[0]   wr_en        (rising edge -> one 72-bit write)
//     probe_out2[0]   rd_en        (rising edge -> one 72-bit read)
//     probe_out3[26:0] wr_addr     (app address: {bank,row,column} mapping)
//     probe_out4[26:0] rd_addr
//     probe_out5[71:0] wr_data
//     probe_out6[0]   (unused)
//   probe_in:
//     0 init_calib_done  1 app_rdy  2 app_wdf_rdy
//     3 rd_valid         4 rd_data[71:0]  5 busy  6 done
//     7 rst echo
//
// DDR pins are declared here and constrained by
// board_reference/ddr3_72bit_converted.xdc.
//-----------------------------------------------------------------------------
`timescale 1ns / 1ps

module ddr_vio_top (
    input  wire        sys_clk_i,     // 50 MHz board clock D27
    output wire [15:0] ddr3_addr,
    output wire [2:0]  ddr3_ba,
    output wire        ddr3_cas_n,
    output wire [0:0]  ddr3_ck_n,
    output wire [0:0]  ddr3_ck_p,
    output wire [0:0]  ddr3_cke,
    output wire        ddr3_ras_n,
    output wire        ddr3_reset_n,
    output wire        ddr3_we_n,
    inout  wire [71:0] ddr3_dq,
    inout  wire [8:0]  ddr3_dqs_n,
    inout  wire [8:0]  ddr3_dqs_p,
    output wire [8:0]  ddr3_dm,
    output wire [0:0]  ddr3_odt,
    output wire [0:0]  ddr3_cs_n
);

    // ---- MIG signals ------------------------------------------------------
    wire        sys_rst;
    wire        clk_ref_i   = 1'b0;    // internal ref clock (no external pin)
    wire        ui_clk;
    wire        ui_clk_sync_rst;
    wire        init_calib_complete;
    wire        app_rdy;
    wire        app_wdf_rdy;
    wire [2:0]  app_cmd;
    wire [26:0] app_addr;
    wire        app_en;
    wire [71:0] app_wdf_data;
    wire        app_wdf_wren;
    wire        app_wdf_end;
    wire [71:0] app_rd_data;
    wire        app_rd_data_end;
    wire        app_rd_data_valid;

    // ---- VIO ---------------------------------------------------------------
    wire [0:0]  v_rst, v_wr_en, v_rd_en;
    wire [26:0] v_wr_addr, v_rd_addr;
    wire [71:0] v_wr_data;
    wire [0:0]  s_init, s_rdy, s_wdf_rdy, s_rd_vld, s_busy, s_done, s_echo;

    vio_0 u_vio (
        .clk        (ui_clk),
        .probe_out0 (v_rst),
        .probe_out1 (v_wr_en),
        .probe_out2 (v_rd_en),
        .probe_out3 (v_wr_addr),
        .probe_out4 (v_rd_addr),
        .probe_out5 (v_wr_data),
        .probe_out6 (v_rst),
        .probe_in0  (s_init),
        .probe_in1  (s_rdy),
        .probe_in2  (s_wdf_rdy),
        .probe_in3  (s_rd_vld),
        .probe_in4  (s_rd_data),
        .probe_in5  (s_busy),
        .probe_in6  (s_done),
        .probe_in7  (s_echo)
    );
    assign s_init    = init_calib_complete;
    assign s_rdy     = app_rdy;
    assign s_wdf_rdy = app_wdf_rdy;
    assign s_rd_vld  = app_rd_data_valid;
    assign s_rd_data = app_rd_data;
    assign s_echo    = v_rst;

    // ---- MIG core ----------------------------------------------------------
    mig_0 u_mig (
        .sys_clk_i            (sys_clk_i),
        .clk_ref_i            (clk_ref_i),
        .sys_rst              (sys_rst),
        .ui_clk               (ui_clk),
        .ui_clk_sync_rst      (ui_clk_sync_rst),
        .init_calib_complete  (init_calib_complete),
        .app_addr             (app_addr),
        .app_cmd              (app_cmd),
        .app_en               (app_en),
        .app_wdf_data         (app_wdf_data),
        .app_wdf_end          (app_wdf_end),
        .app_wdf_wren         (app_wdf_wren),
        .app_rd_data          (app_rd_data),
        .app_rd_data_end      (app_rd_data_end),
        .app_rd_data_valid    (app_rd_data_valid),
        .app_rdy              (app_rdy),
        .app_wdf_rdy          (app_wdf_rdy),
        .ddr3_addr            (ddr3_addr),
        .ddr3_ba              (ddr3_ba),
        .ddr3_cas_n           (ddr3_cas_n),
        .ddr3_ck_n            (ddr3_ck_n),
        .ddr3_ck_p            (ddr3_ck_p),
        .ddr3_cke             (ddr3_cke),
        .ddr3_ras_n           (ddr3_ras_n),
        .ddr3_reset_n         (ddr3_reset_n),
        .ddr3_we_n            (ddr3_we_n),
        .ddr3_dq              (ddr3_dq),
        .ddr3_dqs_n           (ddr3_dqs_n),
        .ddr3_dqs_p           (ddr3_dqs_p),
        .ddr3_dm              (ddr3_dm),
        .ddr3_odt             (ddr3_odt),
        .ddr3_cs_n            (ddr3_cs_n)
    );

    // ---- app 手动控制状态机 ------------------------------------------------
    wire [71:0] wr_data_used = v_wr_data;
    assign sys_rst = v_rst[0];

    ddr_ctrl u_ctrl (
        .clk          (ui_clk),
        .rst          (ui_clk_sync_rst | v_rst[0]),
        .wr_en        (v_wr_en[0]),
        .rd_en        (v_rd_en[0]),
        .wr_addr      (v_wr_addr),
        .rd_addr      (v_rd_addr),
        .wr_data      (wr_data_used),
        .app_rdy      (app_rdy),
        .app_wdf_rdy  (app_wdf_rdy),
        .app_cmd      (app_cmd),
        .app_addr     (app_addr),
        .app_en       (app_en),
        .app_wdf_data (app_wdf_data),
        .app_wdf_wren (app_wdf_wren),
        .app_wdf_end  (app_wdf_end),
        .rd_data      (app_rd_data),
        .rd_valid     (app_rd_data_valid),
        .busy         (s_busy[0]),
        .done         (s_done[0])
    );

endmodule