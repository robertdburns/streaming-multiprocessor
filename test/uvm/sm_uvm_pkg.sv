`timescale 1ns/1ps

package sm_uvm_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import sm_pkg::*;

    localparam int UVM_LANES        = 16;
    localparam int UVM_WARPS        = 4;
    localparam int UVM_REGS         = 32;
    localparam int UVM_IMEM_WORDS   = 256;
    localparam int UVM_DMEM_WORDS   = 1024;
    localparam int UVM_LDST_LATENCY = 12;
    localparam int UVM_MUL_LATENCY  = 5;

    typedef virtual sm_tb_if #(
        UVM_LANES,
        UVM_WARPS,
        UVM_REGS,
        UVM_IMEM_WORDS,
        UVM_DMEM_WORDS
    ) sm_vif_t;

    typedef enum int unsigned {
        SM_PROG_PIPELINE_SMOKE
    } sm_program_kind_e;

    class sm_program_item extends uvm_sequence_item;
        `uvm_object_utils(sm_program_item)

        rand sm_program_kind_e kind;
        rand int unsigned     max_cycles;
        bit  [31:0]           instr_q[$];

        int unsigned          cycles;
        bit                   timed_out;

        function new(string name = "sm_program_item");
            super.new(name);
            kind       = SM_PROG_PIPELINE_SMOKE;
            max_cycles = 3000;
            cycles     = 0;
            timed_out  = 1'b0;
        endfunction

        function string convert2string();
            return $sformatf("kind=%0d instrs=%0d max_cycles=%0d cycles=%0d timed_out=%0b",
                             kind, instr_q.size(), max_cycles, cycles, timed_out);
        endfunction
    endclass

    class sm_result_item extends uvm_sequence_item;
        `uvm_object_utils(sm_result_item)

        sm_program_kind_e kind;
        int unsigned      cycles;
        bit               timed_out;

        logic [31:0] r1   [0:UVM_WARPS-1][0:UVM_LANES-1];
        logic [31:0] r3   [0:UVM_WARPS-1][0:UVM_LANES-1];
        logic [31:0] r4   [0:UVM_WARPS-1][0:UVM_LANES-1];
        logic [31:0] r5   [0:UVM_WARPS-1][0:UVM_LANES-1];
        logic [31:0] r7   [0:UVM_WARPS-1][0:UVM_LANES-1];
        logic [31:0] r8   [0:UVM_WARPS-1][0:UVM_LANES-1];
        logic [31:0] dmem [0:(UVM_WARPS*UVM_LANES)-1];

        function new(string name = "sm_result_item");
            super.new(name);
            kind      = SM_PROG_PIPELINE_SMOKE;
            cycles    = 0;
            timed_out = 1'b0;
        endfunction

        function string convert2string();
            return $sformatf("kind=%0d cycles=%0d timed_out=%0b", kind, cycles, timed_out);
        endfunction
    endclass

    class sm_sequencer extends uvm_sequencer #(sm_program_item);
        `uvm_component_utils(sm_sequencer)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
    endclass

    class sm_pipeline_smoke_sequence extends uvm_sequence #(sm_program_item);
        `uvm_object_utils(sm_pipeline_smoke_sequence)

        function new(string name = "sm_pipeline_smoke_sequence");
            super.new(name);
        endfunction

        virtual task body();
            sm_program_item tr;

            tr = sm_program_item::type_id::create("pipeline_smoke_tr");
            start_item(tr);

            tr.kind       = SM_PROG_PIPELINE_SMOKE;
            tr.max_cycles = 3000;
            tr.instr_q.delete();

            // Same architectural test as the directed bench, now driven as a
            // UVM sequence item:
            //   r1 = global thread_id = warp_id * LANES + lane_id
            //   r2 = 3
            //   r9 = 5
            //   r3 = r1 * r2
            //   r4 = r1 * r2 + r9
            //   r5 = r3 + 7
            //   r6 = r1 << 2
            //   dmem[tid] = r5
            //   r7 = dmem[tid]
            //   r8 = r7 + r4
            //   halt
            tr.instr_q.push_back(enc_i(OP_TID,  5'd1, 5'd0, 16'sd0));
            tr.instr_q.push_back(enc_i(OP_MOVI, 5'd2, 5'd0, 16'sd3));
            tr.instr_q.push_back(enc_i(OP_MOVI, 5'd9, 5'd0, 16'sd5));
            tr.instr_q.push_back(enc_r(OP_MUL,  5'd3, 5'd1, 5'd2));
            tr.instr_q.push_back(enc_mad(OP_IMAD, 5'd4, 5'd1, 5'd2, 5'd9));
            tr.instr_q.push_back(enc_i(OP_ADDI, 5'd5, 5'd3, 16'sd7));
            tr.instr_q.push_back(enc_i(OP_SHLI, 5'd6, 5'd1, 16'sd2));
            tr.instr_q.push_back(enc_s(OP_ST,   5'd5, 5'd6, 16'sd0));
            tr.instr_q.push_back(enc_i(OP_LD,   5'd7, 5'd6, 16'sd0));
            tr.instr_q.push_back(enc_r(OP_ADD,  5'd8, 5'd7, 5'd4));
            tr.instr_q.push_back(enc_j(OP_HALT, 16'sd0));

            finish_item(tr);
        endtask
    endclass

    class sm_driver extends uvm_driver #(sm_program_item);
        `uvm_component_utils(sm_driver)

        sm_vif_t vif;
        uvm_analysis_port #(sm_result_item) result_ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            result_ap = new("result_ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db #(sm_vif_t)::get(this, "", "vif", vif)) begin
                `uvm_fatal("NOVIF", "sm_driver could not get virtual sm_tb_if")
            end
        endfunction

        task run_phase(uvm_phase phase);
            sm_result_item rsp;

            forever begin
                seq_item_port.get_next_item(req);

                `uvm_info("SMDRV", $sformatf("Loading program: %s", req.convert2string()), UVM_MEDIUM)

                vif.clear_imem();
                vif.clear_dmem();

                foreach (req.instr_q[i]) begin
                    vif.poke_imem(i, req.instr_q[i]);
                end

                vif.apply_reset(4);
                vif.wait_halted(req.max_cycles, req.cycles, req.timed_out);

                rsp = sm_result_item::type_id::create("rsp");
                capture_result(req, rsp);

                `uvm_info("SMDRV", $sformatf("Program finished: %s", rsp.convert2string()), UVM_MEDIUM)
                result_ap.write(rsp);
                seq_item_port.item_done();
            end
        endtask

        task capture_result(sm_program_item req_item, sm_result_item rsp);
            int unsigned warp;
            int unsigned lane;
            int unsigned tid;

            rsp.kind      = req_item.kind;
            rsp.cycles    = req_item.cycles;
            rsp.timed_out = req_item.timed_out;

            if (req_item.timed_out) begin
                return;
            end

            case (req_item.kind)
                SM_PROG_PIPELINE_SMOKE: begin
                    for (warp = 0; warp < UVM_WARPS; warp++) begin
                        for (lane = 0; lane < UVM_LANES; lane++) begin
                            tid = warp * UVM_LANES + lane;
                            vif.peek_reg_warp(warp, lane, 5'd1, rsp.r1[warp][lane]);
                            vif.peek_reg_warp(warp, lane, 5'd3, rsp.r3[warp][lane]);
                            vif.peek_reg_warp(warp, lane, 5'd4, rsp.r4[warp][lane]);
                            vif.peek_reg_warp(warp, lane, 5'd5, rsp.r5[warp][lane]);
                            vif.peek_reg_warp(warp, lane, 5'd7, rsp.r7[warp][lane]);
                            vif.peek_reg_warp(warp, lane, 5'd8, rsp.r8[warp][lane]);
                            vif.peek_dmem(tid, rsp.dmem[tid]);
                        end
                    end
                end
                default: begin
                    // Unknown program kinds are reported by the scoreboard.
                end
            endcase
        endtask
    endclass

    class sm_scoreboard extends uvm_subscriber #(sm_result_item);
        `uvm_component_utils(sm_scoreboard)

        int unsigned checked_count;
        event checked_e;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            checked_count = 0;
        endfunction

        virtual function void write(sm_result_item item);
            case (item.kind)
                SM_PROG_PIPELINE_SMOKE: check_pipeline_smoke(item);
                default: begin
                    `uvm_error("SMSCB", $sformatf("Unknown program kind %0d", item.kind))
                end
            endcase

            checked_count++;
            -> checked_e;
        endfunction

        function void check_eq(
            input string       label,
            input int unsigned warp,
            input int unsigned lane,
            input logic [31:0] got,
            input logic [31:0] expected
        );
            if (got !== expected) begin
                `uvm_error("SMSCB", $sformatf("%s warp=%0d lane=%0d got=0x%08x expected=0x%08x",
                                             label, warp, lane, got, expected))
            end
        endfunction

        function void check_dmem_eq(
            input int unsigned idx,
            input logic [31:0] got,
            input logic [31:0] expected
        );
            if (got !== expected) begin
                `uvm_error("SMSCB", $sformatf("dmem[%0d] got=0x%08x expected=0x%08x",
                                             idx, got, expected))
            end
        endfunction

        function void check_pipeline_smoke(sm_result_item item);
            int unsigned warp;
            int unsigned lane;
            int unsigned tid;
            logic [31:0] expect_mul;
            logic [31:0] expect_imad;
            logic [31:0] expect_store;
            logic [31:0] expect_sum;

            if (item.timed_out) begin
                `uvm_error("SMSCB", $sformatf("SM did not halt within test limit; cycles=%0d", item.cycles))
                return;
            end

            for (warp = 0; warp < UVM_WARPS; warp++) begin
                for (lane = 0; lane < UVM_LANES; lane++) begin
                    tid          = warp * UVM_LANES + lane;
                    expect_mul   = tid * 3;
                    expect_imad  = expect_mul + 5;
                    expect_store = expect_mul + 7;
                    expect_sum   = expect_store + expect_imad;

                    check_eq("tid/r1",      warp, lane, item.r1[warp][lane], tid);
                    check_eq("mul/r3",      warp, lane, item.r3[warp][lane], expect_mul);
                    check_eq("imad/r4",     warp, lane, item.r4[warp][lane], expect_imad);
                    check_eq("store-src/r5",warp, lane, item.r5[warp][lane], expect_store);
                    check_eq("load-dst/r7", warp, lane, item.r7[warp][lane], expect_store);
                    check_eq("sum/r8",      warp, lane, item.r8[warp][lane], expect_sum);
                    check_dmem_eq(tid, item.dmem[tid], expect_store);
                end
            end

            `uvm_info("SMSCB", $sformatf("PASS pipeline smoke after %0d cycles", item.cycles), UVM_LOW)
        endfunction
    endclass

    class sm_env extends uvm_env;
        `uvm_component_utils(sm_env)

        sm_sequencer  sequencer;
        sm_driver     driver;
        sm_scoreboard scoreboard;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            sequencer  = sm_sequencer::type_id::create("sequencer", this);
            driver     = sm_driver::type_id::create("driver", this);
            scoreboard = sm_scoreboard::type_id::create("scoreboard", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            driver.seq_item_port.connect(sequencer.seq_item_export);
            driver.result_ap.connect(scoreboard.analysis_export);
        endfunction
    endclass

    class sm_pipeline_uvm_test extends uvm_test;
        `uvm_component_utils(sm_pipeline_uvm_test)

        sm_env env;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = sm_env::type_id::create("env", this);
        endfunction

        task run_phase(uvm_phase phase);
            sm_pipeline_smoke_sequence seq;
            int unsigned target_checked;

            phase.raise_objection(this);

            seq = sm_pipeline_smoke_sequence::type_id::create("seq");
            target_checked = env.scoreboard.checked_count + 1;
            seq.start(env.sequencer);

            while (env.scoreboard.checked_count < target_checked) begin
                @(env.scoreboard.checked_e);
            end

            phase.drop_objection(this);
        endtask
    endclass

endpackage
