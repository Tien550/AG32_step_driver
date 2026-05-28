// syn_in_signal.v - Generic multi-stage synchronizer for async input signals
// Implements a 2-stage or 3-stage flip-flop chain to safely cross clock domains.
// Use STAGES=3 when the output feeds edge-detection logic (extra pipeline stage).
// Use STAGES=2 for standard level signals.

module syn_in_signal #(
    parameter STAGES = 2,   // Number of synchronizer stages (2 or 3)
    parameter WIDTH  = 1    // Bus width
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire [WIDTH-1:0]  async_in,
    output wire [WIDTH-1:0]  sync_out
);

generate
    if (STAGES == 2) begin : sync2
        reg [WIDTH-1:0] s1, s2;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                s1 <= {WIDTH{1'b0}};
                s2 <= {WIDTH{1'b0}};
            end else begin
                s1 <= async_in;
                s2 <= s1;
            end
        end
        assign sync_out = s2;
    end else if (STAGES == 3) begin : sync3
        reg [WIDTH-1:0] s1, s2, s3;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                s1 <= {WIDTH{1'b0}};
                s2 <= {WIDTH{1'b0}};
                s3 <= {WIDTH{1'b0}};
            end else begin
                s1 <= async_in;
                s2 <= s1;
                s3 <= s2;
            end
        end
        assign sync_out = s3;
    end
endgenerate

endmodule
