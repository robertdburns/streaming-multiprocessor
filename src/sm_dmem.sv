`timescale 1ns / 1ps

// Simple lane-parallel data memory. Reads and writes are synchronous; the core
// holds addresses stable while its fixed-latency LSU is busy.
module sm_dmem #(
    parameter int LANES = 16,
    parameter int WORDS = 1024
)(
    input  logic clk,
    input  logic [31:0] addr  [0:LANES-1],
    input  logic [LANES-1:0] re,
    output logic [31:0] rdata [0:LANES-1],
    input  logic [LANES-1:0] we,
    input  logic [31:0] wdata [0:LANES-1]
);

    logic [31:0] mem [0:WORDS-1];

    always_ff @(posedge clk) begin
        for (int l = 0; l < LANES; l++) begin
            int unsigned idx;
            idx = (addr[l] >> 2) % WORDS;

            if (we[l]) begin
                mem[idx] <= wdata[l];
            end

            if (re[l]) begin
                rdata[l] <= mem[idx];
            end
        end
    end

    task automatic clear();
        for (int i = 0; i < WORDS; i++) begin
            mem[i] = 32'd0;
        end
        for (int l = 0; l < LANES; l++) begin
            rdata[l] = 32'd0;
        end
    endtask

    task automatic load_hex(input string path);
        $readmemh(path, mem);
    endtask

endmodule
