// pwm_gate_dec.v - Registered gate output decoder for IRS2111S IN pins
//
// Registered (not combinational) to match original FSM timing:
//   q1/q3 reflect the state that was active on the PREVIOUS clock edge.
//
// S_DRIVE:  sign_latch=0 → q1=1,q3=0 (A→B)   sign_latch=1 → q1=0,q3=1 (B→A)
// S_FAST:   decay_sign=0 → q1=0,q3=1 (reverse A→B)  decay_sign=1 → q1=1,q3=0 (reverse B→A)
// All other states: q1=0, q3=0 (both low-sides on)

module pwm_gate_dec (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire [2:0]  state,
    input  wire        sign_latch,    // direction of current drive (latched in S_OFF)
    input  wire        decay_sign,    // direction of last non-zero drive (latched in S_DT_ON)
    output reg         q1,            // IN_L: left  IRS2111S
    output reg         q3             // IN_R: right IRS2111S
);

    localparam S_DRIVE = 3'd1;
    localparam S_FAST  = 3'd3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)   {q1, q3} <= 2'b00;
        else if (!en) {q1, q3} <= 2'b00;
        else begin
            case (state)
                S_DRIVE: {q1, q3} <= sign_latch ? 2'b01 : 2'b10;
                S_FAST:  {q1, q3} <= decay_sign ? 2'b10 : 2'b01;
                default: {q1, q3} <= 2'b00;
            endcase
        end
    end

endmodule
