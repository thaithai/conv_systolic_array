module controller #(
    parameter integer size      = 16,
    parameter integer size_bram = 256,
    parameter integer IMG_H     = 16,
    parameter integer IMG_W     = 16,
    parameter integer KH        = 3,
    parameter integer KW        = 3,
    parameter integer STRIDE    = 1,
    parameter integer PAD       = 1
)(
    input  clk,
    input  rst_n,
    input  start,

    // status từ datapath
    input  w_row_done,          // packer weight xong 1 hàng
    input  act_busy,
    input  act_done,
    input  act_empty,
    input  act_full,

    // điều khiển weight packer
    output reg                  w_start_row,   // kick pack 1 hàng weight
    output reg [$clog2(size_bram)-1:0] w_base_addr,
    output reg                  load_weight,   // PE load weight

    // điều khiển act path
    output reg act_start,       // start im2col_fifo
    output reg act_rd,          // đọc FIFO → PE

    // điều khiển output
    output reg                  capture,       // chốt pe_acc → result_reg
    output reg                  o_write,       // ghi o_bram
    output reg [$clog2(size_bram)-1:0] o_addr,
    output reg [$clog2(size)-1:0]      o_sel,  // chọn result_reg[i]

    output reg done
);

    localparam integer ADDR_W = $clog2(size_bram);
    localparam integer OH     = (IMG_H + 2*PAD - KH) / STRIDE + 1;
    localparam integer OW     = (IMG_W + 2*PAD - KW) / STRIDE + 1;

    localparam S_IDLE      = 3'd0;
    localparam S_LOAD_W    = 3'd1;
    localparam S_FILL_ACT  = 3'd2;
    localparam S_COMPUTE   = 3'd3;
    localparam S_PIPE_WAIT = 3'd4;   // chờ psum chảy hết hàng
    localparam S_CAPTURE   = 3'd5;
    localparam S_WRITE_OUT = 3'd6;
    localparam S_DONE      = 3'd7;

    reg [2:0] state;
    reg [$clog2(size):0] w_row;
    reg [$clog2(size):0] pipe_cnt;
    reg [$clog2(size):0] out_idx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            done        <= 1'b0;
            w_start_row <= 1'b0;
            w_base_addr <= {ADDR_W{1'b0}};
            load_weight <= 1'b0;
            act_start   <= 1'b0;
            act_rd      <= 1'b0;
            capture     <= 1'b0;
            o_write     <= 1'b0;
            o_addr      <= {ADDR_W{1'b0}};
            o_sel       <= {($clog2(size)){1'b0}};
            w_row       <= {($clog2(size)+1){1'b0}};
            pipe_cnt    <= {($clog2(size)+1){1'b0}};
            out_idx     <= {($clog2(size)+1){1'b0}};
        end
        else begin
            // default pulses
            w_start_row <= 1'b0;
            load_weight <= 1'b0;
            act_start   <= 1'b0;
            act_rd      <= 1'b0;
            capture     <= 1'b0;
            o_write     <= 1'b0;
            done        <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        w_row       <= {($clog2(size)+1){1'b0}};
                        w_base_addr <= {ADDR_W{1'b0}};
                        w_start_row <= 1'b1;
                        state       <= S_LOAD_W;
                    end
                end

                // Load weight từng hàng vào PE
                S_LOAD_W: begin
                    if (w_row_done) begin
                        load_weight <= 1'b1;
                        if (w_row == size-1) begin
                            act_start <= 1'b1;
                            state     <= S_FILL_ACT;
                        end
                        else begin
                            w_row       <= w_row + 1'b1;
                            w_base_addr <= w_base_addr + size;
                            w_start_row <= 1'b1;
                        end
                    end
                end

                // Chờ im2col đổ FIFO
                S_FILL_ACT: begin
                    if (act_done || (!act_busy && !act_empty))
                        state <= S_COMPUTE;
                end

                // FIFO → PE
                S_COMPUTE: begin
                    if (!act_empty) begin
                        act_rd <= 1'b1;
                    end
                    else if (!act_busy) begin
                        pipe_cnt <= size;   // chờ psum chảy ngang size cycle
                        state    <= S_PIPE_WAIT;
                    end
                end

                S_PIPE_WAIT: begin
                    if (pipe_cnt == 0)
                        state <= S_CAPTURE;
                    else
                        pipe_cnt <= pipe_cnt - 1'b1;
                end

                // Chốt acc
                S_CAPTURE: begin
                    capture <= 1'b1;
                    out_idx <= {($clog2(size)+1){1'b0}};
                    o_addr  <= {ADDR_W{1'b0}};
                    state   <= S_WRITE_OUT;
                end

                // result_reg → output BRAM
                S_WRITE_OUT: begin
                    o_write <= 1'b1;
                    o_sel   <= out_idx[$clog2(size)-1:0];
                    o_addr  <= out_idx[ADDR_W-1:0];

                    if (out_idx == size-1)
                        state <= S_DONE;
                    else
                        out_idx <= out_idx + 1'b1;
                end

                S_DONE: begin
                    done  <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end
endmodule