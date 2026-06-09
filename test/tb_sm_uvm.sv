`timescale 1ns/1ps

module tb_sm_uvm;
    import uvm_pkg::*;
    import sm_pkg::*;
    import sm_uvm_pkg::*;

    localparam int LANES        = UVM_LANES;
    localparam int WARPS        = UVM_WARPS;
    localparam int REGS         = UVM_REGS;
    localparam int IMEM_WORDS   = UVM_IMEM_WORDS;
    localparam int DMEM_WORDS   = UVM_DMEM_WORDS;
    localparam int LDST_LATENCY = UVM_LDST_LATENCY;
    localparam int MUL_LATENCY  = UVM_MUL_LATENCY;

    logic clk;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    sm_tb_if #(
        .LANES(LANES),
        .WARPS(WARPS),
        .REGS(REGS),
        .IMEM_WORDS(IMEM_WORDS),
        .DMEM_WORDS(DMEM_WORDS)
    ) tb_if (
        .clk(clk)
    );

    sm_top #(
        .LANES(LANES),
        .WARPS(WARPS),
        .REGS(REGS),
        .IMEM_WORDS(IMEM_WORDS),
        .DMEM_WORDS(DMEM_WORDS),
        .LDST_LATENCY(LDST_LATENCY),
        .MUL_LATENCY(MUL_LATENCY)
    ) dut (
        .clk(clk),
        .rst(tb_if.rst),
        .halted(tb_if.halted)
    );

    initial begin : command_server
        forever begin
            @(tb_if.cmd_req);
            case (tb_if.cmd_kind)
                SM_CMD_CLEAR_IMEM: begin
                    dut.clear_imem();
                end
                SM_CMD_CLEAR_DMEM: begin
                    dut.clear_dmem();
                end
                SM_CMD_POKE_IMEM: begin
                    dut.poke_imem(tb_if.cmd_idx, tb_if.cmd_wdata);
                end
                SM_CMD_POKE_DMEM: begin
                    dut.poke_dmem(tb_if.cmd_idx, tb_if.cmd_wdata);
                end
                SM_CMD_PEEK_DMEM: begin
                    dut.peek_dmem(tb_if.cmd_idx, tb_if.cmd_rdata);
                end
                SM_CMD_PEEK_REG: begin
                    dut.peek_reg_warp(tb_if.cmd_warp, tb_if.cmd_lane, tb_if.cmd_reg, tb_if.cmd_rdata);
                end
                default: begin
                    // No command.
                end
            endcase
            -> tb_if.cmd_rsp;
        end
    end

    initial begin
        uvm_config_db #(sm_vif_t)::set(null, "*", "vif", tb_if);
        run_test("sm_pipeline_uvm_test");
    end

endmodule
