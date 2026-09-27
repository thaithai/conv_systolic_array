module MAC #(
    parameter bit_width = 8,
    parameter acc_width = 32
)(
    input  clk,
    input  rst_n,
    input  load_weight,                 // 1 = đang load weight, 0 = compute

    input  [bit_width-1:0] data_in,     // activation từ trái
    input  [acc_width-1:0] psum_in,     // psum từ trên
    input  [bit_width-1:0] weight_in,   // weight từ trên (khi load)

    output reg [bit_width-1:0] data_out,    // đẩy activation sang phải
    output reg [acc_width-1:0] psum_out,    // đẩy psum xuống dưới
    output reg [bit_width-1:0] weight_out   // đẩy weight xuống dưới (chỉ dùng khi load)
);

    reg [bit_width-1:0] weight_reg;     // weight stationary

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_reg  <= {bit_width{1'b0}};
            data_out    <= {bit_width{1'b0}};
            psum_out    <= {acc_width{1'b0}};
            weight_out  <= {bit_width{1'b0}};
        end
        else begin
            if (load_weight) begin
                // ===== LOAD PHASE =====
                // Weight chảy từ trên xuống
                weight_reg  <= weight_in;
                weight_out  <= weight_in;       // đẩy tiếp xuống PE dưới

                // Data và psum giữ nguyên hoặc bypass
                data_out    <= data_in;
                psum_out    <= psum_in;
            end
            else begin
                // ===== COMPUTE PHASE =====
                // Weight đứng yên
                // weight_out  <= weight_reg;      // không cần thiết, nhưng giữ

                data_out    <= data_in;         // activation chảy ngang
                psum_out    <= psum_in + (data_in * weight_reg);  // MAC
            end
        end
    end

endmodule