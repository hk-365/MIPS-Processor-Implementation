`timescale 1ns / 1ps
`include "defs.vh"

module Memory(
    input reset,
    input clk,
    input [1:0] mem_command,
    input [7:0] addr,           
    input [31:0] write_data,
    output [31:0] read_data     // Note: Changed from 'output reg' to 'output'
);

    reg [31:0] mem_array [0:255]; 
    integer i;

    // --- Combinational Read Port ---
    // Vivado will now correctly infer ultra-fast Distributed RAM
    assign read_data = mem_array[addr];

    // --- Sequential Write Port ---
    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 256; i = i + 1) begin
                mem_array[i] <= 32'b0;
            end
        end
        else begin
            case (mem_command)
                `WRITE_COMMAND:         mem_array[addr] <= write_data;
                `SUBWORD_WRITE_COMMAND: mem_array[addr] <= write_data;
            endcase
        end
    end

endmodule