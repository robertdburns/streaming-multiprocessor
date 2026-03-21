`timescale 1ns / 1ps
// ALU for a single core

module sm_alu_lane (
  input  sm_pkg::opcode_t    op,
  input  logic [31:0]        rs1,
  input  logic [31:0]        rs2,
  input  logic signed [31:0] imm,
  input  logic [3:0]         lane_id,
  output logic [31:0]        result,
  output logic               result_valid
);
	import sm_pkg::*;

	logic [31:0] imm_u;
	logic [31:0] lane_id_zext;

	always_comb begin
	imm_u        = imm;
	lane_id_zext = {28'd0, lane_id};

	result       = 32'd0;
	result_valid = 1'b0;

	unique case (op)
		// Specials
		OP_LID:  begin result = lane_id_zext; result_valid = 1'b1; end
		OP_MOVI: begin result = imm_u;        result_valid = 1'b1; end

		// R-type ALU
		OP_ADD:  begin result = rs1 + rs2;              result_valid = 1'b1; end
		OP_SUB:  begin result = rs1 - rs2;              result_valid = 1'b1; end
		OP_AND:  begin result = rs1 & rs2;              result_valid = 1'b1; end
		OP_OR:   begin result = rs1 | rs2;              result_valid = 1'b1; end
		OP_XOR:  begin result = rs1 ^ rs2;              result_valid = 1'b1; end
		OP_SHL:  begin result = rs1 << rs2[4:0];        result_valid = 1'b1; end
		OP_SHR:  begin result = rs1 >> rs2[4:0];        result_valid = 1'b1; end

		// I-type ALU
		OP_ADDI: begin result = rs1 + imm_u;            result_valid = 1'b1; end
		OP_ANDI: begin result = rs1 & imm_u;            result_valid = 1'b1; end
		OP_ORI:  begin result = rs1 | imm_u;            result_valid = 1'b1; end
		OP_XORI: begin result = rs1 ^ imm_u;            result_valid = 1'b1; end
		OP_SHLI: begin result = rs1 << imm_u[4:0];      result_valid = 1'b1; end
		OP_SHRI: begin result = rs1 >> imm_u[4:0];      result_valid = 1'b1; end

		default: begin
		// Not an ALU-register-writing opcode
		result       = 32'd0;
		result_valid = 1'b0;
		end
	endcase
  	end

endmodule
