// Regfile
// 2-Read / 1-Write
// Sync Reads
// x0 wired to 0

module sm_regfile #(
  parameter int REGS = 32
) 
(
  input  logic        clk,
  input  logic        rst,

  input  logic [4:0]  raddr1,
  input  logic [4:0]  raddr2,
  output logic [31:0] rdata1,
  output logic [31:0] rdata2,

  input  logic        we,
  input  logic [4:0]  waddr,
  input  logic [31:0] wdata,

  // Debug (asynchronous peek)
  input  logic        dbg_en,
  input  logic [4:0]  dbg_addr,
  output logic [31:0] dbg_data
);

	logic [31:0] regs [0:REGS-1];

	// Async debug peek
	always_comb begin
		if (!dbg_en) begin
			dbg_data = 32'd0;
		end else if (dbg_addr == 5'd0) begin
			dbg_data = 32'd0;
		end else begin
			dbg_data = regs[dbg_addr];
		end
	end

	integer i;
	always_ff @(posedge clk) begin
		if (rst) begin
			for (i = 0; i < REGS; i++) begin
			regs[i] <= 32'd0;
			end
			rdata1 <= 32'd0;
			rdata2 <= 32'd0;
		end 
		else begin
			// Write (ignore x0)
			if (we && (waddr != 5'd0)) begin
				regs[waddr] <= wdata;
		end

		// Sync reads 
		if (raddr1 == 5'd0) begin
			rdata1 <= 32'd0;
		end 
		else if (we && (waddr == raddr1) && (waddr != 5'd0)) begin
			rdata1 <= wdata;
		end 
		else begin
			rdata1 <= regs[raddr1];
		end

		if (raddr2 == 5'd0) begin
			rdata2 <= 32'd0;
		end 
		else if (we && (waddr == raddr2) && (waddr != 5'd0)) begin
			rdata2 <= wdata;
		end 
		else begin
			rdata2 <= regs[raddr2];
		end

		// Hardwire x0 = 0
		regs[0] <= 32'd0;
	end
	end

endmodule