`timescale 1ns/1ps

// single 'core', or SIMT lane
// each lane, or 'core' contains 32x 32bit regs
// a single INT ALU

module cuda_lane_core #(
  parameter int REGS = 32,
  parameter int unsigned LANE_ID = 0
) 
(
  input  logic              clk,
  input  logic              rst,

  // Lane controls
  input  logic              lane_en,   // active mask bit for this lane
  input  sm_pkg::opcode_t   op,
  input  logic [4:0]        rd_idx,
  input  logic [4:0]        rs1_idx,
  input  logic [4:0]        rs2_idx,
  input  logic signed [31:0] imm,
  input  logic              commit,    // asserts in the execute/commit phase

  // Memory interface 
  output logic [31:0]       dmem_addr,
  input  logic [31:0]       dmem_rdata,
  output logic              dmem_we,
  output logic [31:0]       dmem_wdata,

  // Expose operands 
  output logic [31:0]       rs1_val,
  output logic [31:0]       rs2_val,

  // Simulation debug signals
  input  logic              dbg_en,
  input  logic [4:0]        dbg_addr,
  output logic [31:0]       dbg_data
);
	import sm_pkg::*;

	// Reg File ===============================================================
	logic rf_we;
	logic [31:0] rf_wdata;

	sm_regfile_2r1w #(
	.REGS(REGS)
	) u_rf (
	.clk(clk),
	.rst(rst),

	.raddr1(rs1_idx),
	.raddr2(rs2_idx),
	.rdata1(rs1_val),
	.rdata2(rs2_val),

	.we(rf_we),
	.waddr(rd_idx),
	.wdata(rf_wdata),

	.dbg_en(dbg_en),
	.dbg_addr(dbg_addr),
	.dbg_data(dbg_data)
	);

	// INT ALU ================================================================
	logic [31:0] alu_res;
	logic        alu_valid;

	logic [3:0] lane_id_4;
	assign lane_id_4 = logic [3:0]'(LANE_ID);

	sm_alu_lane u_alu (
	.op(op),
	.rs1(rs1_val),
	.rs2(rs2_val),
	.imm(imm),
	.lane_id(lane_id_4),
	.result(alu_res),
	.result_valid(alu_valid)
	);

	// Memory =================================================================
    // Default: no mem op
    dmem_addr  = 32'd0;
    dmem_wdata = 32'd0;
    dmem_we    = 1'b0;

    // Drive memory requests only during the execute/commit phase.
    if (commit && lane_en) begin
      if (op == OP_LD || op == OP_ST) begin
        dmem_addr = rs1_val + imm;
      end

      if (op == OP_ST) begin
        dmem_wdata = rs2_val;
        dmem_we    = 1'b1;
      end
    end

endmodule