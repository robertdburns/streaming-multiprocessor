`timescale 1ns/1ps

module sm_top #(
    parameter int LANES      = 16,
    parameter int WARPS      = 4,
    parameter int REGS       = 32,
    parameter int IMEM_WORDS = 256,
    parameter int DMEM_WORDS = 1024,
    parameter int LDST_LATENCY = 12,
    parameter int MUL_LATENCY  = 5,
    parameter int WARP_BITS  = (WARPS > 1) ? $clog2(WARPS) : 1,
    parameter int PC_BITS    = (IMEM_WORDS > 1) ? $clog2(IMEM_WORDS) : 1
)(
    input  logic clk,
    input  logic rst,
    output logic halted
);

    logic [PC_BITS-1:0] imem_addr;
    logic [31:0] imem_rdata;

    logic [31:0] dmem_addr  [0:LANES-1];
    logic [31:0] dmem_rdata [0:LANES-1];
    logic [LANES-1:0] dmem_re;
    logic [LANES-1:0] dmem_we;
    logic [31:0] dmem_wdata [0:LANES-1];

    logic                  dbg_en;
    logic [WARP_BITS-1:0]  dbg_warp;
    logic [3:0]            dbg_lane;
    logic [4:0]            dbg_reg;
    logic [31:0]           dbg_rdata;

    sm_imem #(
        .WORDS(IMEM_WORDS)
    ) u_imem (
        .addr(imem_addr),
        .rdata(imem_rdata)
    );

    sm_dmem #(
        .LANES(LANES),
        .WORDS(DMEM_WORDS)
    ) u_dmem (
        .clk(clk),
        .addr(dmem_addr),
        .re(dmem_re),
        .rdata(dmem_rdata),
        .we(dmem_we),
        .wdata(dmem_wdata)
    );

    cuda_core_int #(
        .LANES(LANES),
        .WARPS(WARPS),
        .REGS(REGS),
        .IMEM_WORDS(IMEM_WORDS),
        .DMEM_WORDS(DMEM_WORDS),
        .LDST_LATENCY(LDST_LATENCY),
        .MUL_LATENCY(MUL_LATENCY),
        .WARP_BITS(WARP_BITS),
        .PC_BITS(PC_BITS)
    ) u_core (
        .clk(clk),
        .rst(rst),
        .imem_rdata(imem_rdata),
        .imem_addr(imem_addr),
        .dmem_rdata(dmem_rdata),
        .dmem_addr(dmem_addr),
        .dmem_re(dmem_re),
        .dmem_we(dmem_we),
        .dmem_wdata(dmem_wdata),
        .dbg_en(dbg_en),
        .dbg_warp(dbg_warp),
        .dbg_lane(dbg_lane),
        .dbg_reg(dbg_reg),
        .dbg_rdata(dbg_rdata),
        .halted(halted)
    );

    initial begin
        dbg_en   = 1'b0;
        dbg_warp = '0;
        dbg_lane = 4'd0;
        dbg_reg  = 5'd0;
    end

    // Simulation helpers =====================================================
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

    task automatic poke_imem(input int unsigned idx, input logic [31:0] data);
        u_imem.mem[idx] = data;
    endtask

    task automatic poke_dmem(input int unsigned idx, input logic [31:0] data);
        u_dmem.mem[idx] = data;
    endtask

    task automatic peek_dmem(input int unsigned idx, output logic [31:0] data);
        data = u_dmem.mem[idx];
    endtask

    task automatic peek_reg_warp(
        input int unsigned warp,
        input int unsigned lane,
        input logic [4:0] reg_idx,
        output logic [31:0] data
    );
        dbg_warp = warp;
        dbg_lane = lane;
        dbg_reg  = reg_idx;
        dbg_en   = 1'b1;
        #1;
        data     = dbg_rdata;
        dbg_en   = 1'b0;
    endtask

    // Backward-compatible helper: inspect warp 0.
    task automatic peek_reg(
        input int unsigned lane,
        input logic [4:0] reg_idx,
        output logic [31:0] data
    );
        peek_reg_warp(0, lane, reg_idx, data);
    endtask

endmodule
