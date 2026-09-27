module im2col_fifo #(
    parameter integer bit_width  = 8,
    parameter integer size       = 16,      // bề rộng vector = size * bit_width
    parameter integer size_bram  = 256,
    parameter integer DEPTH      = 16,      // độ sâu FIFO
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

    // điều khiển
    input  start,                 // bắt đầu im2col → ghi FIFO
    input  rd_en,                 // PE đọc 1 vector / chu kỳ

    // BRAM ifmap (1-cycle read latency)
    output reg                         bram_read,
    output reg [$clog2(size_bram)-1:0] bram_addr,
    input      [bit_width-1:0]         bram_data,

    // ra PE array
    output reg [bit_width*size-1:0] dout,   // = data_in của MAC_array
    output                          full,
    output                          empty,
    output reg                      busy,
    output reg                      done
);

    // ============================================================
    // Localparams
    // ============================================================
    localparam integer DATA_WIDTH = bit_width * size;
    localparam integer OH         = (IMG_H + 2*PAD - KH) / STRIDE + 1;
    localparam integer OW         = (IMG_W + 2*PAD - KW) / STRIDE + 1;
    localparam integer K          = KH * KW * CHANNELS;
    localparam integer ADDR_W     = $clog2(size_bram);
    localparam integer PTR_W      = $clog2(DEPTH);

    // ============================================================
    // FIFO storage
    // ============================================================
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [PTR_W:0]        count;
    reg [PTR_W-1:0]      wptr, rptr;

    assign full  = (count == DEPTH);
    assign empty = (count == 0);

    // ============================================================
    // im2col pack buffer
    // ============================================================
    reg [bit_width-1:0] pack [0:size-1];
    reg [bit_width-1:0] pixel;
    reg                 is_pad;

    integer pack_idx;
    integer oh, ow, kh, kw, ic, k_idx;
    integer y, x, i;

    wire [DATA_WIDTH-1:0] pack_word;
    genvar g;
    generate
        for (g = 0; g < size; g = g + 1) begin : CAT
            assign pack_word[bit_width*(g+1)-1 : bit_width*g] = pack[g];
        end
    endgenerate

    // ============================================================
    // FSM im2col
    // ============================================================
    localparam S_IDLE  = 2'd0;
    localparam S_ISSUE = 2'd1;
    localparam S_WAIT  = 2'd2;
    localparam S_PACK  = 2'd3;

    reg [1:0] state;
    reg       wr_en;   // pulse ghi FIFO

    // tăng index im2col
    task automatic next_index;
        begin
            if (ic == CHANNELS-1) begin
                ic = 0;
                if (kw == KW-1) begin
                    kw = 0;
                    if (kh == KH-1) begin
                        kh = 0;
                        if (ow == OW-1) begin
                            ow = 0;
                            oh = oh + 1;
                        end else
                            ow = ow + 1;
                    end else
                        kh = kh + 1;
                end else
                    kw = kw + 1;
            end else
                ic = ic + 1;
            k_idx = k_idx + 1;
        end
    endtask

    // ============================================================
    // Main sequential logic
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // FIFO
            wptr  <= {PTR_W{1'b0}};
            rptr  <= {PTR_W{1'b0}};
            count <= {(PTR_W+1){1'b0}};
            dout  <= {DATA_WIDTH{1'b0}};
            // im2col
            state     <= S_IDLE;
            busy      <= 1'b0;
            done      <= 1'b0;
            bram_read <= 1'b0;
            bram_addr <= {ADDR_W{1'b0}};
            wr_en     <= 1'b0;
            pack_idx  <= 0;
            oh <= 0; ow <= 0; kh <= 0; kw <= 0; ic <= 0; k_idx <= 0;
            is_pad <= 1'b0;
            pixel  <= {bit_width{1'b0}};
            for (i = 0; i < size; i = i + 1)
                pack[i] <= {bit_width{1'b0}};
        end
        else begin
            bram_read <= 1'b0;
            wr_en     <= 1'b0;
            done      <= 1'b0;

            // ------------------------------------------------
            // FIFO write
            // ------------------------------------------------
            if (wr_en && !full) begin
                mem[wptr] <= pack_word;
                wptr      <= wptr + 1'b1;
            end

            // ------------------------------------------------
            // FIFO read → dout (ra PE)
            // ------------------------------------------------
            if (rd_en && !empty) begin
                dout <= mem[rptr];
                rptr <= rptr + 1'b1;
            end

            // ------------------------------------------------
            // count
            // ------------------------------------------------
            case ({(wr_en && !full), (rd_en && !empty)})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: ;
            endcase

            // ------------------------------------------------
            // im2col FSM → tạo pack_word, bật wr_en
            // ------------------------------------------------
            case (state)
                S_IDLE: begin
                    if (start) begin
                        busy     <= 1'b1;
                        oh <= 0; ow <= 0; kh <= 0; kw <= 0; ic <= 0;
                        k_idx    <= 0;
                        pack_idx <= 0;
                        for (i = 0; i < size; i = i + 1)
                            pack[i] <= {bit_width{1'b0}};
                        state <= S_ISSUE;
                    end
                end

                S_ISSUE: begin
                    y = oh * STRIDE + kh - PAD;
                    x = ow * STRIDE + kw - PAD;
                    if ((y < 0) || (y >= IMG_H) || (x < 0) || (x >= IMG_W)) begin
                        is_pad <= 1'b1;
                        pixel  <= {bit_width{1'b0}};
                        state  <= S_PACK;
                    end
                    else begin
                        is_pad    <= 1'b0;
                        bram_addr <= ic * IMG_H * IMG_W + y * IMG_W + x;
                        bram_read <= 1'b1;
                        state     <= S_WAIT;
                    end
                end

                S_WAIT: begin
                    pixel <= bram_data;
                    state <= S_PACK;
                end

                S_PACK: begin
                    pack[pack_idx] <= is_pad ? {bit_width{1'b0}} : pixel;

                    if (pack_idx == size - 1) begin
                        // pack đủ 1 vector → ghi FIFO nếu còn chỗ
                        if (!full) begin
                            wr_en    <= 1'b1;
                            pack_idx <= 0;

                            if ((oh == OH-1) && (ow == OW-1) && (k_idx == K-1)) begin
                                busy  <= 1'b0;
                                done  <= 1'b1;
                                state <= S_IDLE;
                            end
                            else begin
                                next_index();
                                if (k_idx == K)
                                    k_idx <= 0;
                                state <= S_ISSUE;
                            end
                        end
                        // full: đứng chờ, không tăng index
                    end
                    else begin
                        pack_idx <= pack_idx + 1;

                        if ((oh == OH-1) && (ow == OW-1) && (k_idx == K-1)) begin
                            // hết patch nhưng pack chưa đầy → pad 0 rồi flush ở chu kỳ sau
                            pack_idx <= size - 1;
                        end
                        else begin
                            next_index();
                            if (k_idx == K)
                                k_idx <= 0;
                            state <= S_ISSUE;
                        end
                    end
                end
            endcase
        end
    end

endmodule