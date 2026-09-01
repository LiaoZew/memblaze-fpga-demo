//-----------------------------------------------------------------------------
// ddr_ctrl: simple app-interface driver for one 72-bit write and one 72-bit
// read, triggered by VIO pulses (wr_en / rd_en).
//   WRITE : drive app_cmd=0/app_addr/app_en until app_rdy, and
//           drive app_wdf_data/app_wdf_wren until app_wdf_rdy
//   READ  : drive app_cmd=1/app_addr/app_en until app_rdy, then wait for
//           app_rd_data_valid
// Reads back data appears on 'rd_data/rd_valid' (latched by the top into VIO).
//-----------------------------------------------------------------------------
module ddr_ctrl (
    input  wire        clk,
    input  wire        rst,
    input  wire        wr_en,
    input  wire        rd_en,
    input  wire [26:0] wr_addr,
    input  wire [26:0] rd_addr,
    input  wire [63:0] wr_data,
    input  wire        app_rdy,
    input  wire        app_wdf_rdy,
    output reg  [2:0]  app_cmd,
    output reg  [26:0] app_addr,
    output reg         app_en,
    output reg  [63:0] app_wdf_data,
    output reg         app_wdf_wren,
    output reg         app_wdf_end,
    input  wire [63:0] rd_data,
    input  wire        rd_valid,
    output reg         busy,
    output reg         done
);

    localparam IDLE = 3'd0, W_CMD = 3'd1, W_DATA = 3'd2, R_CMD = 3'd3,
               R_WAIT = 3'd4, FINISH = 3'd5;
    reg [2:0] st;
    reg wr_en_d, rd_en_d;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            st           <= IDLE;
            app_cmd      <= 0;
            app_addr     <= 0;
            app_en       <= 0;
            app_wdf_data <= 0;
            app_wdf_wren <= 0;
            app_wdf_end  <= 0;
            busy         <= 0;
            done         <= 0;
            wr_en_d      <= 0;
            rd_en_d      <= 0;
        end else begin
            wr_en_d <= wr_en;
            rd_en_d <= rd_en;
            done    <= 0;
            case (st)
                IDLE: begin
                    if (wr_en && !wr_en_d) begin
                        st           <= W_CMD;
                        app_cmd      <= 3'd0;           // WRITE
                        app_addr     <= wr_addr;
                        app_wdf_data <= wr_data;
                        app_en       <= 1;
                        busy         <= 1;
                    end else if (rd_en && !rd_en_d) begin
                        st       <= R_CMD;
                        app_cmd  <= 3'd1;               // READ
                        app_addr <= rd_addr;
                        app_en   <= 1;
                        busy     <= 1;
                    end else begin
                        app_en       <= 0;
                        app_wdf_wren <= 0;
                        app_wdf_end  <= 0;
                    end
                end
                W_CMD: begin
                    app_en <= 1;
                    if (app_rdy) begin
                        app_en <= 0;
                        st     <= W_DATA;
                    end
                end
                W_DATA: begin
                    app_wdf_wren <= 1;
                    app_wdf_end  <= 1;
                    if (app_wdf_rdy) begin
                        app_wdf_wren <= 0;
                        app_wdf_end  <= 0;
                        st           <= FINISH;
                    end
                end
                R_CMD: begin
                    app_en <= 1;
                    if (app_rdy) begin
                        app_en <= 0;
                        st     <= R_WAIT;
                    end
                end
                R_WAIT: begin
                    if (rd_valid) st <= FINISH;
                end
                FINISH: begin
                    busy <= 0;
                    done <= 1;
                    st   <= IDLE;
                end
                default: st <= IDLE;
            endcase
        end
    end

    // unused input kept for symmetry (read data is observed via VIO directly)
    wire [63:0] unused_rd = rd_data;

endmodule