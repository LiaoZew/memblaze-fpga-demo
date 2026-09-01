//-----------------------------------------------------------------------------
// 400 MHz waveform generator: sine / ramp, 16-bit samples
// Writes N samples into the shared wbuf (write port, 400 MHz clock domain).
//   en    : run when 1 (already synchronized into this clock domain)
//   sel   : 0 = sine, 1 = ramp
//   start : 1 -> (re)start filling from sample 0
//   done  : pulse when all N samples are written
//-----------------------------------------------------------------------------
`timescale 1ns / 1ps

module wave_gen #(
    parameter N = 1024,        // sample count
    parameter AW = 10,         // wbuf address width (1024)
    parameter W  = 16          // sample width
)(
    input  wire           clk,      // 400 MHz
    input  wire           rst_n,
    input  wire           en,
    input  wire           sel,
    input  wire           start,
    output reg            done,
    output reg            wr_en,
    output reg [AW-1:0]   wr_addr,
    output reg [W-1:0]    wr_data
);

    // 32-point sine LUT as a function (plain Verilog)
    function [W-1:0] sin16;
        input [4:0] i;
        begin
            case (i)
                5'd0  : sin16 = 16'd0;
                5'd1  : sin16 = 16'sd3212;
                5'd2  : sin16 = 16'sd6393;
                5'd3  : sin16 = 16'sd9512;
                5'd4  : sin16 = 16'sd12539;
                5'd5  : sin16 = 16'sd15446;
                5'd6  : sin16 = 16'sd18204;
                5'd7  : sin16 = 16'sd20787;
                5'd8  : sin16 = 16'sd23170;
                5'd9  : sin16 = 16'sd25329;
                5'd10 : sin16 = 16'sd27245;
                5'd11 : sin16 = 16'sd28898;
                5'd12 : sin16 = 16'sd30273;
                5'd13 : sin16 = 16'sd31356;
                5'd14 : sin16 = 16'sd32137;
                5'd15 : sin16 = 16'sd32609;
                5'd16 : sin16 = 16'sd32767;
                5'd17 : sin16 = 16'sd32609;
                5'd18 : sin16 = 16'sd32137;
                5'd19 : sin16 = 16'sd31356;
                5'd20 : sin16 = 16'sd30273;
                5'd21 : sin16 = 16'sd28898;
                5'd22 : sin16 = 16'sd27245;
                5'd23 : sin16 = 16'sd25329;
                5'd24 : sin16 = 16'sd23170;
                5'd25 : sin16 = 16'sd20787;
                5'd26 : sin16 = 16'sd18204;
                5'd27 : sin16 = 16'sd15446;
                5'd28 : sin16 = 16'sd12539;
                5'd29 : sin16 = 16'sd9512;
                5'd30 : sin16 = 16'sd6393;
                default: sin16 = 16'sd3212;
            endcase
        end
    endfunction

    reg [AW:0]   idx;          // 0..N
    reg         run;
    reg         start_d;       // edge detect (start already sync'd, same clock)

    wire [4:0]        lut_addr = idx[AW-1:5];       // 1024 -> 32 steps (32 pts each)
    wire [W-1:0]      sine_val = sin16(lut_addr);
    wire [W-1:0]      ramp_val = idx[AW-1:0] << 6;  // 0..65472

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idx      <= 0;
            run      <= 0;
            done     <= 0;
            wr_en    <= 0;
            wr_addr  <= 0;
            wr_data  <= 0;
        end else begin
            start_d   <= start;
            done      <= 0;
            if (en && start && !start_d) run <= 1;   // rising edge (re)start
            if (run) begin
                if (idx < N) begin
                    wr_en   <= 1;
                    wr_addr <= idx[AW-1:0];
                    wr_data <= sel ? ramp_val : sine_val;
                    idx     <= idx + 1;
                end else begin
                    wr_en <= 0;
                    run   <= 0;
                    done  <= 1;
                    idx   <= 0;
                end
            end else begin
                wr_en <= 0;
            end
        end
    end

endmodule