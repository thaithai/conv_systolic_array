module weight_packer #(
    parameter integer bit_width = 8,
    parameter integer size      = 16,
    parameter integer size_bram = 256
)(
    input  clk,
    input  rst_n,
    input  start_row,                              // 1 pulse: pack 1 hàng
    input  [$clog2(size_bram)-1:0] base_addr,

    output reg                         bram_read,
    output reg [$clog2(size_bram)-1:0] bram_addr,
    input      [bit_width-1:0]         bram_data,

    output reg [bit_width*size-1:0] weight_vec,
    output reg                      row_done
);
    localparam integer ADDR_W = $clog2(size_bram);

    reg [bit_width-1:0] pack [0:size-1];
    reg [$clog2(size):0] cnt;
    reg busy, pending;
    integer i;

    genvar g;
    wire [bit_width*size-1:0] pack_word;
    generate
        for (g = 0; g < size; g = g + 1) begin : CAT
            assign pack_word[bit_width*(g+1)-1 : bit_width*g] = pack[g];
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy       <= 1'b0;
            pending    <= 1'b0;
            cnt        <= {($clog2(size)+1){1'b0}};
            bram_read  <= 1'b0;
            bram_addr  <= {ADDR_W{1'b0}};
            weight_vec <= {(bit_width*size){1'b0}};
            row_done   <= 1'b0;
            for (i = 0; i < size; i = i + 1)
                pack[i] <= {bit_width{1'b0}};
        end
        else begin
            bram_read <= 1'b0;
            row_done  <= 1'b0;

            if (start_row && !busy) begin
                busy      <= 1'b1;
                cnt       <= {($clog2(size)+1){1'b0}};
                bram_addr <= base_addr;
                bram_read <= 1'b1;
                pending   <= 1'b1;
            end
            else if (busy && pending) begin
                pack[cnt] <= bram_data;
                pending   <= 1'b0;

                if (cnt == size-1) begin
                    // byte cuối đã vào pack — 1 cycle sau mới weight_vec ổn
                    weight_vec <= {pack_word[bit_width*size-1:bit_width], bram_data};
                    // sạch hơn: gán pack[cnt] xong, cycle sau xuất
                    busy     <= 1'b0;
                    row_done <= 1'b1;
                end
                else begin
                    cnt       <= cnt + 1'b1;
                    bram_addr <= bram_addr + 1'b1;
                    bram_read <= 1'b1;
                    pending   <= 1'b1;
                end
            end
        end
    end
endmodule