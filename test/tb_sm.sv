`timescale 1ns/1ps

module tb_sm_top;
    import sm_pkg::*;

    localparam int LANES = 16;
    localparam int WARPS = 4;
    localparam int REGS = 32;
    localparam int IMEM_WORDS = 256;
    localparam int DMEM_WORDS = 1024;
    localparam int LDST_LATENCY = 12;
    localparam int MUL_LATENCY  = 5;

    logic clk;
    logic rst;
    logic halted;

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
        .rst(rst),
        .halted(halted)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    integer cycles;
    integer warp;
    integer lane;
    integer tid;
    integer expect_mul;
    integer expect_imad;
    integer expect_store;
    integer expect_sum;
    logic [31:0] got;

    initial begin
        rst = 1'b1;

        dut.clear_imem();
        dut.clear_dmem();

        // Program, executed independently by every resident warp:
        //   r1 = global thread_id = warp_id * LANES + lane_id
        //   r2 = 3
        //   r9 = 5
        //   r3 = r1 * r2                // pipelined MUL; scoreboard protects r3
        //   r4 = r1 * r2 + r9           // pipelined integer MAD/FMA-style op
        //   r5 = r3 + 7                 // dependent on MUL
        //   r6 = r1 << 2                // byte offset for dmem[tid]
        //   dmem[tid] = r5              // fixed-latency store
        //   r7 = dmem[tid]              // fixed-latency load; scoreboard protects r7
        //   r8 = r7 + r4                // dependent on load and IMAD
        //   halt this warp
        dut.poke_imem(0,  enc_i(OP_TID,  5'd1, 5'd0, 16'sd0));
        dut.poke_imem(1,  enc_i(OP_MOVI, 5'd2, 5'd0, 16'sd3));
        dut.poke_imem(2,  enc_i(OP_MOVI, 5'd9, 5'd0, 16'sd5));
        dut.poke_imem(3,  enc_r(OP_MUL,  5'd3, 5'd1, 5'd2));
        dut.poke_imem(4,  enc_mad(OP_IMAD, 5'd4, 5'd1, 5'd2, 5'd9));
        dut.poke_imem(5,  enc_i(OP_ADDI, 5'd5, 5'd3, 16'sd7));
        dut.poke_imem(6,  enc_i(OP_SHLI, 5'd6, 5'd1, 16'sd2));
        dut.poke_imem(7,  enc_s(OP_ST,   5'd5, 5'd6, 16'sd0));
        dut.poke_imem(8,  enc_i(OP_LD,   5'd7, 5'd6, 16'sd0));
        dut.poke_imem(9,  enc_r(OP_ADD,  5'd8, 5'd7, 5'd4));
        dut.poke_imem(10, enc_j(OP_HALT, 16'sd0));

        repeat (2) @(posedge clk);
        rst = 1'b0;

        cycles = 0;
        while (!halted && cycles < 3000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        if (!halted) begin
            $fatal(1, "SM did not halt within 3000 cycles");
        end

        #1;
        for (warp = 0; warp < WARPS; warp = warp + 1) begin
            for (lane = 0; lane < LANES; lane = lane + 1) begin
                tid = warp * LANES + lane;
                expect_mul = tid * 3;
                expect_imad = expect_mul + 5;
                expect_store = expect_mul + 7;
                expect_sum = expect_store + expect_imad;

                dut.peek_reg_warp(warp, lane, 5'd1, got);
                if (got !== tid) begin
                    $fatal(1, "warp %0d lane %0d r1 got %0d expected tid %0d", warp, lane, got, tid);
                end

                dut.peek_reg_warp(warp, lane, 5'd3, got);
                if (got !== expect_mul) begin
                    $fatal(1, "warp %0d lane %0d r3 got %0d expected mul %0d", warp, lane, got, expect_mul);
                end

                dut.peek_reg_warp(warp, lane, 5'd4, got);
                if (got !== expect_imad) begin
                    $fatal(1, "warp %0d lane %0d r4 got %0d expected imad %0d", warp, lane, got, expect_imad);
                end

                dut.peek_reg_warp(warp, lane, 5'd5, got);
                if (got !== expect_store) begin
                    $fatal(1, "warp %0d lane %0d r5 got %0d expected store value %0d", warp, lane, got, expect_store);
                end

                dut.peek_reg_warp(warp, lane, 5'd7, got);
                if (got !== expect_store) begin
                    $fatal(1, "warp %0d lane %0d r7 got %0d expected loaded value %0d", warp, lane, got, expect_store);
                end

                dut.peek_reg_warp(warp, lane, 5'd8, got);
                if (got !== expect_sum) begin
                    $fatal(1, "warp %0d lane %0d r8 got %0d expected %0d", warp, lane, got, expect_sum);
                end

                dut.peek_dmem(tid, got);
                if (got !== expect_store) begin
                    $fatal(1, "dmem[%0d] got %0d expected %0d", tid, got, expect_store);
                end
            end
        end

        $display("PASS: mini SM pipelined ALU + scoreboard + MUL/IMAD pipe + LSU test halted after %0d cycles", cycles);
        $finish;
    end

endmodule
