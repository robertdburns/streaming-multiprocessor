// Instruction Memory

module sm_imem #(
  parameter int WORDS = 256
) 
(
  input  logic [$clog2(WORDS)-1:0] addr,
  output logic [31:0]              rdata
);

	logic [31:0] mem [0:WORDS-1];

	always_comb begin
		rdata = mem[addr];
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
