`timescale 1ns / 1ps
// Multiply/divide unit for the doom core, with the same interface as the course MCycle.v.
//  * Multiplies (mul, mulh, mulhsu, mulhu) use a pipelined 33x33 multiplier (DSP48 blocks):
//    Busy for 3 cycles, result on the 4th, instead of ~17 cycles with the Booth MCycle.
//  * Divides (div, divu, rem, remu) still use the course MCycle.v.
module muldiv (
    input         CLK,
    input         RESET,
    input         Start,
    input  [1:0]  MCycleOp,     // 00 signed mul, 01 unsigned mul, 10 signed div, 11 unsigned div
    input         MulSU,        // with 00: Operand1 signed, Operand2 unsigned (mulhsu)
    input  [31:0] Operand1,
    input  [31:0] Operand2,
    output [31:0] Result1,      // low word / quotient
    output [31:0] Result2,      // high word / remainder
    output        Busy
);
    wire is_mul = ~MCycleOp[1];

    // ---------------- divide: course MCycle ----------------
    wire [31:0] d_r1, d_r2;
    wire        d_busy;
    MCycle #(.width(32)) divider(
        CLK, RESET, Start & ~is_mul, MCycleOp, 1'b0, Operand1, Operand2, d_r1, d_r2, d_busy);

    // ---------------- multiply: 33x33 signed, 3 register stages ----------------
    reg [1:0] mstate = 2'd0;    // 0 idle, 1 operands registered, 2 product registered, 3 result ready
    reg signed [32:0] ma = 0, mb = 0;
    reg signed [65:0] p1 = 0, p2 = 0;
    always @(posedge CLK) begin
        if (RESET) mstate <= 2'd0;
        else case (mstate)
            2'd0: if (Start & is_mul) begin
                      ma <= {~MCycleOp[0] & Operand1[31], Operand1};
                      mb <= {~MCycleOp[0] & ~MulSU & Operand2[31], Operand2};
                      mstate <= 2'd1;
                  end
            2'd1: begin p1 <= ma * mb; mstate <= 2'd2; end
            2'd2: begin p2 <= p1;      mstate <= 2'd3; end
            default: mstate <= 2'd0;    // result is used this cycle
        endcase
    end

    assign Busy    = is_mul ? (Start & (mstate != 2'd3)) : d_busy;
    assign Result1 = is_mul ? p2[31:0]  : d_r1;
    assign Result2 = is_mul ? p2[63:32] : d_r2;
endmodule
