//-----------------------------------------------------------------------------
// 100 MHz reader: streams wbuf[N-1:0] out as AXI-Stream into the AXIS FIFO
// (which feeds the AXI DMA S2MM -> acquisition BRAM -> MicroBlaze).
//
// Pipelined with one-cycle prefetch: raddr = cnt is issued combinational-
// plus-registered, so rdata carries mem[cnt-1] and sample k is presented at
// cnt == k+1. tvalid = running && cnt>0 gives exactly N valid beats.
//-----------------------------------------------------------------------------
`timescale 1ns / 1ps

module reader #(
    parameter N = 1024,
    parameter AW = 10,
    parameter W  = 16
)(
    input  wire           rclk,
    input  wire           rst_n,
    input  wire           enable,        // (re)start streaming
    output wire [AW-1:0]  raddr,
    input  wire [W-1:0]   rdata,

    output wire [W-1:0]   fifo_tdata,
    output wire           fifo_tvalid,
    input  wire           fifo_tready,
    output reg            done            // all N samples streamed
);

    reg [AW:0]   cnt;
    reg         running;
    reg         enable_d;

    always @(posedge rclk or negedge rst_n) begin
        if (!rst_n) begin
            cnt      <= 0;
            running  <= 0;
            done     <= 0;
            enable_d <= 0;
        end else begin
            enable_d <= enable;
            done     <= 0;
            if (enable && !enable_d) begin
                cnt     <= 0;
                running <= 1;
            end
            if (running) begin
                if (fifo_tready && (cnt < N)) cnt <= cnt + 1;
                if (cnt == N) begin
                    running <= 0;
                    done    <= 1;
                end
            end
        end
    end

    assign raddr      = cnt[AW-1:0];   // issue address for the NEXT sample
    assign fifo_tdata = rdata;         // registered read -> mem[cnt-1]
    assign fifo_tvalid= running && (cnt > 0);

endmodule