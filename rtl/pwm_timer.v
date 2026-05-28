// pwm_timer.v - Chopper phase timer for PWM_B FSM
// Counts up each clock. Resets to 0 when timer_rst is asserted (state transition).
// Also resets on rst_n or disable (!en).

module pwm_timer (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire        timer_rst,   // 1 = reset to 0 (driven by FSM on state transition)
    output reg  [11:0] timer
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)         timer <= 12'd0;
        else if (!en)       timer <= 12'd0;
        else if (timer_rst) timer <= 12'd0;
        else                timer <= timer + 12'd1;
    end

endmodule
