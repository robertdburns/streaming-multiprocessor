`timescale 1ns/1ps

// UVM-facing verification interface. The DUT itself only exposes clk/rst/halted,
// while its instruction/data memories and register peek helpers are simulation
// tasks inside sm_top. This interface gives UVM classes a stable BFM API; the
// concrete backdoor calls are serviced by tb_sm_uvm's command server.
interface sm_tb_if #(
    parameter int LANES      = 16,
    parameter int WARPS      = 4,
    parameter int REGS       = 32,
    parameter int IMEM_WORDS = 256,
    parameter int DMEM_WORDS = 1024
)(
    input logic clk
);
    logic rst;
    logic halted;

    import sm_pkg::*;

    sm_tb_cmd_e    cmd_kind;
    int unsigned   cmd_idx;
    int unsigned   cmd_warp;
    int unsigned   cmd_lane;
    logic [4:0]    cmd_reg;
    logic [31:0]   cmd_wdata;
    logic [31:0]   cmd_rdata;

    event cmd_req;
    event cmd_rsp;

    initial begin
        rst       = 1'b1;
        cmd_kind  = SM_CMD_NONE;
        cmd_idx   = 0;
        cmd_warp  = 0;
        cmd_lane  = 0;
        cmd_reg   = 5'd0;
        cmd_wdata = 32'd0;
        cmd_rdata = 32'd0;
    end

    task automatic apply_reset(input int unsigned cycles = 4);
        rst <= 1'b1;
        repeat (cycles) @(posedge clk);
        rst <= 1'b0;
        @(posedge clk);
    endtask

    task automatic wait_halted(
        input  int unsigned max_cycles,
        output int unsigned cycles,
        output bit          timed_out
    );
        cycles    = 0;
        timed_out = 1'b0;

        while (!halted && (cycles < max_cycles)) begin
            @(posedge clk);
            cycles++;
        end

        if (!halted) begin
            timed_out = 1'b1;
        end
    endtask

    task automatic send_cmd(input sm_tb_cmd_e kind);
        cmd_kind = kind;
        -> cmd_req;
        @cmd_rsp;
        cmd_kind = SM_CMD_NONE;
    endtask

    task automatic clear_imem();
        send_cmd(SM_CMD_CLEAR_IMEM);
    endtask

    task automatic clear_dmem();
        send_cmd(SM_CMD_CLEAR_DMEM);
    endtask

    task automatic poke_imem(input int unsigned idx, input logic [31:0] data);
        cmd_idx   = idx;
        cmd_wdata = data;
        send_cmd(SM_CMD_POKE_IMEM);
    endtask

    task automatic poke_dmem(input int unsigned idx, input logic [31:0] data);
        cmd_idx   = idx;
        cmd_wdata = data;
        send_cmd(SM_CMD_POKE_DMEM);
    endtask

    task automatic peek_dmem(input int unsigned idx, output logic [31:0] data);
        cmd_idx = idx;
        send_cmd(SM_CMD_PEEK_DMEM);
        data = cmd_rdata;
    endtask

    task automatic peek_reg_warp(
        input  int unsigned warp,
        input  int unsigned lane,
        input  logic [4:0]   reg_idx,
        output logic [31:0]  data
    );
        cmd_warp = warp;
        cmd_lane = lane;
        cmd_reg  = reg_idx;
        send_cmd(SM_CMD_PEEK_REG);
        data = cmd_rdata;
    endtask

endinterface
