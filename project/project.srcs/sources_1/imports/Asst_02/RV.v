`timescale 1ns / 1ps
/*
----------------------------------------------------------------------------------
-- Company: NUS	
-- Engineer: (c) Rajesh Panicker  
-- 
-- Create Date: 09/22/2020 06:49:10 PM
-- Module Name: RV
-- Project Name: CG3207 Project
-- Target Devices: Nexys 4 / Basys 3
-- Tool Versions: Vivado 2019.2
-- Description: RISC-V Processor Module
-- 
-- Dependencies: NIL
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments: The interface SHOULD NOT be modified (except making output reg) unless you modify Wrapper.v/vhd too. 
                        The implementation can be modified.
-- 
----------------------------------------------------------------------------------

----------------------------------------------------------------------------------
--	License terms :
--	You are free to use this code as long as you
--		(i) DO NOT post it on any public repository;
--		(ii) use it only for educational purposes;
--		(iii) accept the responsibility to ensure that your implementation does not violate anyone's intellectual property.
--		(iv) accept that the program is provided "as is" without warranty of any kind or assurance regarding its suitability for any particular purpose;
--		(v) send an email to rajesh<dot>panicker<at>ieee.org briefly mentioning its use (except when used for the course CG3207 at the National University of Singapore);
--		(vi) retain this notice in this file as well as any files derived from this.
----------------------------------------------------------------------------------
*/

// Change wire to reg if assigned inside a procedural (always) block. However, where it is easy enough, use assign instead of always.
// A 2-1 multiplexing can be done easily using an assign with a ternary operator
// For multiplexing with number of inputs > 2, a case construct within an always block is a natural fit. DO NOT to use nested ternary assignment operator as it hampers the readability of your code.


module RV #(
    parameter PC_INIT = 32'h00400000
)(
    input CLK,
    input RESET,
    //input Interrupt,      // for optional future use.
    input [31:0] Instr,
    input [31:0] ReadData_in,       // Name mangled to support lb/lbu/lh/lhu
    output MemRead,
    output [3:0] MemWrite_out,		// Column-wise write enable to support sb/sw. Each column is a byte.
    output [31:0] PC,
    output [31:0] ALUResult,
    output [31:0] WriteData_out		// Name mangled to support sb/sw
);
    
    // Please read Lab 4 Enhancement: Implementing additional instructions on how to support lb/lbu/lh/lhu/sb/sh
        
    //RV Signals
    wire [2:0] SizeSel;     //to support lb/lbu/lh/lhu/sb/sh
    wire [31:0] ReadData;
    wire [31:0] WriteData;
    wire MemWrite;

    // The signals that are commented out (except CLK) will need to be uncommented and attached a stage suffix for pipelining,
    //  except if the connection is within the same stage.

    // RegFile signals
    //wire CLK ;
    wire WE ;
    wire [4:0] rs1 ;
    wire [4:0] rs2 ;
    wire [4:0] rd ;
    wire [31:0] WD ;
    wire [31:0] R15 ;
    wire [31:0] RD1 ;
    wire [31:0] RD2 ;
    
    // Extend Module signals
    wire [2:0] ImmSrc ;
    wire [24:0] InstrImm ;
    wire [31:0] ExtImm ;
    
    // Decoder signals
    wire [6:0] Opcode ;
    wire [2:0] Funct3 ;
    wire [6:0] Funct7 ;
    wire [1:0] PCS ;
    wire RegWrite ;
    //wire MemWrite ;
    wire MemtoReg ;
    wire [1:0] ALUSrcA ;
    wire [1:0] ALUSrcB ;
    //wire [2:0] ImmSrc ;
    wire [3:0] ALUControl ;
    wire MCycleStart ;
    wire [1:0] MCycleOp ;
    wire MCycleResultSel ;

    // MCycle signals
    //wire CLK ;
    //wire RESET ;
    //wire MCycleStart ;
    //wire [1:0] MCycleOp ;
    //wire [31:0] RD1 ;     // Operand1
    //wire [31:0] RD2 ;     // Operand2
    wire [31:0] MCycleResult1 ;
    wire [31:0] MCycleResult2 ;
    wire MCycleBusy ;

    // PC_Logic signals
    //wire [1:0] PCS
    //wire [2:0] Funct3;
    //wire [2:0] ALUFlags;
    wire [2:0] PCSrcE;
      
    // ALU signals
    reg [31:0] Src_A ;
    reg [31:0] Src_B ;
    //wire [3:0] ALUControl ;
    //wire [31:0] ALUResult ;
    wire [2:0] ALUFlags ;
    
    // ProgramCounter signals
    //wire CLK ;
    //wire RESET ;
    wire WE_PC ;    
    wire [31:0] PC_IN ;
    wire [31:0] PC ; 
        
    // Other internal signals here
    reg [31:0] PC_Base ;
    wire [31:0] PC_Offset ;
    wire [31:0] Result ;
    wire [31:0] MCycleResult ;
    
    // Fetch Stage signals
    reg [31:0] PCF;
    
    // Decode Stage signals
    reg [31:0] RD1D;
    reg [31:0] RD2D;
    reg [31:0] PCD;
    reg [31:0] ExtImmD;
    reg [4:0] rdD;
    reg [1:0] PCSD;
    reg RegWriteD;
    reg MemtoRegD;
    reg MemWriteD;
    reg [3:0] ALUControlD;
    reg [1:0] ALUSrcAD;
    reg [1:0] ALUSrcBD;
    
    
    // Execute Stage signals
    reg [31:0] RD1E;
    reg [31:0] RD2E;
    reg [31:0] ExtImmE;
    reg [31:0] PCE;
    reg [4:0] rdE;
    wire [31:0] ALUResultE;
    
    wire [31:0] WriteDataE;
    reg RegWriteE;
    reg [1:0] PCSE;
    reg MemtoRegE;
    reg MemWriteE;
    reg [3:0] ALUControlE;
    reg [1:0] ALUSrcAE;
    reg [1:0] ALUSrcBE;
    reg [2:0] Funct3E;
    
    // Memory Stage signals
    reg RegWriteM;
    reg MemtoRegM;
    reg MemWriteM;
    reg [31:0] ALUResultM;
    reg [31:0] WriteDataM;
    reg [4:0] rdM;
    
    // Writeback Stage signals
    reg RegWriteW;
    
    assign ALUResult = ALUResultM;
    
    //Execute Stage Registers
    always @(posedge CLK) begin
        if (RESET) begin
            RD1E <= 32'b0;
            RD2E <= 32'b0;
            ExtImmE <= 32'b0;
            PCE <= 32'b0;
            rdE <= 5'b0;
            RegWriteE <= 1'b0;
            PCSE <= 2'b0;
            MemtoRegE <= 1'b0;
            MemWriteE <= 1'b0;
            ALUControlE <= 4'b0;
            ALUSrcAE <= 2'b0;
            ALUSrcBE <= 2'b0;
            Funct3E <= 3'b0;
         end
         else begin
         RD1E <= RD1D;
         RD2E <= RD2D;
         ExtImmE <= ExtImmD;
         PCE <= PCD;
         rdE <= rdD;
         // ALUResultE output from ALU
         RegWriteE <= RegWriteD;
         PCSE <= PCSD;
         MemtoRegE <= MemtoRegD;
         MemWriteE <= MemWriteD;
         ALUControlE <= ALUControlD;
         ALUSrcAE <= ALUSrcAD;
         ALUSrcBE <= ALUSrcBD;
         Funct3E <= Funct3;
         end
    end
    
    //Memory Stage Registers
    always @(posedge CLK) begin
        if (RESET) begin
            RegWriteM  <= 1'b0;
            MemtoRegM  <= 1'b0;
            MemWriteM  <= 1'b0;
            ALUResultM <= 32'b0;
            WriteDataM <= 32'b0;
            rdM        <= 5'b0;
        end
        else begin
            RegWriteM <= RegWriteE;
            MemtoRegM <= MemtoRegE;
            MemWriteM <= MemWriteE;
            ALUResultM <= ALUResultE;
            WriteDataM <= WriteDataE;
            rdM <= rdE;
        end
    end
    
    
    assign MemRead = MemtoRegM; // This is needed for the proper functionality of some devices such as UART CONSOLE
    assign WE_PC = ~MCycleBusy ;  // Freeze PC while a multi-cycle operation (Multiplication, Division) is on. Will need more control for Pipelining with hazard hardware.

    assign ReadData = ReadData_in;       // Change datapath as appropriate if supporting lb/lbu/lh/lhu
    assign WriteData_out = WriteDataM;    // Change datapath as appropriate if supporting sb/sh
    assign MemWrite_out = {4{MemWriteM}}; // Change datapath as appropriate if supporting sb/sh
    assign SizeSel = 3'b010;             // Change this to be generated by the Decoder (control) as appropriate if 
                                         // supporting lb/sb/lbu/lh/sh/lhu/lw/sw. Hint: funct3
    
    //Splitting full 32 bit instruction into format
    assign Opcode = Instr[6:0];
    assign rd = Instr[11:7];
    assign Funct3 = Instr[14:12];
    assign rs1 = Instr[19:15];
    assign rs2 = Instr[24:20];
    assign Funct7 = Instr[31:25];
    assign InstrImm = Instr[31:7];
    
    //To control Write-Enable with pipelining
    assign WE = RegWriteW & ~MCycleBusy; // Don't write intermediate MCycle results to rd; write only once Busy drops
    
    // Multiplexers for ALU Inputs modified for pipelining
    always @(*) begin
        case (ALUSrcAE)
            2'b00:   Src_A = RD1E;      // RD1
            2'b01:   Src_A = 32'd0;     // 0 (lui)
            2'b11:   Src_A = PCE;       // PC (auipc, jal, jalr)
            default: Src_A = RD1E;      // 2'b10 unused
        endcase
    end

    always @(*) begin
        case (ALUSrcBE)
            2'b00:   Src_B = RD2E;      // RD2
            2'b01:   Src_B = 32'd4;     // 4 (link address for jal, jalr)
            2'b11:   Src_B = ExtImmE;   // ExtImm
            default: Src_B = RD2E;      // 2'b10 unused
        endcase
    end
    
    assign MCycleResult = MCycleResultSel ? MCycleResult2 : MCycleResult1; // Result2 for mulh, mulhu, rem, remu. Result1 for mul, div, divu
    assign Result = MCycleStart ? MCycleResult : (MemtoReg ? ReadData : ALUResult); //Multiplex Result from MCycle, Memory or ALU
    assign WD = Result; //Write to Register File from result
    
    // PC with pipelining * Note that this differs from schematic as schematic did not include support for jalr
    // Next PC uses a single adder: PC_Base + PC_Offset
    // PCSrc: 000: PCF + 4, 101: PCE + ExtImm (branch, jal), 111: RD1 + ExtImm (jalr)
    always @(*) begin
        case (PCSrcE[1:0])
            2'b00:   PC_Base = PCF;     // PC + 4
            2'b01:   PC_Base = PCE;     // branch, jal
            2'b11:   PC_Base = RD1E;    // jalr
            default: PC_Base = PCF;     // 2'b10 unused
        endcase
    end
    assign PC_Offset = PCSrcE[2] ? ExtImmE : 32'd4;
    assign PC_IN = PC_Base + PC_Offset; 

    assign WriteData = RD2;

    // Store data in Execute stage. Replace RD2E with the forwarded rs2 value once forwarding is added.
    assign WriteDataE = RD2E;
	
    // Instantiate RegFile
    RegFile RegFile1( 
                    CLK,
                    WE,
                    rs1,
                    rs2,
                    rd,
                    WD,
                    RD1,
                    RD2     
                );
                
     // Instantiate Extend Module
    Extend Extend1(
                    ImmSrc,
                    InstrImm,
                    ExtImm
                );
                
    // Instantiate Decoder
    Decoder Decoder1(
                    Opcode,
                    Funct3,
                    Funct7,
                    PCS,
                    RegWrite,
                    MemWrite,
                    MemtoReg,
                    ALUSrcA,
                    ALUSrcB,
                    ImmSrc,
                    ALUControl,
                    MCycleStart,
                    MCycleOp,
                    MCycleResultSel
                );
                
    // Instantiate PC_Logic with pipelining logic
	PC_Logic PC_Logic1(
                    PCSE,
                    Funct3E,
                    ALUFlags,
                    PCSrcE
		);
                
    // Instantiate ALU        
    ALU ALU1(
                    Src_A,
                    Src_B,
                    ALUControlE,
                    ALUResultE,
                    ALUFlags
                );                
    
    // Instantiate MCycle
    MCycle #(.width(32)) MCycle1(
                    CLK,
                    RESET,
                    MCycleStart,
                    MCycleOp,
                    RD1,
                    RD2,
                    MCycleResult1,
                    MCycleResult2,
                    MCycleBusy
                );
    
    // Instantiate ProgramCounter    
    ProgramCounter #(.PC_INIT(PC_INIT)) ProgramCounter1(
                    CLK,
                    RESET,
                    WE_PC,    
                    PC_IN,
                    PC  
                );                         
endmodule
