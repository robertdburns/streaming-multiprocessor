`timescale 1ns / 1ps

module cuda_core_int #(
    parameter int LANES      = 16,
    parameter int WARPS      = 4,
    parameter int REGS       = 32,
    parameter int IMEM_WORDS = 256,
    parameter int DMEM_WORDS = 1024,
    parameter int LDST_LATENCY = 12,
    parameter int MUL_LATENCY  = 5,
    parameter bit ASSERT_UNIFORM = 1'b1,
    parameter int WARP_BITS  = (WARPS > 1) ? $clog2(WARPS) : 1,
    parameter int PC_BITS    = (IMEM_WORDS > 1) ? $clog2(IMEM_WORDS) : 1
)(
    input  logic clk,
    input  logic rst,

    // Instruction memory
    input  logic [31:0] imem_rdata,
    output logic [PC_BITS-1:0] imem_addr,

    // Data memory
    input  logic [31:0] dmem_rdata [0:LANES-1],
    output logic [31:0] dmem_addr  [0:LANES-1],
    output logic [LANES-1:0] dmem_re,
    output logic [LANES-1:0] dmem_we,
    output logic [31:0] dmem_wdata [0:LANES-1],

    // Simulation debug signals
    input  logic dbg_en,
    input  logic [WARP_BITS-1:0] dbg_warp,
    input  logic [3:0] dbg_lane,
    input  logic [4:0] dbg_reg,
    output logic [31:0] dbg_rdata,

    // Core status
    output logic halted
);
    import sm_pkg::*;

    localparam int MUL_STAGES = (MUL_LATENCY > 0) ? MUL_LATENCY : 1;
    localparam int MAX_LATENCY = (LDST_LATENCY > MUL_STAGES) ? LDST_LATENCY : MUL_STAGES;
    localparam int LAT_BITS = (MAX_LATENCY > 1) ? $clog2(MAX_LATENCY + 1) : 1;

    // One issue slot feeds one RF-read stage. The following cycle, the captured
    // metadata plus the registered RF outputs form the EX/WB stage. A warp is
    // kept in-flight until its instruction retires, which is conservative but
    // avoids same-warp ordering hazards while still allowing different resident
    // warps to fill the main ALU pipe.
    logic [PC_BITS-1:0]      warp_pc_q       [0:WARPS-1];
    logic [LANES-1:0]        warp_active_q   [0:WARPS-1];
    logic [WARPS-1:0]        warp_done_q;
    logic [WARPS-1:0]        warp_inflight_q;
    logic [WARP_BITS-1:0]    rr_q;

    // Per-warp scoreboard. Bits are set at issue and cleared at retirement or
    // delayed writeback.
    logic [REGS-1:0]         sb_busy_q       [0:WARPS-1];

    // Decode phase signals.
    logic [31:0] instr;
    opcode_t op_id;
    logic [4:0] A_id;
    logic [4:0] B_id;
    logic [4:0] C_id;
    logic [4:0] D_id;
    logic [15:0] imm16_id;
    logic signed [31:0] imm_sext_id;
    logic [4:0] rd_id;
    logic [4:0] rs1_id;
    logic [4:0] rs2_id;
    logic [4:0] rs3_id;

    // Round-robin scheduler result for the RF-read/issue phase.
    logic [WARP_BITS-1:0] sched_warp;
    logic                 sched_valid;

    function automatic logic [WARP_BITS-1:0] warp_inc(input logic [WARP_BITS-1:0] w);
        if (WARPS <= 1) begin
            warp_inc = '0;
        end else if (w == (WARPS - 1)) begin
            warp_inc = '0;
        end else begin
            warp_inc = w + 1'b1;
        end
    endfunction

    always_comb begin
        sched_warp  = '0;
        sched_valid = 1'b0;

        for (int off = 0; off < WARPS; off++) begin
            int unsigned idx;
            idx = (rr_q + off) % WARPS;
            if (!sched_valid && !warp_done_q[idx] && !warp_inflight_q[idx]) begin
                sched_warp  = idx;
                sched_valid = 1'b1;
            end
        end
    end

    assign instr     = imem_rdata;
    assign imem_addr = sched_valid ? warp_pc_q[sched_warp] : '0;

    sm_decode u_dec (
        .instr(instr),
        .op(op_id),
        .A(A_id),
        .B(B_id),
        .C(C_id),
        .D(D_id),
        .imm16(imm16_id),
        .imm_sext(imm_sext_id),
        .rd_idx(rd_id),
        .rs1_idx(rs1_id),
        .rs2_idx(rs2_id),
        .rs3_idx(rs3_id)
    );

    // Execute/writeback pipeline register. Operands are held in the lane RF
    // output registers, so this stage only needs instruction metadata.
    logic                 ex_valid_q;
    opcode_t              op_ex_q;
    logic [4:0]           rd_ex_q;
    logic [4:0]           rs1_ex_q;
    logic [4:0]           rs2_ex_q;
    logic [4:0]           rs3_ex_q;
    logic signed [31:0]   imm_ex_q;
    logic [PC_BITS-1:0]   pc_ex_q;
    logic [WARP_BITS-1:0] warp_ex_q;
    logic [LANES-1:0]     active_mask_ex_q;

    // Pending load/store unit. One warp memory instruction may be in flight.
    logic                    lsu_busy_q;
    logic                    lsu_is_load_q;
    logic [LAT_BITS-1:0]     lsu_count_q;
    logic [WARP_BITS-1:0]    lsu_warp_q;
    logic [4:0]              lsu_rd_q;
    logic [LANES-1:0]        lsu_active_q;
    logic [31:0]             lsu_addr_q  [0:LANES-1];
    logic [31:0]             lsu_wdata_q [0:LANES-1];

    // Pipelined multiply/MAD completion queue. The multiply itself is modeled
    // combinationally at launch, then delayed through MUL_STAGES registered
    // pipe stages. This gives latency MUL_LATENCY and initiation interval 1
    // unless the single RF writeback port is backpressured.
    logic                    mul_pipe_valid_q  [0:MUL_STAGES-1];
    logic [WARP_BITS-1:0]    mul_pipe_warp_q   [0:MUL_STAGES-1];
    logic [4:0]              mul_pipe_rd_q     [0:MUL_STAGES-1];
    logic [LANES-1:0]        mul_pipe_active_q [0:MUL_STAGES-1];
    logic [31:0]             mul_pipe_result_q [0:MUL_STAGES-1][0:LANES-1];

    logic lsu_complete_ready;
    logic lsu_load_wb_ready;
    logic mul_wb_ready;
    logic mul_pipe_hold;
    logic external_rf_wb_valid;
    logic mul_any_valid;
    logic mul_pipe_has_sched_warp;

    assign lsu_complete_ready  = lsu_busy_q && (lsu_count_q == 1);
    assign lsu_load_wb_ready   = lsu_complete_ready && lsu_is_load_q;
    assign mul_wb_ready        = mul_pipe_valid_q[MUL_STAGES-1];
    assign mul_pipe_hold       = lsu_load_wb_ready && mul_wb_ready;
    assign external_rf_wb_valid = lsu_load_wb_ready || mul_wb_ready;

    always_comb begin
        mul_any_valid = 1'b0;
        mul_pipe_has_sched_warp = 1'b0;
        for (int s = 0; s < MUL_STAGES; s++) begin
            if (mul_pipe_valid_q[s]) begin
                mul_any_valid = 1'b1;
                if (sched_valid && (mul_pipe_warp_q[s] == sched_warp)) begin
                    mul_pipe_has_sched_warp = 1'b1;
                end
            end
        end
    end

    // ID-stage scoreboard/structural readiness check.
    logic src1_busy_id;
    logic src2_busy_id;
    logic src3_busy_id;
    logic dst_busy_id;
    logic structural_busy_id;
    logic halt_wait_id;
    logic id_ready;

    always_comb begin
        src1_busy_id       = 1'b0;
        src2_busy_id       = 1'b0;
        src3_busy_id       = 1'b0;
        dst_busy_id        = 1'b0;
        structural_busy_id = 1'b0;
        halt_wait_id       = 1'b0;

        if (sched_valid) begin
            if (op_uses_rs1(op_id) && (rs1_id != 5'd0)) begin
                src1_busy_id = sb_busy_q[sched_warp][rs1_id];
            end

            if (op_uses_rs2(op_id) && (rs2_id != 5'd0)) begin
                src2_busy_id = sb_busy_q[sched_warp][rs2_id];
            end

            if (op_uses_rs3(op_id) && (rs3_id != 5'd0)) begin
                src3_busy_id = sb_busy_q[sched_warp][rs3_id];
            end

            if (op_writes_rd(op_id) && (rd_id != 5'd0)) begin
                dst_busy_id = sb_busy_q[sched_warp][rd_id];
            end

            // Conservative structural checks. A new memory instruction is not
            // issued if the LSU is busy or if the EX stage is about to launch a
            // memory op. MUL/IMAD can normally be issued back-to-back because
            // the multiply completion path is a registered pipe.
            if (op_is_mem(op_id)) begin
                structural_busy_id = lsu_busy_q || (ex_valid_q && op_is_mem(op_ex_q));
            end else if (op_is_mul(op_id)) begin
                structural_busy_id = mul_pipe_hold;
            end

            if (op_id == OP_HALT) begin
                halt_wait_id = (|sb_busy_q[sched_warp]) ||
                               (lsu_busy_q && (lsu_warp_q == sched_warp)) ||
                               mul_pipe_has_sched_warp;
            end
        end

        id_ready = sched_valid && !src1_busy_id && !src2_busy_id && !src3_busy_id &&
                   !dst_busy_id && !structural_busy_id && !halt_wait_id;
    end

    // EX-stage commit can proceed unless a real structural or writeback-port
    // conflict exists. External load/MUL writebacks only block EX instructions
    // that also need the RF write port this cycle.
    logic ex_structural_blocked;
    logic ex_wb_port_blocked;
    logic ex_commit_fire;
    logic issue_can_flow;
    logic issue_fire;
    logic launch_mul_ex;

    always_comb begin
        ex_structural_blocked = 1'b0;
        if (ex_valid_q && op_is_mem(op_ex_q) && lsu_busy_q) begin
            ex_structural_blocked = 1'b1;
        end
        if (ex_valid_q && op_is_mul(op_ex_q) && mul_pipe_hold) begin
            ex_structural_blocked = 1'b1;
        end
    end

    assign ex_wb_port_blocked = ex_valid_q && op_is_singlecycle_writer(op_ex_q) && external_rf_wb_valid;
    assign ex_commit_fire     = ex_valid_q && !ex_structural_blocked && !ex_wb_port_blocked;
    assign issue_can_flow     = !halted && (!ex_valid_q || ex_commit_fire);
    assign issue_fire         = issue_can_flow && id_ready;
    assign launch_mul_ex      = ex_commit_fire && op_is_mul(op_ex_q);

    // Read controls for the RF-read/issue stage.
    logic [WARP_BITS-1:0] read_warp_bus;
    logic [4:0] rs1_bus;
    logic [4:0] rs2_bus;
    logic [4:0] rs3_bus;

    always_comb begin
        read_warp_bus = sched_warp;
        rs1_bus       = rs1_id;
        rs2_bus       = rs2_id;
        rs3_bus       = rs3_id;
        if (!sched_valid) begin
            read_warp_bus = '0;
            rs1_bus       = 5'd0;
            rs2_bus       = 5'd0;
            rs3_bus       = 5'd0;
        end
    end

    logic [31:0] lane_rs1       [0:LANES-1];
    logic [31:0] lane_rs2       [0:LANES-1];
    logic [31:0] lane_rs3       [0:LANES-1];
    logic [31:0] lane_dbg       [0:LANES-1];
    logic [31:0] lane_alu_res   [0:LANES-1];
    logic        lane_alu_valid [0:LANES-1];
    logic [31:0] lane_mem_addr  [0:LANES-1];
    logic [31:0] lane_mem_wdata [0:LANES-1];

    // One writeback bus to every lane-local register file.
    logic                    wb_en_bus;
    logic [LANES-1:0]        wb_active_bus;
    logic [WARP_BITS-1:0]    wb_warp_bus;
    logic [4:0]              wb_rd_bus;
    logic [31:0]             wb_data_bus [0:LANES-1];

    always_comb begin
        wb_en_bus     = 1'b0;
        wb_active_bus = '0;
        wb_warp_bus   = '0;
        wb_rd_bus     = 5'd0;
        for (int l = 0; l < LANES; l++) begin
            wb_data_bus[l] = 32'd0;
        end

        if (lsu_load_wb_ready) begin
            wb_en_bus     = 1'b1;
            wb_active_bus = lsu_active_q;
            wb_warp_bus   = lsu_warp_q;
            wb_rd_bus     = lsu_rd_q;
            for (int l = 0; l < LANES; l++) begin
                wb_data_bus[l] = dmem_rdata[l];
            end
        end else if (mul_wb_ready) begin
            wb_en_bus     = 1'b1;
            wb_active_bus = mul_pipe_active_q[MUL_STAGES-1];
            wb_warp_bus   = mul_pipe_warp_q[MUL_STAGES-1];
            wb_rd_bus     = mul_pipe_rd_q[MUL_STAGES-1];
            for (int l = 0; l < LANES; l++) begin
                wb_data_bus[l] = mul_pipe_result_q[MUL_STAGES-1][l];
            end
        end else if (ex_commit_fire && op_is_singlecycle_writer(op_ex_q)) begin
            wb_en_bus     = 1'b1;
            wb_active_bus = active_mask_ex_q;
            wb_warp_bus   = warp_ex_q;
            wb_rd_bus     = rd_ex_q;
            for (int l = 0; l < LANES; l++) begin
                wb_data_bus[l] = lane_alu_res[l];
            end
        end
    end

    genvar gl;
    generate
        for (gl = 0; gl < LANES; gl++) begin : G_LANE
            localparam logic [3:0] LANE_IDX = gl % 16;
            logic lane_dbg_en;
            assign lane_dbg_en = dbg_en && (dbg_lane == LANE_IDX);

            cuda_lane_core #(
                .REGS(REGS),
                .LANES(LANES),
                .WARPS(WARPS),
                .WARP_BITS(WARP_BITS),
                .LANE_ID(gl)
            ) u_lane (
                .clk(clk),
                .rst(rst),
                .rf_read_warp_id(read_warp_bus),
                .rf_rs1_idx(rs1_bus),
                .rf_rs2_idx(rs2_bus),
                .rf_rs3_idx(rs3_bus),
                .alu_warp_id(warp_ex_q),
                .alu_op(op_ex_q),
                .alu_imm(imm_ex_q),
                .wb_en(wb_en_bus),
                .wb_lane_en(wb_active_bus[gl]),
                .wb_warp_id(wb_warp_bus),
                .wb_rd_idx(wb_rd_bus),
                .wb_data(wb_data_bus[gl]),
                .dmem_issue_addr(lane_mem_addr[gl]),
                .dmem_issue_wdata(lane_mem_wdata[gl]),
                .alu_result(lane_alu_res[gl]),
                .alu_result_valid(lane_alu_valid[gl]),
                .rs1_val(lane_rs1[gl]),
                .rs2_val(lane_rs2[gl]),
                .rs3_val(lane_rs3[gl]),
                .dbg_en(lane_dbg_en),
                .dbg_warp(dbg_warp),
                .dbg_addr(dbg_reg),
                .dbg_data(lane_dbg[gl])
            );
        end
    endgenerate

    always_comb begin
        dbg_rdata = 32'd0;
        for (int i = 0; i < LANES; i++) begin
            if (dbg_en && (dbg_lane == (i % 16))) begin
                dbg_rdata = lane_dbg[i];
            end
        end
    end

    // Drive the memory port from the outstanding LSU request, not directly
    // from the instruction in EX. This lets the scheduler continue issuing
    // non-memory instructions while the LSU is waiting.
    always_comb begin
        dmem_re = '0;
        dmem_we = '0;
        for (int l = 0; l < LANES; l++) begin
            dmem_addr[l]  = lsu_busy_q ? lsu_addr_q[l] : 32'd0;
            dmem_wdata[l] = lsu_busy_q ? lsu_wdata_q[l] : 32'd0;

            if (lsu_busy_q && lsu_active_q[l] && lsu_is_load_q) begin
                dmem_re[l] = 1'b1;
            end

            if (lsu_complete_ready && lsu_active_q[l] && !lsu_is_load_q) begin
                dmem_we[l] = 1'b1;
            end
        end
    end

    logic lane0_eq;
    assign lane0_eq = (lane_rs1[0] == lane_rs2[0]);

    logic [PC_BITS-1:0] pc_next;

    always_comb begin
        logic signed [31:0] pc_calc;

        pc_next = pc_ex_q + 1'b1;
        pc_calc = $signed({{(32-PC_BITS){1'b0}}, pc_ex_q}) + 32'sd1 + imm_ex_q;

        unique case (op_ex_q)
            OP_BRA: begin
                pc_next = pc_calc[PC_BITS-1:0];
            end

            OP_BEQ: begin
                if (lane0_eq) begin
                    pc_next = pc_calc[PC_BITS-1:0];
                end
            end

            default: begin
                // Sequential PC already assigned.
            end
        endcase
    end

    logic all_warps_done;
    always_comb begin
        all_warps_done = 1'b1;
        for (int w = 0; w < WARPS; w++) begin
            if (!warp_done_q[w]) begin
                all_warps_done = 1'b0;
            end
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (!rst && ASSERT_UNIFORM && ex_commit_fire && (op_ex_q == OP_BEQ)) begin
            for (int i = 1; i < LANES; i++) begin
                if (active_mask_ex_q[i] && ((lane_rs1[i] != lane_rs1[0]) || (lane_rs2[i] != lane_rs2[0]))) begin
                    $warning("Non-uniform BEQ operands in warp %0d: lane 0 decides branch direction in this core", warp_ex_q);
                end
            end
        end
    end
`endif

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int w = 0; w < WARPS; w++) begin
                warp_pc_q[w]       <= '0;
                warp_active_q[w]   <= {LANES{1'b1}};
                sb_busy_q[w]       <= '0;
            end
            warp_done_q      <= '0;
            warp_inflight_q  <= '0;
            rr_q             <= '0;

            ex_valid_q       <= 1'b0;
            pc_ex_q          <= '0;
            warp_ex_q        <= '0;
            active_mask_ex_q <= '0;
            op_ex_q          <= OP_NOP;
            rd_ex_q          <= '0;
            rs1_ex_q         <= '0;
            rs2_ex_q         <= '0;
            rs3_ex_q         <= '0;
            imm_ex_q         <= 32'sd0;
            halted           <= 1'b0;

            lsu_busy_q       <= 1'b0;
            lsu_is_load_q    <= 1'b0;
            lsu_count_q      <= '0;
            lsu_warp_q       <= '0;
            lsu_rd_q         <= 5'd0;
            lsu_active_q     <= '0;

            for (int s = 0; s < MUL_STAGES; s++) begin
                mul_pipe_valid_q[s]  <= 1'b0;
                mul_pipe_warp_q[s]   <= '0;
                mul_pipe_rd_q[s]     <= 5'd0;
                mul_pipe_active_q[s] <= '0;
            end

            for (int l = 0; l < LANES; l++) begin
                lsu_addr_q[l]  <= 32'd0;
                lsu_wdata_q[l] <= 32'd0;
                for (int s = 0; s < MUL_STAGES; s++) begin
                    mul_pipe_result_q[s][l] <= 32'd0;
                end
            end
        end else if (!halted) begin
            // Complete or advance the outstanding LSU.
            if (lsu_busy_q) begin
                if (lsu_complete_ready) begin
                    lsu_busy_q <= 1'b0;
                    warp_inflight_q[lsu_warp_q] <= 1'b0;
                    if (lsu_is_load_q && (lsu_rd_q != 5'd0)) begin
                        sb_busy_q[lsu_warp_q][lsu_rd_q] <= 1'b0;
                    end
                end else begin
                    lsu_count_q <= lsu_count_q - 1'b1;
                end
            end

            // Retire the last multiply/MAD pipe stage if it wins the RF port.
            if (mul_wb_ready && !lsu_load_wb_ready) begin
                warp_inflight_q[mul_pipe_warp_q[MUL_STAGES-1]] <= 1'b0;
                if (mul_pipe_rd_q[MUL_STAGES-1] != 5'd0) begin
                    sb_busy_q[mul_pipe_warp_q[MUL_STAGES-1]][mul_pipe_rd_q[MUL_STAGES-1]] <= 1'b0;
                end
            end

            // Shift the multiply/MAD completion pipe. If a load and MUL result
            // both want the RF port, hold the whole pipe for one cycle.
            if (!mul_pipe_hold) begin
                for (int s = MUL_STAGES-1; s > 0; s--) begin
                    mul_pipe_valid_q[s]  <= mul_pipe_valid_q[s-1];
                    mul_pipe_warp_q[s]   <= mul_pipe_warp_q[s-1];
                    mul_pipe_rd_q[s]     <= mul_pipe_rd_q[s-1];
                    mul_pipe_active_q[s] <= mul_pipe_active_q[s-1];
                    for (int l = 0; l < LANES; l++) begin
                        mul_pipe_result_q[s][l] <= mul_pipe_result_q[s-1][l];
                    end
                end

                mul_pipe_valid_q[0]  <= launch_mul_ex;
                mul_pipe_warp_q[0]   <= warp_ex_q;
                mul_pipe_rd_q[0]     <= rd_ex_q;
                mul_pipe_active_q[0] <= active_mask_ex_q;
                for (int l = 0; l < LANES; l++) begin
                    mul_pipe_result_q[0][l] <= launch_mul_ex ? lane_alu_res[l] : 32'd0;
                end
            end

            // Retire/launch the current EX-stage instruction.
            if (ex_commit_fire) begin
                if (op_ex_q == OP_HALT) begin
                    warp_done_q[warp_ex_q]     <= 1'b1;
                    warp_inflight_q[warp_ex_q] <= 1'b0;
                end else begin
                    warp_pc_q[warp_ex_q] <= pc_next;

                    if (op_is_load(op_ex_q)) begin
                        lsu_busy_q    <= 1'b1;
                        lsu_is_load_q <= 1'b1;
                        lsu_count_q   <= LDST_LATENCY;
                        lsu_warp_q    <= warp_ex_q;
                        lsu_rd_q      <= rd_ex_q;
                        lsu_active_q  <= active_mask_ex_q;
                        for (int l = 0; l < LANES; l++) begin
                            lsu_addr_q[l]  <= lane_mem_addr[l];
                            lsu_wdata_q[l] <= 32'd0;
                        end
                    end else if (op_is_store(op_ex_q)) begin
                        lsu_busy_q    <= 1'b1;
                        lsu_is_load_q <= 1'b0;
                        lsu_count_q   <= LDST_LATENCY;
                        lsu_warp_q    <= warp_ex_q;
                        lsu_rd_q      <= 5'd0;
                        lsu_active_q  <= active_mask_ex_q;
                        for (int l = 0; l < LANES; l++) begin
                            lsu_addr_q[l]  <= lane_mem_addr[l];
                            lsu_wdata_q[l] <= lane_mem_wdata[l];
                        end
                    end else if (op_is_mul(op_ex_q)) begin
                        // Result was pushed into mul_pipe stage 0 above.
                    end else begin
                        warp_inflight_q[warp_ex_q] <= 1'b0;
                        if (op_is_singlecycle_writer(op_ex_q) && (rd_ex_q != 5'd0)) begin
                            sb_busy_q[warp_ex_q][rd_ex_q] <= 1'b0;
                        end
                    end
                end
            end

            // Main ALU pipe register update. On a retiring EX instruction and
            // a valid issue in the same cycle, the new instruction immediately
            // occupies EX for the following cycle.
            if (issue_fire) begin
                ex_valid_q       <= 1'b1;
                pc_ex_q          <= warp_pc_q[sched_warp];
                warp_ex_q        <= sched_warp;
                active_mask_ex_q <= warp_active_q[sched_warp];
                op_ex_q          <= op_id;
                rd_ex_q          <= rd_id;
                rs1_ex_q         <= rs1_id;
                rs2_ex_q         <= rs2_id;
                rs3_ex_q         <= rs3_id;
                imm_ex_q         <= imm_sext_id;

                warp_inflight_q[sched_warp] <= 1'b1;
                rr_q <= warp_inc(sched_warp);

                if (op_writes_rd(op_id) && (rd_id != 5'd0)) begin
                    sb_busy_q[sched_warp][rd_id] <= 1'b1;
                end
            end else if (ex_commit_fire) begin
                ex_valid_q <= 1'b0;
            end else if (issue_can_flow && sched_valid) begin
                // The probed warp was blocked by its scoreboard or by a
                // conservative structural check. Probe the next warp next cycle.
                rr_q <= warp_inc(sched_warp);
            end

            if (all_warps_done && !ex_valid_q && !lsu_busy_q && !mul_any_valid) begin
                halted <= 1'b1;
            end
        end
    end

endmodule
