package sm_pkg;

parameter int DEFAULT_WARPS = 4;

typedef enum logic [5:0] {
    OP_NOP   = 6'h00,
    OP_HALT  = 6'h01,

    OP_LID   = 6'h02,
    OP_MOVI  = 6'h03,
    OP_WID   = 6'h04,
    OP_TID   = 6'h05,

    OP_ADD   = 6'h08,
    OP_SUB   = 6'h09,
    OP_AND   = 6'h0A,
    OP_OR    = 6'h0B,
    OP_XOR   = 6'h0C,
    OP_SHL   = 6'h0D,
    OP_SHR   = 6'h0E,
    OP_MUL   = 6'h0F,

    OP_ADDI  = 6'h10,
    OP_ANDI  = 6'h11,
    OP_ORI   = 6'h12,
    OP_XORI  = 6'h13,
    OP_SHLI  = 6'h14,
    OP_SHRI  = 6'h15,
    OP_IMAD  = 6'h16,  // rd = low32(rs1 * rs2 + rs3)

    OP_LD    = 6'h20,
    OP_ST    = 6'h21,

    OP_BRA   = 6'h30,
    OP_BEQ   = 6'h31
} opcode_t;

// Kept for older comments/tests; the current core uses explicit valid pipeline
// registers rather than the original two-state FSM.
typedef enum logic {
    ST_ID = 1'b0,
    ST_EX = 1'b1
} core_state_t;

function automatic logic signed [31:0] sext16(input logic [15:0] imm16);
    sext16 = $signed({{16{imm16[15]}}, imm16});
endfunction

function automatic bit op_uses_rs1(input opcode_t op);
    unique case (op)
        OP_ADD, OP_SUB, OP_AND, OP_OR, OP_XOR, OP_SHL, OP_SHR, OP_MUL, OP_IMAD,
        OP_ADDI, OP_ANDI, OP_ORI, OP_XORI, OP_SHLI, OP_SHRI,
        OP_LD, OP_ST, OP_BEQ: op_uses_rs1 = 1'b1;
        default:             op_uses_rs1 = 1'b0;
    endcase
endfunction

function automatic bit op_uses_rs2(input opcode_t op);
    unique case (op)
        OP_ADD, OP_SUB, OP_AND, OP_OR, OP_XOR, OP_SHL, OP_SHR, OP_MUL, OP_IMAD,
        OP_ST, OP_BEQ: op_uses_rs2 = 1'b1;
        default:       op_uses_rs2 = 1'b0;
    endcase
endfunction

function automatic bit op_uses_rs3(input opcode_t op);
    unique case (op)
        OP_IMAD: op_uses_rs3 = 1'b1;
        default: op_uses_rs3 = 1'b0;
    endcase
endfunction

function automatic bit op_writes_rd(input opcode_t op);
    unique case (op)
        OP_LID, OP_MOVI, OP_WID, OP_TID,
        OP_ADD, OP_SUB, OP_AND, OP_OR, OP_XOR, OP_SHL, OP_SHR, OP_MUL, OP_IMAD,
        OP_ADDI, OP_ANDI, OP_ORI, OP_XORI, OP_SHLI, OP_SHRI,
        OP_LD:   op_writes_rd = 1'b1;
        default: op_writes_rd = 1'b0;
    endcase
endfunction

function automatic bit op_is_load(input opcode_t op);
    op_is_load = (op == OP_LD);
endfunction

function automatic bit op_is_store(input opcode_t op);
    op_is_store = (op == OP_ST);
endfunction

function automatic bit op_is_mem(input opcode_t op);
    op_is_mem = (op == OP_LD) || (op == OP_ST);
endfunction

function automatic bit op_is_mul(input opcode_t op);
    op_is_mul = (op == OP_MUL) || (op == OP_IMAD);
endfunction

function automatic bit op_is_multicycle_writer(input opcode_t op);
    op_is_multicycle_writer = (op == OP_LD) || op_is_mul(op);
endfunction

function automatic bit op_is_singlecycle_writer(input opcode_t op);
    op_is_singlecycle_writer = op_writes_rd(op) && !op_is_multicycle_writer(op);
endfunction

function automatic logic [31:0] enc_r(input opcode_t op, input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] rs2);
    enc_r = {op, rd, rs1, rs2, 11'd0};
endfunction

function automatic logic [31:0] enc_mad(input opcode_t op, input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] rs2, input logic [4:0] rs3);
    enc_mad = {op, rd, rs1, rs2, rs3, 6'd0};
endfunction

function automatic logic [31:0] enc_i(input opcode_t op, input logic [4:0] rd, input logic [4:0] rs1, input logic signed [15:0] imm16);
    enc_i = {op, rd, rs1, imm16};
endfunction

function automatic logic [31:0] enc_s(input opcode_t op, input logic [4:0] rs2, input logic [4:0] rs1, input logic signed [15:0] imm16);
    enc_s = {op, rs2, rs1, imm16};
endfunction

function automatic logic [31:0] enc_b(input opcode_t op, input logic [4:0] rs1, input logic [4:0] rs2, input logic signed [15:0] imm16);
    enc_b = {op, rs1, rs2, imm16};
endfunction

function automatic logic [31:0] enc_j(input opcode_t op, input logic signed [15:0] imm16);
    enc_j = {op, 10'd0, imm16};
endfunction

endpackage
