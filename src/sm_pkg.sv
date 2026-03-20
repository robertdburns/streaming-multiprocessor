package mini_sm_pkg;

// ==============================================
// Mini-SM ISA
// ==============================================
// 32-bit fixed-width instructions
//
// Formatting:
// 	OP 	= instr[31:26]
// 	A 	= instr[25:21]
// 	B 	= instr[20:16]
// 	Instructions use EITHER c OR imm
// 	C  	= instr[15:11]
// 	imm = instr[15:0]
//
// Instruction Formatting
//  R-type:  {op, rd=A, rs1=B, rs2=C, 11'b0}			// Reg-based Math
//  I-type:  {op, rd=A, rs1=B, imm16}					// Immediate-based Math
//  S-type:  {op, rs2=A (data), rs1=B (base), imm16}	// Memory Instructions
//  B-type:  {op, rs1=A, rs2=B, imm16}  				// Branches
//
//

typedef enum logic [5:0] {
    OP_NOP   = 6'h00,
    OP_HALT  = 6'h01,

    // Specials
    OP_LID   = 6'h02, // LID  rd
    OP_MOVI  = 6'h03, // MOVI rd, imm16

    // R-type ALU
    OP_ADD   = 6'h08,
    OP_SUB   = 6'h09,
    OP_AND   = 6'h0A,
    OP_OR    = 6'h0B,
    OP_XOR   = 6'h0C,
    OP_SHL   = 6'h0D, // shift amount = rs2[4:0]
    OP_SHR   = 6'h0E,

    // I-type ALU
    OP_ADDI  = 6'h10,
    OP_ANDI  = 6'h11,
    OP_ORI   = 6'h12,
    OP_XORI  = 6'h13,
    OP_SHLI  = 6'h14, // shift amount = imm16[4:0]
    OP_SHRI  = 6'h15,

    // Memory
    OP_LD    = 6'h20, // LD  rd, [rs1 + imm16]
    OP_ST    = 6'h21, // ST  rs2(A), [rs1(B) + imm16]

    // Control (uniform for now)
    OP_BRA   = 6'h30, // BRA imm16  (PC = PC+1+imm16)
    OP_BEQ   = 6'h31  // BEQ rs1(A), rs2(B), imm16 (lane0 decides)
  } opcode_t;


// Sign Extend Function
	function automatic logic signed [31:0] sext16(input logic [15:0] imm16);
		sext16 = $signed({{16{imm16[15]}}, imm16});
	endfunction


endpackage