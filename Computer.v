`timescale 1ns / 1ps
`include "defs.vh"

module Computer(
    input reset,
    input clk,
    
    // --- Program Loading Ports ---
    input [7:0] ins_addr,
    input [31:0] ins,
    input done_storing,
    
    // --- Execution Status ---
    output done,
    output [31:0] total_cycles,
    output [31:0] proc_cycles,
    
    // --- LAB 8 Print I/O Ports ---
    output [31:0] out_reg1,
    output [31:0] out_reg2,
    output [31:0] out_reg3,
    output [31:0] out_reg4,
    output io_stall,
    input copied_io_regs,
    output [2:0] io_regs_index,
    
    // --- LAB 9 Keyboard I/O Ports ---
    output waiting_for_input,
    input [31:0] input_value,
    input input_value_valid
);

    // --- Internal Wires ---
    wire [7:0] pc;
    wire halt;
    wire [31:0] mem_read_data;
    
    // Memory Interface Wires from Processor
    wire [7:0] data_addr;
    wire data_addr_valid;
    wire [1:0] data_mem_command;
    wire [31:0] store_value;

    assign done = halt;

    // ==========================================
    // MEMORY MULTIPLEXER (The Traffic Controller)
    // ==========================================
    // If not done storing: Give environment access to memory to load the program.
    // If done storing AND data_addr_valid is 1: Give Processor's data lines access to memory (Load/Store).
    // If done storing AND data_addr_valid is 0: Give Processor's PC access to memory (Instruction Fetch).
    
    wire [7:0] active_mem_addr = (!done_storing) ? ins_addr : 
                                 (data_addr_valid) ? data_addr : pc;
                                 
    wire [1:0] active_mem_cmd  = (!done_storing) ? `WRITE_COMMAND : 
                                 (data_addr_valid) ? data_mem_command : `READ_COMMAND;
                                 
    wire [31:0] active_write_data = (!done_storing) ? ins : store_value;

    // --- Instantiations ---
    Memory mem (
        .reset(reset),
        .clk(clk),
        .mem_command(active_mem_cmd),
        .addr(active_mem_addr),
        .write_data(active_write_data),
        .read_data(mem_read_data)
    );

    Processor proc (
        .clk(clk),
        .halt(halt),
        .reset(reset || !done_storing),
        .pc(pc),
        .ins(mem_read_data), // Fed by memory during instruction fetch
        
        // Lab 8 Print Ports
        .io_reg1(out_reg1), 
        .io_reg2(out_reg2), 
        .io_reg3(out_reg3), 
        .io_reg4(out_reg4),
        .io_stall(io_stall), 
        .copied_io_regs(copied_io_regs), 
        .io_regs_index(io_regs_index),
        
        // Lab 9 Keyboard Ports
        .waiting_for_input(waiting_for_input),
        .input_value(input_value),
        .input_value_valid(input_value_valid),
        
        // Lab 9 Memory Ports
        .data_addr(data_addr),
        .data_addr_valid(data_addr_valid),
        .data_mem_command(data_mem_command),
        .store_value(store_value),
        .load_value(mem_read_data) // Fed by memory during data loads
    );

    // --- Performance Counters ---
    reg [31:0] total_cycles_reg;
    reg [31:0] proc_cycles_reg;
    
    always @(posedge clk) begin
        if (reset || !done_storing) begin
            total_cycles_reg <= 32'b0;
            proc_cycles_reg <= 32'b0;
        end else begin
            total_cycles_reg <= total_cycles_reg + 1;
            if (!halt && !io_stall && !waiting_for_input) begin
                proc_cycles_reg <= proc_cycles_reg + 1;
            end
        end
    end

    assign total_cycles = total_cycles_reg;
    assign proc_cycles = proc_cycles_reg;

endmodule