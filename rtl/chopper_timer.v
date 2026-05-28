// chopper_timer.v - Shared chopper period counter for both coils
//
// Single counter 0..(period_cycles-1).
// cycle_start_a pulses HIGH for 1 clock at cnt==0           (coil A ON start)
// cycle_start_b pulses HIGH for 1 clock at cnt==period/2    (coil B ON start, half-period offset)
//
// Using one shared counter ensures the offset always tracks exactly 50% of
// the current period, even when period_cycles is changed at runtime.

module chop_timer (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire [11:0] period_cycles,
    output wire        cycle_start_a,
    output wire        cycle_start_b
);

    reg [11:0] cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cnt <= 12'd0;
        else if (!en)
            cnt <= 12'd0;
        else if (cnt >= period_cycles)
            cnt <= 12'd0;
        else
            cnt <= cnt + 12'd1;
    end

    assign cycle_start_a = (cnt == 12'd0) && en;
    //assign cycle_start_b = (cnt == (period_cycles >> 1)) && en;
	 assign cycle_start_b = cycle_start_a;
endmodule
