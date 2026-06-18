`timescale 1ns / 1ps
`include "defs.vh"

module ALU (
    input [31:0] src1, 
    input [31:0] src2, 
    input [4:0] shift_amount, 
    input [5:0] opcode, 
    input [5:0] func, 
    input [7:0] pc,              
    input [31:0] branch_offset,  
    input [4:0] rt,              
    output reg [31:0] dest, 
    output reg dest_valid,
    output reg branch_taken      
);

    always @(*) begin
        // Default assignments to prevent latches
        dest = 32'b0;
        dest_valid = 1'b0;
        branch_taken = 1'b0;

        case (opcode)
            // ==========================================
            // R-TYPE INSTRUCTIONS
            // ==========================================
            `OP_REG: begin
                case (func)
                    `FUNC_SLL:  begin dest = src2 << shift_amount; dest_valid = 1'b1; end
                    `FUNC_SRL:  begin dest = src2 >> shift_amount; dest_valid = 1'b1; end
                    `FUNC_SRA:  begin dest = $signed(src2) >>> shift_amount; dest_valid = 1'b1; end
                    `FUNC_SLLV: begin dest = src2 << src1[4:0]; dest_valid = 1'b1; end
                    `FUNC_SRLV: begin dest = src2 >> src1[4:0]; dest_valid = 1'b1; end
                    `FUNC_SRAV: begin dest = $signed(src2) >>> src1[4:0]; dest_valid = 1'b1; end
                    
                    `FUNC_ADD:  begin dest = src1 + src2; dest_valid = 1'b1; end
                    `FUNC_SUB:  begin dest = src1 - src2; dest_valid = 1'b1; end
                    `FUNC_AND:  begin dest = src1 & src2; dest_valid = 1'b1; end
                    `FUNC_OR:   begin dest = src1 | src2; dest_valid = 1'b1; end
                    `FUNC_XOR:  begin dest = src1 ^ src2; dest_valid = 1'b1; end
                    `FUNC_NOR:  begin dest = ~(src1 | src2); dest_valid = 1'b1; end
                    
                    `FUNC_SLT:  begin dest = ($signed(src1) < $signed(src2)) ? 32'd1 : 32'd0; dest_valid = 1'b1; end
                    `FUNC_SLTU: begin dest = (src1 < src2) ? 32'd1 : 32'd0; dest_valid = 1'b1; end
                    
                    `FUNC_JR: begin 
                        dest = src1;          
                        branch_taken = 1'b1;  
                        dest_valid = 1'b0;    
                    end
                    `FUNC_JALR: begin 
                        dest = {24'b0, pc} + 32'd1; 
                        branch_taken = 1'b1;        
                        dest_valid = 1'b1;          
                    end
                    
                    `FUNC_SYSCALL: begin 
                        dest = 32'b0; 
                        dest_valid = 1'b0; 
                    end
                endcase
            end
            
            // ==========================================
            // I-TYPE INSTRUCTIONS (Arithmetic & Logic)
            // ==========================================
            `OP_ADDI: begin dest = src1 + src2; dest_valid = 1'b1; end 
            `OP_ANDI: begin dest = src1 & src2; dest_valid = 1'b1; end
            `OP_ORI:  begin dest = src1 | src2; dest_valid = 1'b1; end
            `OP_XORI: begin dest = src1 ^ src2; dest_valid = 1'b1; end
            
            `OP_SLTI:  begin dest = ($signed(src1) < $signed(branch_offset)) ? 32'd1 : 32'd0; dest_valid = 1'b1; end
            `OP_SLTIU: begin dest = (src1 < branch_offset) ? 32'd1 : 32'd0; dest_valid = 1'b1; end
            
            // ==========================================
            // J-TYPE INSTRUCTIONS
            // ==========================================
            `OP_J: begin 
                dest = branch_offset; 
                branch_taken = 1'b1; 
                dest_valid = 1'b0; 
            end
            `OP_JAL: begin 
                dest = {24'b0, pc} + 32'd1; 
                branch_taken = 1'b1; 
                dest_valid = 1'b1; 
            end
            
            // ==========================================
            // CONDITIONAL BRANCHES
            // ==========================================
            `OP_BEQ: begin 
                dest = {24'b0, pc} + branch_offset; 
                branch_taken = (src1 == src2) ? 1'b1 : 1'b0; 
                dest_valid = 1'b0; 
            end
            `OP_BNE: begin 
                dest = {24'b0, pc} + branch_offset; 
                branch_taken = (src1 != src2) ? 1'b1 : 1'b0; 
                dest_valid = 1'b0; 
            end
            `OP_BLEZ: begin 
                dest = {24'b0, pc} + branch_offset; 
                branch_taken = ($signed(src1) <= $signed(32'd0)) ? 1'b1 : 1'b0; 
                dest_valid = 1'b0; 
            end
            `OP_BGTZ: begin 
                dest = {24'b0, pc} + branch_offset; 
                branch_taken = ($signed(src1) > $signed(32'd0)) ? 1'b1 : 1'b0; 
                dest_valid = 1'b0; 
            end
            `OP_BLTZ_BGEZ: begin 
                dest = {24'b0, pc} + branch_offset; 
                dest_valid = 1'b0;
                
                if (rt == `RT_BLTZ) begin
                    branch_taken = ($signed(src1) < $signed(32'd0)) ? 1'b1 : 1'b0;
                end else if (rt == `RT_BGEZ) begin
                    branch_taken = ($signed(src1) >= $signed(32'd0)) ? 1'b1 : 1'b0;
                end
            end
            
            // ==========================================
            // LAB 9: LOAD/STORE & LUI
            // ==========================================
            `OP_LUI: begin
                dest = {branch_offset[15:0], 16'd0}; // Shift the 16-bit immediate left
                dest_valid = 1'b1;
            end
            
            // Loads: Address Computation (Writes to Register)
            `OP_LB, `OP_LH, `OP_LW, `OP_LBU, `OP_LHU: begin
                dest = src1 + branch_offset; 
                dest_valid = 1'b1;
            end
            
            // Stores: Address Computation (Does NOT write to Register)
            `OP_SB, `OP_SH, `OP_SW: begin
                dest = src1 + branch_offset; 
                dest_valid = 1'b0;
            end

        endcase
    end
endmodule