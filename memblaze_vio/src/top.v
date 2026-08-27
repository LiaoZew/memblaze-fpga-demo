//-----------------------------------------------------------------------------
// MemBlaze FPGA board (xc7k325tffg900-2) - VIO LED demo
//
// A Xilinx VIO (Virtual I/O) core drives the three on-board LEDs.
// Toggle probe_out0/1/2 in the Hardware Manager (hw_vio window) to
// turn LED_G / LED_Y / LED_R on and off.
//
// Pin map derived from MEMBLAZE_PINS_V2.xls and ddr.xdc:
//   sysclk  D27   LVCMOS18  50 MHz single-ended board clock ("CLCK")
//   led_g   R24   LVCMOS18  green  LED
//   led_y   T20   LVCMOS18  yellow LED
//   led_r   T21   LVCMOS18  red    LED
//
// NOTE: LED polarity (active-high vs active-low) is unknown from the
// pin table; these outputs drive the FPGA pin directly. If the LEDs
// light inverted, add an inverter (assign led_x = ~vio_outx).
//-----------------------------------------------------------------------------
`timescale 1ns / 1ps

module memblaze_vio_top (
    input  wire sysclk,   // 50 MHz board clock, D27
    output wire led_g,    // LED_G green , R24
    output wire led_y,    // LED_Y yellow, T20
    output wire led_r     // LED_R red   , T21
);

    wire [0:0] vio_out0;
    wire [0:0] vio_out1;
    wire [0:0] vio_out2;

    vio_0 u_vio (
        .clk        (sysclk),
        .probe_out0 (vio_out0),
        .probe_out1 (vio_out1),
        .probe_out2 (vio_out2)
    );

    assign led_g = vio_out0;
    assign led_y = vio_out1;
    assign led_r = vio_out2;

endmodule