// Register file
// 3-read / 1-write, one architectural register context per resident warp.
// x0 is hardwired to 0 for every warp.

module sm_regfile #(
  parameter int REGS = 32,
  parameter int WARPS = 4,
  parameter int WARP_BITS = (WARPS > 1) ? $clog2(WARPS) : 1
)(
  input  logic                       clk,
  input  logic                       rst,

  // Read side: selected by the currently issued warp.
  input  logic [WARP_BITS-1:0]       rwarp_id,
  input  logic [4:0]                 raddr1,
  input  logic [4:0]                 raddr2,
  input  logic [4:0]                 raddr3,
  output logic [31:0]                rdata1,
  output logic [31:0]                rdata2,
  output logic [31:0]                rdata3,

  // Write side: selected by the writeback producer. This may be a different
  // warp than rwarp_id when a pending load or multiply pipeline completes.
  input  logic                       we,
  input  logic [WARP_BITS-1:0]       wwarp_id,
  input  logic [4:0]                 waddr,
  input  logic [31:0]                wdata,

  // Debug: asynchronous peek into any warp context.
  input  logic                       dbg_en,
  input  logic [WARP_BITS-1:0]       dbg_warp,
  input  logic [4:0]                 dbg_addr,
  output logic [31:0]                dbg_data
);

    logic [31:0] regs [0:WARPS-1][0:REGS-1];

    // Async debug peek.
    always_comb begin
        if (!dbg_en) begin
            dbg_data = 32'd0;
        end else if (dbg_addr == 5'd0) begin
            dbg_data = 32'd0;
        end else begin
            dbg_data = regs[dbg_warp][dbg_addr];
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int w = 0; w < WARPS; w++) begin
                for (int r = 0; r < REGS; r++) begin
                    regs[w][r] <= 32'd0;
                end
            end
            rdata1 <= 32'd0;
            rdata2 <= 32'd0;
            rdata3 <= 32'd0;
        end else begin
            // Write selected warp context. Ignore x0.
            if (we && (waddr != 5'd0)) begin
                regs[wwarp_id][waddr] <= wdata;
            end

            // Synchronous read selected warp context, with same-cycle bypass
            // when the writeback targets the same warp and register.
            if (raddr1 == 5'd0) begin
                rdata1 <= 32'd0;
            end else if (we && (wwarp_id == rwarp_id) && (waddr == raddr1) && (waddr != 5'd0)) begin
                rdata1 <= wdata;
            end else begin
                rdata1 <= regs[rwarp_id][raddr1];
            end

            if (raddr2 == 5'd0) begin
                rdata2 <= 32'd0;
            end else if (we && (wwarp_id == rwarp_id) && (waddr == raddr2) && (waddr != 5'd0)) begin
                rdata2 <= wdata;
            end else begin
                rdata2 <= regs[rwarp_id][raddr2];
            end

            if (raddr3 == 5'd0) begin
                rdata3 <= 32'd0;
            end else if (we && (wwarp_id == rwarp_id) && (waddr == raddr3) && (waddr != 5'd0)) begin
                rdata3 <= wdata;
            end else begin
                rdata3 <= regs[rwarp_id][raddr3];
            end

            // Keep x0 at 0 for every resident warp.
            for (int w = 0; w < WARPS; w++) begin
                regs[w][0] <= 32'd0;
            end
        end
    end

endmodule
