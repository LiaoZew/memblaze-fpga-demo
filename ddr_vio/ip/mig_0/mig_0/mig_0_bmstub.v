// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.
// -------------------------------------------------------------------------------

`timescale 1 ps / 1 ps

(* BLOCK_STUB = "true" *)
module mig_0 (
  sys_rst,
  clk_ref_p,
  clk_ref_n
);

  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 SYSTEM_RESET RST" *)
  (* X_INTERFACE_MODE = "slave SYSTEM_RESET" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME SYSTEM_RESET, POLARITY ACTIVE_LOW, BOARD.ASSOCIATED_PARAM RESET_BOARD_INTERFACE, INSERT_VIP 0" *)
  input sys_rst;
  (* X_INTERFACE_INFO = "xilinx.com:interface:diff_clock:1.0 CLK_REF CLK_P" *)
  (* X_INTERFACE_MODE = "slave CLK_REF" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME CLK_REF, CAN_DEBUG false, FREQ_HZ 100000000" *)
  input clk_ref_p;
  (* X_INTERFACE_INFO = "xilinx.com:interface:diff_clock:1.0 CLK_REF CLK_N" *)
  input clk_ref_n;

  // stub module has no contents

endmodule
