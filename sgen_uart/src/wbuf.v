//-----------------------------------------------------------------------------
// Dual-port sample buffer: write port 400 MHz (wave_gen), read port 100 MHz
// (reader -> AXIS->FIFO->DMA). Inferred BRAM, registered read.
//-----------------------------------------------------------------------------
`timescale 1ns / 1ps

module wbuf #(
    parameter AW = 10,          // address width (1024)
    parameter W  = 16
)(
    input  wire           wclk,
    input  wire           we,
    input  wire [AW-1:0]  waddr,
    input  wire [W-1:0]   wdata,

    input  wire           rclk,
    input  wire [AW-1:0]  raddr,
    output reg  [W-1:0]   rdata
);

    reg [W-1:0] mem [0:(1<<AW)-1];

    always @(posedge wclk) begin
        if (we) mem[waddr] <= wdata;
    end

    always @(posedge rclk) begin
        rdata <= mem[raddr];
    end

endmodule