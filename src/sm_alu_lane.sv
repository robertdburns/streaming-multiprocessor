`timescale 1ns / 1ps

module sm_alu_lane (
  input  sm_pkg::opcode_t    op,
  input  logic [31:0]        rs1,
  input  logic [31:0]        rs2,
  input  logic [31:0]        rs3,
  input  logic signed [31:0] imm,
  input  logic [31:0]        lane_id,
  input  logic [31:0]        warp_id,
  input  logic [31:0]        thread_id,
  output logic [31:0]        result,
  output logic               result_valid
);
    import sm_pkg::*;

    logic [31:0] imm_u;
    logic [63:0] mul_rr;
    logic [63:0] imad_rr;

    always_comb begin
        imm_u        = imm;
        mul_rr       = rs1 * rs2;
        imad_rr      = (rs1 * rs2) + rs3;
        result       = 32'd0;
        result_valid = 1'b0;

        unique case (op)
            OP_LID:  begin result = lane_id;       result_valid = 1'b1; end
            OP_WID:  begin result = warp_id;       result_valid = 1'b1; end
            OP_TID:  begin result = thread_id;     result_valid = 1'b1; end
            OP_MOVI: begin result = imm_u;         result_valid = 1'b1; end

            OP_ADD:  begin result = rs1 + rs2;         result_valid = 1'b1; end
            OP_SUB:  begin result = rs1 - rs2;         result_valid = 1'b1; end
            OP_AND:  begin result = rs1 & rs2;         result_valid = 1'b1; end
            OP_OR:   begin result = rs1 | rs2;         result_valid = 1'b1; end
            OP_XOR:  begin result = rs1 ^ rs2;         result_valid = 1'b1; end
            OP_SHL:  begin result = rs1 << rs2[4:0];   result_valid = 1'b1; end
            OP_SHR:  begin result = rs1 >> rs2[4:0];   result_valid = 1'b1; end
            OP_MUL:  begin result = mul_rr[31:0];      result_valid = 1'b1; end
            OP_IMAD: begin result = imad_rr[31:0];     result_valid = 1'b1; end

            OP_ADDI: begin result = rs1 + imm_u;       result_valid = 1'b1; end
            OP_ANDI: begin result = rs1 & imm_u;       result_valid = 1'b1; end
            OP_ORI:  begin result = rs1 | imm_u;       result_valid = 1'b1; end
            OP_XORI: begin result = rs1 ^ imm_u;       result_valid = 1'b1; end
            OP_SHLI: begin result = rs1 << imm_u[4:0]; result_valid = 1'b1; end
            OP_SHRI: begin result = rs1 >> imm_u[4:0]; result_valid = 1'b1; end

            default: begin
                result       = 32'd0;
                result_valid = 1'b0;
            end
        endcase
    end
endmodule
