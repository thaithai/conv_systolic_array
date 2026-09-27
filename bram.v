module bram #(
    parameter bit_width   = 8,
    parameter size_bram   = 512
)(
    input  clk,
    input  rst_n,
    input  read,
    input  write,
    input  [bit_width-1:0]           data_in,
    input  [$clog2(size_bram)-1:0]   address,   
    output reg [bit_width-1:0]       data_out
);

    // Memory array
    reg [$clog2(size_bram)-1:0] ram [0:size_bram-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out <= {$clog2(size_bram){1'b0}};
        end
        else begin
            // Write
            if (write) begin
                ram[address] <= data_in;
            end
            // Read
            if (read) begin
                data_out <= ram[address];
            end
        end
    end
endmodule