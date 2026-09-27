module MAC_array #(
    parameter size      = 16,
    parameter bit_width = 8,
    parameter acc_width = 32
)(
    input  clk,
    input  rst_n,
    input  load_weight,                         // 1: load weight, 0: compute

    // Weight từ BÊN TRÁI (1 vector = 1 cột weight, mỗi phần tử 1 hàng)
    input  [bit_width*size-1:0] weight_in,      // weight_in[row]

    // Input/activation từ PHÍA TRÊN (1 vector = 1 hàng input, mỗi phần tử 1 cột)
    input  [bit_width*size-1:0] data_in,        // data_in[col]

    // Kết quả từ BÊN PHẢI (mỗi hàng 1 acc)
    output [acc_width*size-1:0] acc_out         // acc_out[row]
);

    // input chảy dọc: size cột, size+1 điểm nối (0 = đỉnh, size = đáy)
    wire [bit_width-1:0] data_v   [0:size][0:size-1];

    // weight chảy ngang: size hàng, size+1 điểm nối (0 = trái, size = phải)
    wire [bit_width-1:0] weight_h [0:size-1][0:size];

    // psum chảy ngang: size hàng, size+1 điểm nối
    wire [acc_width-1:0] psum_h   [0:size-1][0:size];

    genvar r, c;

    // Input từ trên xuống — 1 phần tử / cột
    generate
        for (c = 0; c < size; c = c + 1) begin : TOP_IN
            assign data_v[0][c] = data_in[bit_width*(c+1)-1 : bit_width*c];
        end
    endgenerate

    // Weight + psum từ trái sang — 1 phần tử / hàng, psum đầu hàng = 0
    generate
        for (r = 0; r < size; r = r + 1) begin : LEFT_IN
            assign weight_h[r][0] = weight_in[bit_width*(r+1)-1 : bit_width*r];
            assign psum_h[r][0]   = {acc_width{1'b0}};
        end
    endgenerate

    generate
        for (r = 0; r < size; r = r + 1) begin : ROW
            for (c = 0; c < size; c = c + 1) begin : COL
                MAC #(
                    .bit_width (bit_width),
                    .acc_width (acc_width)
                ) pe (
                    .clk         (clk),
                    .rst_n       (rst_n),
                    .load_weight (load_weight),

                    .data_in     (data_v[r][c]),       // từ PE trên
                    .psum_in     (psum_h[r][c]),       // từ PE trái
                    .weight_in   (weight_h[r][c]),     // từ PE trái

                    .data_out    (data_v[r+1][c]),     // xuống PE dưới
                    .psum_out    (psum_h[r][c+1]),     // sang PE phải
                    .weight_out  (weight_h[r][c+1])    // sang PE phải
                );
            end
        end
    endgenerate

    // Output cạnh phải
    generate
        for (r = 0; r < size; r = r + 1) begin : RIGHT_OUT
            assign acc_out[acc_width*(r+1)-1 : acc_width*r] = psum_h[r][size];
        end
    endgenerate

endmodule