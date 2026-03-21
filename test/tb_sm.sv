`timescale 1ns/1ps

module tb_sm_top;
	import sm_pkg::*;

	localparam int LANES      = 16;
	localparam int REGS       = 32;
	localparam int IMEM_WORDS = 256;
	localparam int DMEM_WORDS = 1024;

	logic clk;
	logic rst;
	logic halted;

	sm_top #(
	.LANES(LANES),
	.REGS(REGS),
	.IMEM_WORDS(IMEM_WORDS),
	.DMEM_WORDS(DMEM_WORDS)
	) 
	dut 
	(
	.clk(clk),
	.rst(rst),
	.halted(halted)
	);

	// Clock
	initial clk = 1'b0;
	always #10 clk = ~clk;

endmodule