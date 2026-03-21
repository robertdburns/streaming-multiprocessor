`timescale 1ns / 1ps

module cuda_core_int #(
	parameter int LANES      = 16,
	parameter int REGS       = 32,
	parameter int IMEM_WORDS = 256,
	parameter int DMEM_WORDS = 1024
	parameter bit ASSERT_UNIFORM = 1'b1
)
(
	input logic clk,
	input logic rst,

	// Instruction Memory 
	input 	logic [31:0] 					imem_rdata,
	output 	logic [$clog2(IMEM_WORDS)-1:0] 	imem_addr,

	// Data Memory
	input 	logic [31:0] dmem_rdata [0:LANES-1],

	output 	logic [31:0] 		dmem_addr 	[0:LANES-1],
	output 	logic [LANES-1:0] 	dmem_we,
	output 	logic [31:0] 		dmem_wdata	[0:LANES-1],

	// Simulation debug signals
	input	logic 			dbg_en,
	input   logic [3:0] 	dbg_lane,
	input 	logic [4:0] 	dbg_reg,
	output	logic [31:0]   	dbg_rdata,

	// core status
	output	logic halted
);
	import sm_pkg::*;

	// Warp-level State =======================================================
	logic [$clog2(IMEM_WORDS)-1:0] pc_q;
	logic [LANES-1:0]              active_mask_q;

	// Instruction Decode Phase ===============================================
	logic [31:0] instr;
	opcode_t op_id;

	logic [4:0] A_id, B_id, C_id;
	logic [15:0] imm16_id;

	logic signed [31:0] imm_sext_id;
	logic [4:0] rd_id, rs1_id, rs2_id;

	assign instr     = imem_rdata;
	assign imem_addr = pc_q;

	sm_decode u_dec (
    .instr(instr),
    .op(op_id),
    .A(A_id),
    .B(B_id),
    .C(C_id),
    .imm16(imm16_id),
    .imm_sext(imm_sext_id),
    .rd_idx(rd_id),
    .rs1_idx(rs1_id),
    .rs2_idx(rs2_id)
  	);

	// Execute Phase ==========================================================
	opcode_t                 op_ex;
	logic [4:0]              rd_ex, rs1_ex, rs2_ex;
	logic signed [31:0]      imm_ex;
	logic [$clog2(IMEM_WORDS)-1:0] pc_ex;

	// Bus ====================================================================
	opcode_t            op_bus;
	logic [4:0]         rd_bus, rs1_bus, rs2_bus;
	logic signed [31:0] imm_bus;
	logic               commit;

	always_comb begin

	// Instruction Decode
    if (state_q == ST_ID) begin
		op_bus  = op_id;
		rd_bus  = rd_id;
		rs1_bus = rs1_id;
		rs2_bus = rs2_id;
		imm_bus = imm_sext_id;
    end 
	// Instruction Execute
	else begin
		op_bus  = op_ex;
		rd_bus  = rd_ex;
		rs1_bus = rs1_ex;
		rs2_bus = rs2_ex;
		imm_bus = imm_ex;
    end

	// Commit in Execute
    commit = (state_q == ST_EX) && !halted && (op_bus != OP_HALT);
  	end


	// Lane (Core) Generation =================================================
	logic [31:0] lane_rs1 [0:LANES-1];
	logic [31:0] lane_rs2 [0:LANES-1];

	logic [31:0] lane_dbg [0:LANES-1];

	genvar gl;
	generate
	for (gl = 0; gl < LANES; gl++) begin : G_LANE
		logic lane_dbg_en;
		assign lane_dbg_en = dbg_en && (dbg_lane == logic [3:0]'(gl));

		// generate core module
		cuda_lane_core #(
		.REGS(REGS),
		.LANE_ID(gl)
		) 
		u_lane 
		(
		.clk(clk),
		.rst(rst),

		.lane_en(active_mask_q[gl] && !halted),
		.op(op_bus),
		.rd_idx(rd_bus),
		.rs1_idx(rs1_bus),
		.rs2_idx(rs2_bus),
		.imm(imm_bus),
		.commit(commit),

		.dmem_addr(dmem_addr[gl]),
		.dmem_rdata(dmem_rdata[gl]),
		.dmem_we(dmem_we[gl]),
		.dmem_wdata(dmem_wdata[gl]),

		.rs1_val(lane_rs1[gl]),
		.rs2_val(lane_rs2[gl]),

		.dbg_en(lane_dbg_en),
		.dbg_addr(dbg_reg),
		.dbg_data(lane_dbg[gl])
		);
	end
	endgenerate


// PC Next Generation =========================================================
	logic [$clog2(IMEM_WORDS)-1:0] pc_next;
	always_comb begin
	// Default sequential
	pc_next = pc_ex + 1;

	unique case (op_ex)
		OP_BRA: begin
		logic signed [31:0] pc_calc;
		pc_calc = $signed({{(32-$clog2(IMEM_WORDS)){1'b0}}, pc_ex}) + 32'sd1 + imm_ex;
		pc_next = pc_calc[$clog2(IMEM_WORDS)-1:0];
		end

		OP_BEQ: begin
		if (lane0_eq) begin
			logic signed [31:0] pc_calc;
			pc_calc = $signed({{(32-$clog2(IMEM_WORDS)){1'b0}}, pc_ex}) + 32'sd1 + imm_ex;
			pc_next = pc_calc[$clog2(IMEM_WORDS)-1:0];
		end
		end

		default: begin
		// keep sequential
		end
	endcase
	end

// Sequential Control =========================================================
	always_ff @(posedge clk) begin
		
		// on RST set all registers to 0
		if (rst) begin
			pc_q          <= '0;
			pc_ex         <= '0;
			op_ex         <= OP_NOP;
			rd_ex         <= '0;
			rs1_ex        <= '0;
			rs2_ex        <= '0;
			imm_ex        <= 32'sd0;

			active_mask_q <= {LANES{1'b1}};
			state_q       <= ST_ID;
			halted        <= 1'b0;
		end 
		
		else begin
			// if core not halted
			if (!halted) begin
			unique case (state_q)
				ST_ID: begin
				// Latch decoded fields for EX phase
				pc_ex  <= pc_q;
				op_ex  <= op_id;
				rd_ex  <= rd_id;
				rs1_ex <= rs1_id;
				rs2_ex <= rs2_id;
				imm_ex <= imm_sext_id;

				state_q <= ST_EX;
				end

				ST_EX: begin
				if (op_ex == OP_HALT) begin
					halted  <= 1'b1;
					state_q <= ST_EX;
				end 
				else begin
					pc_q    <= pc_next;
					state_q <= ST_ID;
				end
				end
			endcase
			end
		end
	end

endmodule