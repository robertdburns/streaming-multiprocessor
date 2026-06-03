`timescale 1ns/1ps

// One physical SIMT lane. The same lane hardware is reused for multiple
// resident warps. The register-file read controls are separated from the ALU
// controls so the core can read operands for the next warp while the previous
// warp's instruction is in the execute/writeback stage.
module cuda_lane_core #(
    parameter int REGS = 32,
    parameter int LANES = 16,
    parameter int WARPS = 4,
    parameter int WARP_BITS = (WARPS > 1) ? $clog2(WARPS) : 1,
    parameter int unsigned LANE_ID = 0
)(
    input  logic                       clk,
    input  logic                       rst,

    // Register read controls for the currently issued warp.
    input  logic [WARP_BITS-1:0]       rf_read_warp_id,
    input  logic [4:0]                 rf_rs1_idx,
    input  logic [4:0]                 rf_rs2_idx,
    input  logic [4:0]                 rf_rs3_idx,

    // Execute controls for the instruction currently in the EX stage.
    input  logic [WARP_BITS-1:0]       alu_warp_id,
    input  sm_pkg::opcode_t            alu_op,
    input  logic signed [31:0]         alu_imm,

    // Single writeback port for this lane's architectural register file.
    input  logic                       wb_en,
    input  logic                       wb_lane_en,
    input  logic [WARP_BITS-1:0]       wb_warp_id,
    input  logic [4:0]                 wb_rd_idx,
    input  logic [31:0]                wb_data,

    // Execute-side memory address/data. The parent core decides when these are
    // latched into the load/store unit.
    output logic [31:0]                dmem_issue_addr,
    output logic [31:0]                dmem_issue_wdata,

    // Execute-side ALU result. The parent core decides whether the result
    // writes back immediately or enters a multicycle multiply/MAD pipeline.
    output logic [31:0]                alu_result,
    output logic                       alu_result_valid,

    // Expose operands for branch/control logic in the parent core.
    output logic [31:0]                rs1_val,
    output logic [31:0]                rs2_val,
    output logic [31:0]                rs3_val,

    // Simulation debug signals.
    input  logic                       dbg_en,
    input  logic [WARP_BITS-1:0]       dbg_warp,
    input  logic [4:0]                 dbg_addr,
    output logic [31:0]                dbg_data
);
    import sm_pkg::*;

    sm_regfile #(
        .REGS(REGS),
        .WARPS(WARPS),
        .WARP_BITS(WARP_BITS)
    ) u_rf (
        .clk(clk),
        .rst(rst),
        .rwarp_id(rf_read_warp_id),
        .raddr1(rf_rs1_idx),
        .raddr2(rf_rs2_idx),
        .raddr3(rf_rs3_idx),
        .rdata1(rs1_val),
        .rdata2(rs2_val),
        .rdata3(rs3_val),
        .we(wb_en && wb_lane_en),
        .wwarp_id(wb_warp_id),
        .waddr(wb_rd_idx),
        .wdata(wb_data),
        .dbg_en(dbg_en),
        .dbg_warp(dbg_warp),
        .dbg_addr(dbg_addr),
        .dbg_data(dbg_data)
    );

    logic [31:0] lane_id_32;
    logic [31:0] warp_id_32;
    logic [31:0] thread_id_32;

    assign lane_id_32   = LANE_ID;
    assign warp_id_32   = {{(32-WARP_BITS){1'b0}}, alu_warp_id};
    assign thread_id_32 = (warp_id_32 * LANES) + lane_id_32;

    sm_alu_lane u_alu (
        .op(alu_op),
        .rs1(rs1_val),
        .rs2(rs2_val),
        .rs3(rs3_val),
        .imm(alu_imm),
        .lane_id(lane_id_32),
        .warp_id(warp_id_32),
        .thread_id(thread_id_32),
        .result(alu_result),
        .result_valid(alu_result_valid)
    );

    always_comb begin
        dmem_issue_addr  = rs1_val + alu_imm;
        dmem_issue_wdata = rs2_val;
    end

endmodule
