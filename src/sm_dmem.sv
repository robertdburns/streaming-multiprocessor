`timescale 1ns / 1ps
// Global Data Memory Module

module sm_dmem #(
  parameter int LANES = 16,
  parameter int WORDS = 1024
) 
(
  input  logic        clk,

  input  logic [31:0] addr  [0:LANES-1],
  output logic [31:0] rdata [0:LANES-1],

  input  logic [LANES-1:0] we,
  input  logic [31:0]      wdata [0:LANES-1]
);

  logic [31:0] mem [0:WORDS-1];

  	// Combinational reads 
	integer lr;
	always_comb begin
		for (lr = 0; lr < LANES; lr++) begin
			int unsigned idx;
			idx      = (int unsigned'(addr[lr]) >> 2) % WORDS;
			rdata[lr]= mem[idx];
		end
	end

  	// Synchronous writes 
	always_ff @(posedge clk) begin
		for (lr = 0; lr < LANES; lr++) begin
			if (we[lr]) begin
			int unsigned idx;
			idx = (int unsigned'(addr[lr]) >> 2) % WORDS;
			mem[idx] <= wdata[lr];
			end
		end
	end

	// Simulation Helper ======================================================
	task automatic clear();
		int i;
		for (i = 0; i < WORDS; i++) begin
			mem[i] = 32'd0;
		end
	endtask

	task automatic load_hex(input string path);
		$readmemh(path, mem);
	endtask

endmodule