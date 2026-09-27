module systolic_top #(
    parameter integer size       = 16,
    parameter integer bit_width  = 8,
    parameter integer acc_width  = 32,
    parameter integer size_bram  = 256,
    parameter integer FIFO_DEPTH = 16,
    parameter integer IMG_H      = 16,
    parameter integer IMG_W      = 16,
    parameter integer CHANNELS   = 1,
    parameter integer KH         = 3,
    parameter integer KW         = 3,
    parameter integer STRIDE     = 1,
    parameter integer PAD        = 1
)(
    input  clk,
    input  rst_n,
    input  start,
    output done
);

    localparam integer VEC_W   = bit_width * size;
    localparam integer ACC_VEC = acc_width * size;
    localparam integer ADDR_W  = $clog2(size_bram);

    // ---------- control wires ----------
    wire                  w_start_row, w_row_done, load_weight;
    wire [ADDR_W-1:0]     w_base_addr;
    wire                  act_start, act_rd;
    wire                  act_busy, act_done, act_empty, act_full;
    wire                  capture, o_write;
    wire [ADDR_W-1:0]     o_addr;
    wire [$clog2(size)-1:0] o_sel;

    // ---------- BRAM wires ----------
    wire                  w_read, a_read;
    wire [ADDR_W-1:0]     w_addr, a_addr;
    wire [bit_width-1:0]  w_dout, a_dout;
    wire [acc_width-1:0]  o_dout;

    // ---------- data path ----------
    wire [VEC_W-1:0]   pe_weight, pe_data;
    wire [ACC_VEC-1:0] pe_acc;

    reg  [acc_width-1:0] result_reg [0:size-1];
    reg  [acc_width-1:0] o_din;
    integer ri;

    // ============================================================
    // BRAMs
    // ============================================================
    bram #(.bit_width(bit_width), .size_bram(size_bram)) w_bram (
        .clk(clk), .rst_n(rst_n),
        .read(w_read), .write(1'b0),
        .data_in({bit_width{1'b0}}),
        .address(w_addr), .data_out(w_dout)
    );

    bram #(.bit_width(bit_width), .size_bram(size_bram)) a_bram (
        .clk(clk), .rst_n(rst_n),
        .read(a_read), .write(1'b0),
        .data_in({bit_width{1'b0}}),
        .address(a_addr), .data_out(a_dout)
    );

    bram #(.bit_width(acc_width), .size_bram(size_bram)) o_bram (
        .clk(clk), .rst_n(rst_n),
        .read(1'b0), .write(o_write),
        .data_in(o_din),
        .address(o_addr), .data_out(o_dout)
    );

    // ============================================================
    // Weight packer
    // ============================================================
    weight_packer #(
        .bit_width(bit_width), .size(size), .size_bram(size_bram)
    ) u_wpack (
        .clk(clk), .rst_n(rst_n),
        .start_row (w_start_row),
        .base_addr (w_base_addr),
        .bram_read (w_read),
        .bram_addr (w_addr),
        .bram_data (w_dout),
        .weight_vec(pe_weight),
        .row_done  (w_row_done)
    );

    // ============================================================
    // Act: im2col + FIFO
    // ============================================================
    im2col_fifo #(
        .bit_width(bit_width), .size(size), .size_bram(size_bram),
        .DEPTH(FIFO_DEPTH),
        .IMG_H(IMG_H), .IMG_W(IMG_W), .CHANNELS(CHANNELS),
        .KH(KH), .KW(KW), .STRIDE(STRIDE), .PAD(PAD)
    ) u_act (
        .clk(clk), .rst_n(rst_n),
        .start(act_start), .rd_en(act_rd),
        .bram_read(a_read), .bram_addr(a_addr), .bram_data(a_dout),
        .dout(pe_data),
        .full(act_full), .empty(act_empty),
        .busy(act_busy), .done(act_done)
    );

    // ============================================================
    // PE array
    // ============================================================
    MAC_array #(
        .size(size), .bit_width(bit_width), .acc_width(acc_width)
    ) u_array (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load_weight),
        .weight_in(pe_weight),
        .data_in(pe_data),
        .acc_out(pe_acc)
    );

    // ============================================================
    // Result registers + output mux
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (ri = 0; ri < size; ri = ri + 1)
                result_reg[ri] <= {acc_width{1'b0}};
            o_din <= {acc_width{1'b0}};
        end
        else begin
            if (capture) begin
                for (ri = 0; ri < size; ri = ri + 1)
                    result_reg[ri] <= pe_acc[acc_width*(ri+1)-1 : acc_width*ri];
            end
            o_din <= result_reg[o_sel];
        end
    end

    // ============================================================
    // Controller
    // ============================================================
    controller #(
        .size(size), .size_bram(size_bram),
        .IMG_H(IMG_H), .IMG_W(IMG_W),
        .KH(KH), .KW(KW), .STRIDE(STRIDE), .PAD(PAD)
    ) u_ctrl (
        .clk(clk), .rst_n(rst_n), .start(start),
        .w_row_done (w_row_done),
        .act_busy   (act_busy),
        .act_done   (act_done),
        .act_empty  (act_empty),
        .act_full   (act_full),
        .w_start_row(w_start_row),
        .w_base_addr(w_base_addr),
        .load_weight(load_weight),
        .act_start  (act_start),
        .act_rd     (act_rd),
        .capture    (capture),
        .o_write    (o_write),
        .o_addr     (o_addr),
        .o_sel      (o_sel),
        .done       (done)
    );

endmodule