`timescale 1ns / 1ps
`include "defs.vh"

module Processor(
    input clk, 
    output halt, 
    input reset, 
    output reg [7:0] pc, 
    input [31:0] ins, 
    
    // --- LAB 8 I/O PORTS ---
    output [31:0] io_reg1, 
    output [31:0] io_reg2, 
    output [31:0] io_reg3, 
    output [31:0] io_reg4,
    output reg io_stall,           
    input copied_io_regs,          
    output [2:0] io_regs_index,
    
    // --- LAB 9 KEYBOARD I/O PORTS ---
    output reg waiting_for_input,
    input [31:0] input_value,
    input input_value_valid,
    
    // --- LAB 9 MEMORY PORTS ---
    output [7:0] data_addr,
    output data_addr_valid,
    output [1:0] data_mem_command,
    output [31:0] store_value,
    input [31:0] load_value
);

    // --- Combinational Wires (Cycle 1) ---
    wire [5:0] opcode = ins[31:26];             
    wire [5:0] func = ins[5:0];               
    wire [4:0] shift_amount = ins[10:6];       
    wire [4:0] src1_addr = ins[25:21];          
    wire [4:0] src2_addr = ins[20:16];          
    wire [31:0] src1;              
    wire [31:0] src2;              
    wire [4:0] dest_addr;          
    wire [15:0] imm = ins[15:0];               
    wire [25:0] jump_target = ins[25:0];
    wire [4:0] rt = ins[20:16];
    wire [31:0] branch_offset;

    // --- Inter-Stage Registers (Cycle 1 -> Cycle 2) ---
    reg [5:0]  opcode_reg;
    reg [5:0]  func_reg;
    reg [4:0]  shift_amount_reg;
    reg [31:0] src1_reg;
    reg [31:0] src2_reg; // Holds raw Register rt value for Stores
    reg [31:0] alu_src2_reg;
    reg [4:0]  dest_addr_reg;
    reg [31:0] branch_offset_reg;
    reg [4:0]  rt_reg;
    reg [25:0] jump_target_reg;

    // --- Combinational Wires (Cycle 2) ---
    wire [31:0] dest_data;         
    wire dest_data_valid;          
    wire branch_taken;

    // --- Inter-Stage Registers (Cycle 2 -> Cycle 3) ---
    reg [31:0] dest_data_reg;
    reg dest_valid_reg;
    reg [7:0]  next_pc_reg; 

    // --- FSM States ---
    reg [1:0] state;
    localparam S_FETCH_READ = 2'd0;
    localparam S_EXECUTE    = 2'd1;
    localparam S_WRITEBACK  = 2'd2;

    // --- System / Control Registers ---
    reg [31:0] io_reg [0:3];       
    reg [2:0] io_reg_index;        
    reg fetched;                   
    reg halt_reg;
    reg wait_for_zero;             
    reg wait_for_input_clear;

    assign halt = halt_reg;
    assign io_reg1 = io_reg[0];
    assign io_reg2 = io_reg[1];
    assign io_reg3 = io_reg[2];
    assign io_reg4 = io_reg[3];
    assign io_regs_index = io_reg_index; 

    // --- Decode Instruction ---
    assign dest_addr = (opcode == `OP_JAL) ? 5'd31 : 
                       ((opcode == `OP_REG) && (func == `FUNC_JALR)) ? 5'd31 : 
                       (opcode == `OP_REG) ? ins[15:11] : ins[20:16]; 

    wire [31:0] sign_ext_imm = {{16{imm[15]}}, imm}; 
    wire [31:0] zero_ext_imm = {16'b0, imm};         
    
    assign branch_offset = ((opcode == `OP_J) || (opcode == `OP_JAL)) ? {6'b0, jump_target} : 
                           (opcode == `OP_LUI) ? zero_ext_imm : sign_ext_imm;

    wire [31:0] alu_src2 = ((opcode == `OP_REG) || (opcode == `OP_BEQ) || (opcode == `OP_BNE)) ? src2 : 
                           ((opcode == `OP_ANDI) || (opcode == `OP_ORI) || (opcode == `OP_XORI)) ? zero_ext_imm : 
                           sign_ext_imm;

    // --- Instantiations ---
    RegisterFile rf (
        src1_addr, src2_addr, src1, src2, 
        dest_addr_reg, dest_data_reg, dest_valid_reg, clk
    );

    ALU alu (
        src1_reg, alu_src2_reg, shift_amount_reg, 
        opcode_reg, func_reg, pc, branch_offset_reg, rt_reg,
        dest_data, dest_data_valid, branch_taken    
    );

    // ==========================================
    // LAB 9: MEMORY ROUTING LOGIC (Combinational)
    // ==========================================
    
    assign data_addr = dest_data[9:2]; // Word address derived from ALU byte address
    assign data_addr_valid = (state == S_EXECUTE) && (opcode_reg == `OP_LW || opcode_reg == `OP_LB || opcode_reg == `OP_LBU || opcode_reg == `OP_LH || opcode_reg == `OP_LHU || opcode_reg == `OP_SW || opcode_reg == `OP_SB || opcode_reg == `OP_SH);

    // 1. Memory Command Mapping
    reg [1:0] mem_cmd;
    always @(*) begin
        if (state == S_EXECUTE) begin
            if (opcode_reg == `OP_SW) mem_cmd = `WRITE_COMMAND;
            else if (opcode_reg == `OP_SB || opcode_reg == `OP_SH) mem_cmd = `SUBWORD_WRITE_COMMAND;
            else mem_cmd = `READ_COMMAND;
        end else begin
            mem_cmd = `READ_COMMAND;
        end
    end
    assign data_mem_command = mem_cmd;

    // 2. Subword Merging for Stores (Big Endian)
    reg [31:0] st_val;
    always @(*) begin
        if (opcode_reg == `OP_SW) begin
            st_val = src2_reg; // Store full word
        end else if (opcode_reg == `OP_SB) begin
            case (dest_data[1:0])
                2'b00: st_val = {src2_reg[7:0], load_value[23:0]};
                2'b01: st_val = {load_value[31:24], src2_reg[7:0], load_value[15:0]};
                2'b10: st_val = {load_value[31:16], src2_reg[7:0], load_value[7:0]};
                2'b11: st_val = {load_value[31:8], src2_reg[7:0]};
            endcase
        end else if (opcode_reg == `OP_SH) begin
            if (dest_data[1] == 1'b0) st_val = {src2_reg[15:0], load_value[15:0]};
            else st_val = {load_value[31:16], src2_reg[15:0]};
        end else begin
            st_val = 32'b0;
        end
    end
    assign store_value = st_val;

    // 3. Subword Extraction for Loads (Big Endian)
    reg [31:0] loaded_data;
    always @(*) begin
        case (opcode_reg)
            `OP_LW: loaded_data = load_value;
            `OP_LB: begin
                case (dest_data[1:0])
                    2'b00: loaded_data = {{24{load_value[31]}}, load_value[31:24]};
                    2'b01: loaded_data = {{24{load_value[23]}}, load_value[23:16]};
                    2'b10: loaded_data = {{24{load_value[15]}}, load_value[15:8]};
                    2'b11: loaded_data = {{24{load_value[7]}}, load_value[7:0]};
                endcase
            end
            `OP_LBU: begin
                case (dest_data[1:0])
                    2'b00: loaded_data = {24'b0, load_value[31:24]};
                    2'b01: loaded_data = {24'b0, load_value[23:16]};
                    2'b10: loaded_data = {24'b0, load_value[15:8]};
                    2'b11: loaded_data = {24'b0, load_value[7:0]};
                endcase
            end
            `OP_LH: begin
                if (dest_data[1] == 1'b0) loaded_data = {{16{load_value[31]}}, load_value[31:16]};
                else loaded_data = {{16{load_value[15]}}, load_value[15:0]};
            end
            `OP_LHU: begin
                if (dest_data[1] == 1'b0) loaded_data = {16'b0, load_value[31:16]};
                else loaded_data = {16'b0, load_value[15:0]};
            end
            default: loaded_data = dest_data; 
        endcase
    end


    // ==========================================
    // FSM LOGIC
    // ==========================================
    always @(posedge clk) begin
        if (reset) begin
            pc <= 8'b0;
            io_reg_index <= 3'b0;
            fetched <= 1'b0;
            state <= S_FETCH_READ;
            halt_reg <= 1'b0;
            dest_valid_reg <= 1'b0;
            io_stall <= 1'b0;
            wait_for_zero <= 1'b0;
            waiting_for_input <= 1'b0;
            wait_for_input_clear <= 1'b0;
            next_pc_reg <= 8'b0;
        end
        else begin
            case (state)
                S_FETCH_READ: begin
                    fetched <= 1'b1;
                    if (!halt_reg) begin
                        opcode_reg <= opcode;
                        func_reg <= func;
                        shift_amount_reg <= shift_amount;
                        src1_reg <= src1;
                        src2_reg <= src2; // Save raw Register value for Stores
                        alu_src2_reg <= alu_src2;
                        dest_addr_reg <= dest_addr;
                        branch_offset_reg <= branch_offset;
                        rt_reg <= rt;
                        jump_target_reg <= jump_target;
                        
                        state <= S_EXECUTE;
                    end
                end

                S_EXECUTE: begin
                    // 1. Keyboard Input Stalling Logic (Lab 9)
                    if ((opcode_reg == `OP_REG) && (func_reg == `FUNC_SYSCALL) && (src1_reg == `SYS_read) && !waiting_for_input && !wait_for_input_clear) begin
                        waiting_for_input <= 1'b1;
                    end
                    else if (waiting_for_input && input_value_valid) begin
                        waiting_for_input <= 1'b0;
                        dest_data_reg <= input_value; // Capture keyboard input
                        dest_valid_reg <= 1'b1;       // Needs to write to regfile[rd]
                        next_pc_reg <= pc + 1;
                        wait_for_input_clear <= 1'b1;
                    end
                    else if (wait_for_input_clear && !input_value_valid) begin
                        wait_for_input_clear <= 1'b0;
                        state <= S_WRITEBACK;
                    end
                    
                    // 2. Print Output Stalling Logic (Lab 8)
                    else if ((opcode_reg == `OP_REG) && (func_reg == `FUNC_SYSCALL) && (src1_reg == `SYS_write) && (io_reg_index == 3'd4) && !io_stall && !wait_for_zero) begin
                        io_stall <= 1'b1;
                    end 
                    else if (io_stall && copied_io_regs) begin
                        io_stall <= 1'b0;
                        io_reg_index <= 3'd0; 
                        wait_for_zero <= 1'b1;
                    end 
                    else if (wait_for_zero && !copied_io_regs) begin
                        wait_for_zero <= 1'b0;
                    end 
                    
                    // 3. Normal Execution
                    else if (!io_stall && !wait_for_zero && !waiting_for_input && !wait_for_input_clear) begin
                        
                        // Handle Write System Call Array Writing
                        if ((opcode_reg == `OP_REG) && (func_reg == `FUNC_SYSCALL) && (src1_reg == `SYS_write)) begin
                            io_reg[io_reg_index] <= alu_src2_reg;
                            io_reg_index <= io_reg_index + 1;
                        end

                        // If memory load, select 'loaded_data'. Otherwise, select ALU 'dest_data'
                        if (opcode_reg == `OP_LW || opcode_reg == `OP_LB || opcode_reg == `OP_LBU || opcode_reg == `OP_LH || opcode_reg == `OP_LHU) begin
                            dest_data_reg <= loaded_data;
                            dest_valid_reg <= 1'b1; // Memory load always writes to RF
                        end else begin
                            dest_data_reg <= dest_data;
                            dest_valid_reg <= dest_data_valid;
                        end
                        
                        // Handle Control Flow
                        if (branch_taken) begin
                            if (opcode_reg == `OP_JAL) next_pc_reg <= jump_target_reg[7:0];
                            else if ((opcode_reg == `OP_REG) && (func_reg == `FUNC_JALR)) next_pc_reg <= src1_reg[7:0];
                            else next_pc_reg <= dest_data[7:0]; 
                        end else begin
                            next_pc_reg <= pc + 1; 
                        end

                        if ((opcode_reg == `OP_REG) && (func_reg == `FUNC_SYSCALL) && (src1_reg == `SYS_exit)) begin
                            halt_reg <= 1'b1;
                        end
                        
                        state <= S_WRITEBACK;
                    end
                end

                S_WRITEBACK: begin
                    dest_valid_reg <= 1'b0; 
                    if (!halt_reg) begin
                        pc <= next_pc_reg; 
                        state <= S_FETCH_READ;
                    end
                end
            endcase
        end
    end
endmodule