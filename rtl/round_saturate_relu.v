`timescale 1ns/1ps

// ------------------------------------------------------------
// round_saturate_relu — output conditioning stage.
// FRAC_BITS=0 (default) => kernel treated as PLAIN INTEGER (Q7.0):
//   no shift is applied, only saturation. This matches the original
//   design's implicit assumption (competition spec explicitly allows
//   "8-bit signed fixed-point OR integer" kernels - integer is valid).
// FRAC_BITS>0 => enables round-to-nearest right-shift for a fixed-point
//   (e.g. SQ3.4) kernel format, should the team switch to that later.
// ------------------------------------------------------------
module round_saturate_relu #(
    parameter SUM_W       = 20,
    parameter FRAC_BITS   = 0,
    parameter OUT_W       = 16,
    parameter ENABLE_RELU = 0
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    valid_in,
    input  wire signed [SUM_W-1:0] sum_in,
    output reg  signed [OUT_W-1:0] pixel_out,
    output reg                     valid_out
);
    localparam signed [SUM_W-1:0] OUT_MAX = (1 <<< (OUT_W-1)) - 1;
    localparam signed [SUM_W-1:0] OUT_MIN = -(1 <<< (OUT_W-1));

    wire signed [SUM_W-1:0] rounded = (FRAC_BITS == 0) ? sum_in :
                             (sum_in + (1 <<< (FRAC_BITS-1))) >>> FRAC_BITS;

    wire signed [SUM_W-1:0] saturated = (rounded > OUT_MAX) ? OUT_MAX :
                                        (rounded < OUT_MIN) ? OUT_MIN : rounded;

    wire signed [OUT_W-1:0] relu_applied =
            (ENABLE_RELU && saturated[SUM_W-1]) ? {OUT_W{1'b0}} : saturated[OUT_W-1:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_out <= {OUT_W{1'b0}};
            valid_out <= 1'b0;
        end else begin
            pixel_out <= relu_applied;
            valid_out <= valid_in;
        end
    end
endmodule
