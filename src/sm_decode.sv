// Decoder Module

module sm_decode (
  input  logic [31:0]        instr,
  output sm_pkg::opcode_t    op,
  output logic [4:0]         A,
  output logic [4:0]         B,
  output logic [4:0]         C,
  output logic [15:0]        imm16,
  output logic signed [31:0] imm_sext,
  output logic [4:0]         rd_idx,
  output logic [4:0]         rs1_idx,
  output logic [4:0]         rs2_idx
);
  import sm_pkg::*;

  // Map opcode bits to opcode variable
  // unknowns become NOP
	function automatic opcode_t decode_op(input logic [5:0] raw);
		unique case (raw)
			OP_NOP  : decode_op = OP_NOP;
			OP_HALT : decode_op = OP_HALT;

			OP_LID  : decode_op = OP_LID;
			OP_MOVI : decode_op = OP_MOVI;

			OP_ADD  : decode_op = OP_ADD;
			OP_SUB  : decode_op = OP_SUB;
			OP_AND  : decode_op = OP_AND;
			OP_OR   : decode_op = OP_OR;
			OP_XOR  : decode_op = OP_XOR;
			OP_SHL  : decode_op = OP_SHL;
			OP_SHR  : decode_op = OP_SHR;

			OP_ADDI : decode_op = OP_ADDI;
			OP_ANDI : decode_op = OP_ANDI;
			OP_ORI  : decode_op = OP_ORI;
			OP_XORI : decode_op = OP_XORI;
			OP_SHLI : decode_op = OP_SHLI;
			OP_SHRI : decode_op = OP_SHRI;

			OP_LD   : decode_op = OP_LD;
			OP_ST   : decode_op = OP_ST;

			OP_BRA  : decode_op = OP_BRA;
			OP_BEQ  : decode_op = OP_BEQ;

			default : decode_op = OP_NOP;
		endcase
 	endfunction

	always_comb begin
		// Decode raw fields
		op       = decode_op(instr[31:26]);
		A        = instr[25:21];
		B        = instr[20:16];
		C        = instr[15:11];
		imm16    = instr[15:0];
		imm_sext = sext16(imm16);

		// Default interpretation is R-type:
		//   rd=A, rs1=B, rs2=C
		rd_idx  = A;
		rs1_idx = B;
		rs2_idx = C;

    unique case (op)
		// I-type (rd=A, rs1=B)
		OP_MOVI, OP_ADDI, OP_ANDI, OP_ORI, OP_XORI, OP_SHLI, OP_SHRI, OP_LD: begin
			rd_idx  = A;
			rs1_idx = B;
			rs2_idx = '0;
		end

		// Special
		OP_LID: begin
			rd_idx  = A;
			rs1_idx = '0;
			rs2_idx = '0;
		end

		// Store format: rs2(data)=A, rs1(base)=B
		OP_ST: begin
			rd_idx  = '0;
			rs1_idx = B;
			rs2_idx = A;
		end

		// Branch compare: rs1=A, rs2=B
		OP_BEQ: begin
			rd_idx  = '0;
			rs1_idx = A;
			rs2_idx = B;
		end

		default: begin
			// Keep R-type defaults
		end
    endcase
  	end

	
endmodule