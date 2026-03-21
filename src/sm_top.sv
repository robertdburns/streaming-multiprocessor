`timescale 1ns/1ps

// sm_top

module sm_top #(
  parameter int LANES      = 16,
  parameter int REGS       = 32,
  parameter int IMEM_WORDS = 256,
  parameter int DMEM_WORDS = 1024
) 
(
  input  logic clk,
  input  logic rst,
  output logic halted
);

	// IMEM wiring
	logic [$clog2(IMEM_WORDS)-1:0] imem_addr;
	logic [31:0]                   imem_rdata;

	// DMEM wiring
	logic [31:0]       dmem_addr  [0:LANES-1];
	logic [31:0]       dmem_rdata [0:LANES-1];
	logic [LANES-1:0]  dmem_we;
	logic [31:0]       dmem_wdata [0:LANES-1];

	// Debug peek wiring (simulation-only; used by helper task below)
	logic        dbg_en;
	logic [3:0]  dbg_lane;
	logic [4:0]  dbg_reg;
	logic [31:0] dbg_rdata;

	// Module Instantiation ===================================================
	// Memories
	sm_imem #(
	.WORDS(IMEM_WORDS)
	) 
	u_imem 
	(
	.addr(imem_addr),
	.rdata(imem_rdata)
	);

	sm_dmem #(
	.LANES(LANES),
	.WORDS(DMEM_WORDS)
	) 
	u_dmem 
	(
	.clk(clk),
	.addr(dmem_addr),
	.rdata(dmem_rdata),
	.we(dmem_we),
	.wdata(dmem_wdata)
	);

	// Core
	cuda_core_int #(
	.LANES(LANES),
	.REGS(REGS),
	.IMEM_WORDS(IMEM_WORDS)
	) 
	u_core 
	(
	.clk(clk),
	.rst(rst),
	.imem_addr(imem_addr),
	.imem_rdata(imem_rdata),
	.dmem_addr(dmem_addr),
	.dmem_rdata(dmem_rdata),
	.dmem_we(dmem_we),
	.dmem_wdata(dmem_wdata),

	.dbg_en(dbg_en),
	.dbg_lane(dbg_lane),
	.dbg_reg(dbg_reg),
	.dbg_rdata(dbg_rdata),

	.halted(halted)
	);


	// Simulation Helpers =====================================================
	task automatic clear_imem();
		u_imem.clear();
	endtask

	task automatic clear_dmem();
		u_dmem.clear();
	endtask

	task automatic load_imem_hex(input string path);
		u_imem.load_hex(path);
	endtask

	task automatic load_dmem_hex(input string path);
		u_dmem.load_hex(path);
	endtask

	// Init debug lines
	initial begin
		dbg_en   = 1'b0;
		dbg_lane = 4'd0;
		dbg_reg  = 5'd0;
	end

endmodule
