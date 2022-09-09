// SPDX-FileCopyrightText: 
// 2022 Nguyen Dao
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// SPDX-License-Identifier: Apache-2.0


module eFPGA_top (
	// Wishbone Slave ports (WB MI A)
	input wb_clk_i,
	input wbs_stb_i,
	input wbs_cyc_i,
	input wbs_we_i,
	input [31:0] wbs_dat_i,
	input [31:0] wbs_adr_i,
	output [31:0] wbs_dat_o,
	output wbs_ack_o,

	// Logic Analyzer Signals
	output [6:0] la_data_out,

	// IOs
	input  [31-1:0] io_in,
	output [31-1:0] io_out,
	output [31-1:0] io_oeb,

	// Independent clock (on independent integer divider)
	input   user_clock2
);

	localparam include_eFPGA = 1;
	localparam NumberOfRows = 12;
	localparam NumberOfCols = 10;
	localparam FrameBitsPerRow = 32;
	localparam MaxFramesPerCol = 20;
	localparam desync_flag = 20;
	localparam FrameSelectWidth = 5;
	localparam RowSelectWidth = 5;

	// External USER ports 
	//inout [16-1:0] PAD; // these are for Dirk and go to the pad ring
	wire [24-1:0] I_top; 
	wire [24-1:0] T_top;
	wire [24-1:0] O_top;
	wire [48-1:0] A_config_C;
	wire [48-1:0] B_config_C;

	wire CLK; // This clock can go to the CPU (connects to the fabric LUT output flops

	// CPU configuration port
	wire SelfWriteStrobe; // must decode address and write enable
	wire [32-1:0] SelfWriteData; // configuration data write port

	// UART configuration port
	wire Rx;
	wire ComActive;
	wire ReceiveLED;

	// BitBang configuration port
	wire s_clk;
	wire s_data;

	//BlockRAM ports
	wire [192-1:0] RAM2FAB_D;
	wire [192-1:0] FAB2RAM_D;
	wire [96-1:0] FAB2RAM_A;
	wire [48-1:0] FAB2RAM_C;
	wire [48-1:0] Config_accessC;

	// Signal declarations
	wire [(NumberOfRows*FrameBitsPerRow)-1:0] FrameRegister;

	wire [(MaxFramesPerCol*NumberOfCols)-1:0] FrameSelect;

	wire [(FrameBitsPerRow*(NumberOfRows+2))-1:0] FrameData;

	wire [FrameBitsPerRow-1:0] FrameAddressRegister;
	wire LongFrameStrobe;
	wire [31:0] LocalWriteData;
	wire LocalWriteStrobe;
	wire [RowSelectWidth-1:0] RowSelect;

	wire external_clock;
	wire [1:0] clk_sel;

	wire config_strobe;
	wire fabric_strobe;
	wire read_ena;
	reg [31:0] config_data;
	reg [16:0] to_fabric_ios;
	wire [15:0] from_fabric_ios;

	//latch for config_strobe
	reg latch_config_strobe = 0;
	reg config_strobe_reg1 = 0;
	reg config_strobe_reg2 = 0;
	reg config_strobe_reg3 = 0;
	wire latch_config_strobe_inverted1;
	wire latch_config_strobe_inverted2;
	always @ (*) begin
		if(config_strobe_reg2) begin
			latch_config_strobe = 0;
		end else if(latch_config_strobe_inverted2) begin
			latch_config_strobe = 0;
		end else if(wbs_stb_i && wbs_cyc_i && wbs_we_i && !wbs_stb_i && (wbs_adr_i == 32'h30000000)) begin
			latch_config_strobe = 1;
		end
	end
	//assign latch_config_strobe_inverted1 = (!latch_config_strobe);			//This are the two inverters
	sky130_fd_sc_hd__inv latch_config_strobe_inv_0 (.Y(latch_config_strobe_inverted1), .A(latch_config_strobe));
	//assign latch_config_strobe_inverted2 = (!latch_config_strobe_inverted1);
	sky130_fd_sc_hd__inv latch_config_strobe_inv_1 (.Y(latch_config_strobe_inverted2), .A(latch_config_strobe_inverted1));
	always @ (posedge CLK) begin
		config_strobe_reg1 <= latch_config_strobe;
		config_strobe_reg2 <= config_strobe_reg1;
		config_strobe_reg3 <= config_strobe_reg2;
	end
	assign config_strobe = (config_strobe_reg3 && (!config_strobe_reg2)); //posedge pulse for config strobe
	
	
	//latch for fabric_strobe
	reg latch_fabric_strobe = 0;
	reg fabric_strobe_reg1 = 0;
	reg fabric_strobe_reg2 = 0;
	reg fabric_strobe_reg3 = 0;
	wire latch_fabric_strobe_inverted1;
	wire latch_fabric_strobe_inverted2;
	
	always @ (*) begin
		if(fabric_strobe_reg2) begin
			latch_fabric_strobe = 0;
		end else if(latch_fabric_strobe_inverted2) begin
			latch_fabric_strobe = 0;
		end else if(wbs_stb_i && wbs_cyc_i && wbs_we_i && !wbs_stb_i && (wbs_adr_i == 32'h30000004)) begin
			latch_fabric_strobe = 1;
		end
	end
	//assign latch_fabric_strobe_inverted1 = (!latch_fabric_strobe);			//This are the two inverters
	sky130_fd_sc_hd__inv latch_fabric_strobe_inv_0 (.Y(latch_fabric_strobe_inverted1), .A(latch_fabric_strobe));
	//assign latch_fabric_strobe_inverted2 = (!latch_fabric_strobe_inverted1);
	sky130_fd_sc_hd__inv latch_fabric_strobe_inv_1 (.Y(latch_fabric_strobe_inverted2), .A(latch_fabric_strobe_inverted1));
	always @ (posedge CLK) begin
		fabric_strobe_reg1 <= latch_fabric_strobe;
		fabric_strobe_reg2 <= fabric_strobe_reg1;
		fabric_strobe_reg3 <= fabric_strobe_reg2;
	end
	assign fabric_strobe = (fabric_strobe_reg3 && (!fabric_strobe_reg2)); //posedge pulse for config strobe
	
	//config data register
	always @ (posedge wb_clk_i) begin
		if(wbs_stb_i && wbs_cyc_i && wbs_we_i && !wbs_stb_i && (wbs_adr_i == 32'h30000000)) begin
			config_data = wbs_dat_i;
		end
	end
	//to_fabric_ios register
	always @ (posedge wb_clk_i) begin
		if(wbs_stb_i && wbs_cyc_i && wbs_we_i && !wbs_stb_i && (wbs_adr_i == 32'h30000004)) begin
			to_fabric_ios = wbs_dat_i[16:0];
		end
	end
	
	//to_wishbone


	// wb ack generation
	wire cfg_wb_active = (wbs_adr_i[31:24] == 8'h30);
	// fabric map regions selected
	wire fab_wb_active = (wbs_adr_i[31:24] >= 8'h31 && wbs_adr_i[31:24] <= 8'h3F);
	reg cfg_wb_ack;
	always @(posedge wb_clk_i)
		cfg_wb_ack <= cfg_wb_active && wbs_stb_i && wbs_cyc_i;
	wire fab_wb_ack_o = FAB2RAM_D[32];
	wire fab_wb_ack = fab_wb_ack_o && fab_wb_active;

	assign wbs_ack_o = cfg_wb_ack || fab_wb_ack;

	// Receive Wishbone data back from fabric via RAM IO
	assign wbs_dat_o = fab_wb_active ? FAB2RAM_D[31:0] : {16'b0,from_fabric_ios};
	assign read_ena = (wbs_adr_i == 32'h30000004)? (wbs_stb_i & wbs_cyc_i & ~wbs_we_i & ~wbs_stb_i) : 1'b0;
	
	my_mux2 from_fabric_io_0  (.A0(1'b0), .A1(I_top[0]),  .S(read_ena), .X(from_fabric_ios[0]));
	my_mux2 from_fabric_io_1  (.A0(1'b0), .A1(I_top[1]),  .S(read_ena), .X(from_fabric_ios[1]));
	my_mux2 from_fabric_io_2  (.A0(1'b0), .A1(I_top[2]),  .S(read_ena), .X(from_fabric_ios[2]));
	my_mux2 from_fabric_io_3  (.A0(1'b0), .A1(I_top[3]),  .S(read_ena), .X(from_fabric_ios[3]));
	my_mux2 from_fabric_io_4  (.A0(1'b0), .A1(I_top[4]),  .S(read_ena), .X(from_fabric_ios[4]));
	my_mux2 from_fabric_io_5  (.A0(1'b0), .A1(I_top[5]),  .S(read_ena), .X(from_fabric_ios[5]));
	my_mux2 from_fabric_io_6  (.A0(1'b0), .A1(I_top[6]),  .S(read_ena), .X(from_fabric_ios[6]));
	my_mux2 from_fabric_io_7  (.A0(1'b0), .A1(I_top[7]),  .S(read_ena), .X(from_fabric_ios[7]));
	my_mux2 from_fabric_io_8  (.A0(1'b0), .A1(I_top[8]),  .S(read_ena), .X(from_fabric_ios[8]));
	my_mux2 from_fabric_io_9  (.A0(1'b0), .A1(I_top[9]),  .S(read_ena), .X(from_fabric_ios[9]));
	my_mux2 from_fabric_io_10 (.A0(1'b0), .A1(I_top[10]), .S(read_ena), .X(from_fabric_ios[10]));
	my_mux2 from_fabric_io_11 (.A0(1'b0), .A1(I_top[11]), .S(read_ena), .X(from_fabric_ios[11]));
	my_mux2 from_fabric_io_12 (.A0(1'b0), .A1(I_top[12]), .S(read_ena), .X(from_fabric_ios[12]));
	my_mux2 from_fabric_io_13 (.A0(1'b0), .A1(I_top[13]), .S(read_ena), .X(from_fabric_ios[13]));
	my_mux2 from_fabric_io_14 (.A0(1'b0), .A1(I_top[14]), .S(read_ena), .X(from_fabric_ios[14]));
	my_mux2 from_fabric_io_15 (.A0(1'b0), .A1(I_top[15]), .S(read_ena), .X(from_fabric_ios[15]));

	my_mux2 to_fabric_io_0  (.A0(io_in[7]), .A1(to_fabric_ios[0]),  .S(B_config_C[0]),  .X(O_top[0]));
	my_mux2 to_fabric_io_1  (.A0(io_in[8]), .A1(to_fabric_ios[1]),  .S(A_config_C[0]),  .X(O_top[1]));
	my_mux2 to_fabric_io_2  (.A0(io_in[9]), .A1(to_fabric_ios[2]),  .S(B_config_C[4]),  .X(O_top[2]));
	my_mux2 to_fabric_io_3  (.A0(io_in[10]), .A1(to_fabric_ios[3]),  .S(A_config_C[4]),  .X(O_top[3]));
	my_mux2 to_fabric_io_4  (.A0(io_in[11]), .A1(to_fabric_ios[4]),  .S(B_config_C[8]),  .X(O_top[4]));
	my_mux2 to_fabric_io_5  (.A0(io_in[12]), .A1(to_fabric_ios[5]),  .S(A_config_C[8]),  .X(O_top[5]));
	my_mux2 to_fabric_io_6  (.A0(io_in[13]), .A1(to_fabric_ios[6]),  .S(B_config_C[12]), .X(O_top[6]));
	my_mux2 to_fabric_io_7  (.A0(io_in[14]), .A1(to_fabric_ios[7]),  .S(A_config_C[12]), .X(O_top[7]));
	my_mux2 to_fabric_io_8  (.A0(io_in[15]), .A1(to_fabric_ios[8]),  .S(B_config_C[16]), .X(O_top[8]));
	my_mux2 to_fabric_io_9  (.A0(io_in[16]), .A1(to_fabric_ios[9]),  .S(A_config_C[16]), .X(O_top[9]));
	my_mux2 to_fabric_io_10 (.A0(io_in[17]), .A1(to_fabric_ios[10]), .S(B_config_C[20]), .X(O_top[10]));
	my_mux2 to_fabric_io_11 (.A0(io_in[18]), .A1(to_fabric_ios[11]), .S(A_config_C[20]), .X(O_top[11]));
	my_mux2 to_fabric_io_12 (.A0(io_in[19]), .A1(to_fabric_ios[12]), .S(B_config_C[24]), .X(O_top[12]));
	my_mux2 to_fabric_io_13 (.A0(io_in[20]), .A1(to_fabric_ios[13]), .S(A_config_C[24]), .X(O_top[13]));
	my_mux2 to_fabric_io_14 (.A0(io_in[21]), .A1(to_fabric_ios[14]), .S(B_config_C[28]), .X(O_top[14]));
	my_mux2 to_fabric_io_15 (.A0(io_in[22]), .A1(to_fabric_ios[15]), .S(A_config_C[28]), .X(O_top[15]));
	
	my_mux2 to_fabric_addr  (.A0(io_in[23]), .A1(to_fabric_ios[16]), .S(B_config_C[32]), .X(O_top[16]));
	
	my_mux2 to_fabric_strobe(.A0(io_in[24]), .A1(fabric_strobe),     .S(A_config_C[32]), .X(O_top[17]));

	// Pass wishbone signals into fabric via RAM-intended IO
	assign RAM2FAB_D[63:0] = {fab_wb_active, wbs_stb_i, wbs_cyc_i, wbs_we_i, wbs_adr_i[27:0], wbs_dat_i};

	assign external_clock = io_in[0];
	assign clk_sel = {io_in[2],io_in[1]};
	assign s_clk          = io_in[3];
	assign s_data         = io_in[4];
	assign Rx             = io_in[5];
	assign io_out[6]     = ReceiveLED;

	assign io_oeb[6:0] = 7'b1000000;
	
	assign SelfWriteStrobe = config_strobe;
	assign SelfWriteData   = config_data;

	assign CLK = clk_sel[0] ? (clk_sel[1] ? user_clock2 : wb_clk_i) : external_clock;

	assign la_data_out[6:0] = {A_config_C[39], A_config_C[31], A_config_C[16], FAB2RAM_C[45], ReceiveLED, Rx, ComActive};

	assign O_top[23:18] = io_in[30:25];
	assign io_out[30:7] = I_top;
	assign io_oeb[30:7] = T_top;

Config Config_inst (
	.CLK(CLK),
	.Rx(Rx),
	.ComActive(ComActive),
	.ReceiveLED(ReceiveLED),
	.s_clk(s_clk),
	.s_data(s_data),
	.SelfWriteData(SelfWriteData),
	.SelfWriteStrobe(SelfWriteStrobe),
	
	.ConfigWriteData(LocalWriteData),
	.ConfigWriteStrobe(LocalWriteStrobe),
	
	.FrameAddressRegister(FrameAddressRegister),
	.LongFrameStrobe(LongFrameStrobe),
	.RowSelect(RowSelect)
);


	// L: if include_eFPGA = 1 generate

	Frame_Data_Reg_0 Inst_Frame_Data_Reg_0 (
	.FrameData_I(LocalWriteData),
	.FrameData_O(FrameRegister[0*FrameBitsPerRow+:FrameBitsPerRow]),
	.RowSelect(RowSelect),
	.CLK(CLK)
	);

	Frame_Data_Reg_1 Inst_Frame_Data_Reg_1 (
	.FrameData_I(LocalWriteData),
	.FrameData_O(FrameRegister[1*FrameBitsPerRow+:FrameBitsPerRow]),
	.RowSelect(RowSelect),
	.CLK(CLK)
	);

	Frame_Data_Reg_2 Inst_Frame_Data_Reg_2 (
	.FrameData_I(LocalWriteData),
	.FrameData_O(FrameRegister[2*FrameBitsPerRow+:FrameBitsPerRow]),
	.RowSelect(RowSelect),
	.CLK(CLK)
	);

	Frame_Data_Reg_3 Inst_Frame_Data_Reg_3 (
	.FrameData_I(LocalWriteData),
	.FrameData_O(FrameRegister[3*FrameBitsPerRow+:FrameBitsPerRow]),
	.RowSelect(RowSelect),
	.CLK(CLK)
	);

	Frame_Data_Reg_4 Inst_Frame_Data_Reg_4 (
	.FrameData_I(LocalWriteData),
	.FrameData_O(FrameRegister[4*FrameBitsPerRow+:FrameBitsPerRow]),
	.RowSelect(RowSelect),
	.CLK(CLK)
	);

	Frame_Data_Reg_5 Inst_Frame_Data_Reg_5 (
	.FrameData_I(LocalWriteData),
	.FrameData_O(FrameRegister[5*FrameBitsPerRow+:FrameBitsPerRow]),
	.RowSelect(RowSelect),
	.CLK(CLK)
	);

	Frame_Data_Reg_6 Inst_Frame_Data_Reg_6 (
	.FrameData_I(LocalWriteData),
	.FrameData_O(FrameRegister[6*FrameBitsPerRow+:FrameBitsPerRow]),
	.RowSelect(RowSelect),
	.CLK(CLK)
	);

	Frame_Data_Reg_7 Inst_Frame_Data_Reg_7 (
	.FrameData_I(LocalWriteData),
	.FrameData_O(FrameRegister[7*FrameBitsPerRow+:FrameBitsPerRow]),
	.RowSelect(RowSelect),
	.CLK(CLK)
	);

	Frame_Data_Reg_8 Inst_Frame_Data_Reg_8 (
	.FrameData_I(LocalWriteData),
	.FrameData_O(FrameRegister[8*FrameBitsPerRow+:FrameBitsPerRow]),
	.RowSelect(RowSelect),
	.CLK(CLK)
	);

	Frame_Data_Reg_9 Inst_Frame_Data_Reg_9 (
	.FrameData_I(LocalWriteData),
	.FrameData_O(FrameRegister[9*FrameBitsPerRow+:FrameBitsPerRow]),
	.RowSelect(RowSelect),
	.CLK(CLK)
	);

	Frame_Data_Reg_10 Inst_Frame_Data_Reg_10 (
	.FrameData_I(LocalWriteData),
	.FrameData_O(FrameRegister[10*FrameBitsPerRow+:FrameBitsPerRow]),
	.RowSelect(RowSelect),
	.CLK(CLK)
	);

	Frame_Data_Reg_11 Inst_Frame_Data_Reg_11 (
	.FrameData_I(LocalWriteData),
	.FrameData_O(FrameRegister[11*FrameBitsPerRow+:FrameBitsPerRow]),
	.RowSelect(RowSelect),
	.CLK(CLK)
	);

	Frame_Select_0 Inst_Frame_Select_0 (
	.FrameStrobe_I(FrameAddressRegister[MaxFramesPerCol-1:0]),
	.FrameStrobe_O(FrameSelect[0*MaxFramesPerCol +: MaxFramesPerCol]),
	.FrameSelect(FrameAddressRegister[FrameBitsPerRow-1:FrameBitsPerRow-(FrameSelectWidth)]),
	.FrameStrobe(LongFrameStrobe)
	);

	Frame_Select_1 Inst_Frame_Select_1 (
	.FrameStrobe_I(FrameAddressRegister[MaxFramesPerCol-1:0]),
	.FrameStrobe_O(FrameSelect[1*MaxFramesPerCol +: MaxFramesPerCol]),
	.FrameSelect(FrameAddressRegister[FrameBitsPerRow-1:FrameBitsPerRow-(FrameSelectWidth)]),
	.FrameStrobe(LongFrameStrobe)
	);

	Frame_Select_2 Inst_Frame_Select_2 (
	.FrameStrobe_I(FrameAddressRegister[MaxFramesPerCol-1:0]),
	.FrameStrobe_O(FrameSelect[2*MaxFramesPerCol +: MaxFramesPerCol]),
	.FrameSelect(FrameAddressRegister[FrameBitsPerRow-1:FrameBitsPerRow-(FrameSelectWidth)]),
	.FrameStrobe(LongFrameStrobe)
	);

	Frame_Select_3 Inst_Frame_Select_3 (
	.FrameStrobe_I(FrameAddressRegister[MaxFramesPerCol-1:0]),
	.FrameStrobe_O(FrameSelect[3*MaxFramesPerCol +: MaxFramesPerCol]),
	.FrameSelect(FrameAddressRegister[FrameBitsPerRow-1:FrameBitsPerRow-(FrameSelectWidth)]),
	.FrameStrobe(LongFrameStrobe)
	);

	Frame_Select_4 Inst_Frame_Select_4 (
	.FrameStrobe_I(FrameAddressRegister[MaxFramesPerCol-1:0]),
	.FrameStrobe_O(FrameSelect[4*MaxFramesPerCol +: MaxFramesPerCol]),
	.FrameSelect(FrameAddressRegister[FrameBitsPerRow-1:FrameBitsPerRow-(FrameSelectWidth)]),
	.FrameStrobe(LongFrameStrobe)
	);

	Frame_Select_5 Inst_Frame_Select_5 (
	.FrameStrobe_I(FrameAddressRegister[MaxFramesPerCol-1:0]),
	.FrameStrobe_O(FrameSelect[5*MaxFramesPerCol +: MaxFramesPerCol]),
	.FrameSelect(FrameAddressRegister[FrameBitsPerRow-1:FrameBitsPerRow-(FrameSelectWidth)]),
	.FrameStrobe(LongFrameStrobe)
	);

	Frame_Select_6 Inst_Frame_Select_6 (
	.FrameStrobe_I(FrameAddressRegister[MaxFramesPerCol-1:0]),
	.FrameStrobe_O(FrameSelect[6*MaxFramesPerCol +: MaxFramesPerCol]),
	.FrameSelect(FrameAddressRegister[FrameBitsPerRow-1:FrameBitsPerRow-(FrameSelectWidth)]),
	.FrameStrobe(LongFrameStrobe)
	);

	Frame_Select_7 Inst_Frame_Select_7 (
	.FrameStrobe_I(FrameAddressRegister[MaxFramesPerCol-1:0]),
	.FrameStrobe_O(FrameSelect[7*MaxFramesPerCol +: MaxFramesPerCol]),
	.FrameSelect(FrameAddressRegister[FrameBitsPerRow-1:FrameBitsPerRow-(FrameSelectWidth)]),
	.FrameStrobe(LongFrameStrobe)
	);

	Frame_Select_8 Inst_Frame_Select_8 (
	.FrameStrobe_I(FrameAddressRegister[MaxFramesPerCol-1:0]),
	.FrameStrobe_O(FrameSelect[8*MaxFramesPerCol +: MaxFramesPerCol]),
	.FrameSelect(FrameAddressRegister[FrameBitsPerRow-1:FrameBitsPerRow-(FrameSelectWidth)]),
	.FrameStrobe(LongFrameStrobe)
	);

	Frame_Select_9 Inst_Frame_Select_9 (
	.FrameStrobe_I(FrameAddressRegister[MaxFramesPerCol-1:0]),
	.FrameStrobe_O(FrameSelect[9*MaxFramesPerCol +: MaxFramesPerCol]),
	.FrameSelect(FrameAddressRegister[FrameBitsPerRow-1:FrameBitsPerRow-(FrameSelectWidth)]),
	.FrameStrobe(LongFrameStrobe)
	);

	eFPGA Inst_eFPGA(
	.Tile_X0Y1_A_I_top(I_top[23]),
	.Tile_X0Y1_B_I_top(I_top[22]),
	.Tile_X0Y2_A_I_top(I_top[21]),
	.Tile_X0Y2_B_I_top(I_top[20]),
	.Tile_X0Y3_A_I_top(I_top[19]),
	.Tile_X0Y3_B_I_top(I_top[18]),
	.Tile_X0Y4_A_I_top(I_top[17]),
	.Tile_X0Y4_B_I_top(I_top[16]),
	.Tile_X0Y5_A_I_top(I_top[15]),
	.Tile_X0Y5_B_I_top(I_top[14]),
	.Tile_X0Y6_A_I_top(I_top[13]),
	.Tile_X0Y6_B_I_top(I_top[12]),
	.Tile_X0Y7_A_I_top(I_top[11]),
	.Tile_X0Y7_B_I_top(I_top[10]),
	.Tile_X0Y8_A_I_top(I_top[9]),
	.Tile_X0Y8_B_I_top(I_top[8]),
	.Tile_X0Y9_A_I_top(I_top[7]),
	.Tile_X0Y9_B_I_top(I_top[6]),
	.Tile_X0Y10_A_I_top(I_top[5]),
	.Tile_X0Y10_B_I_top(I_top[4]),
	.Tile_X0Y11_A_I_top(I_top[3]),
	.Tile_X0Y11_B_I_top(I_top[2]),
	.Tile_X0Y12_A_I_top(I_top[1]),
	.Tile_X0Y12_B_I_top(I_top[0]),

	.Tile_X0Y1_A_T_top(T_top[23]),
	.Tile_X0Y1_B_T_top(T_top[22]),
	.Tile_X0Y2_A_T_top(T_top[21]),
	.Tile_X0Y2_B_T_top(T_top[20]),
	.Tile_X0Y3_A_T_top(T_top[19]),
	.Tile_X0Y3_B_T_top(T_top[18]),
	.Tile_X0Y4_A_T_top(T_top[17]),
	.Tile_X0Y4_B_T_top(T_top[16]),
	.Tile_X0Y5_A_T_top(T_top[15]),
	.Tile_X0Y5_B_T_top(T_top[14]),
	.Tile_X0Y6_A_T_top(T_top[13]),
	.Tile_X0Y6_B_T_top(T_top[12]),
	.Tile_X0Y7_A_T_top(T_top[11]),
	.Tile_X0Y7_B_T_top(T_top[10]),
	.Tile_X0Y8_A_T_top(T_top[9]),
	.Tile_X0Y8_B_T_top(T_top[8]),
	.Tile_X0Y9_A_T_top(T_top[7]),
	.Tile_X0Y9_B_T_top(T_top[6]),
	.Tile_X0Y10_A_T_top(T_top[5]),
	.Tile_X0Y10_B_T_top(T_top[4]),
	.Tile_X0Y11_A_T_top(T_top[3]),
	.Tile_X0Y11_B_T_top(T_top[2]),
	.Tile_X0Y12_A_T_top(T_top[1]),
	.Tile_X0Y12_B_T_top(T_top[0]),

	.Tile_X0Y1_A_O_top(O_top[23]),
	.Tile_X0Y1_B_O_top(O_top[22]),
	.Tile_X0Y2_A_O_top(O_top[21]),
	.Tile_X0Y2_B_O_top(O_top[20]),
	.Tile_X0Y3_A_O_top(O_top[19]),
	.Tile_X0Y3_B_O_top(O_top[18]),
	.Tile_X0Y4_A_O_top(O_top[17]),
	.Tile_X0Y4_B_O_top(O_top[16]),
	.Tile_X0Y5_A_O_top(O_top[15]),
	.Tile_X0Y5_B_O_top(O_top[14]),
	.Tile_X0Y6_A_O_top(O_top[13]),
	.Tile_X0Y6_B_O_top(O_top[12]),
	.Tile_X0Y7_A_O_top(O_top[11]),
	.Tile_X0Y7_B_O_top(O_top[10]),
	.Tile_X0Y8_A_O_top(O_top[9]),
	.Tile_X0Y8_B_O_top(O_top[8]),
	.Tile_X0Y9_A_O_top(O_top[7]),
	.Tile_X0Y9_B_O_top(O_top[6]),
	.Tile_X0Y10_A_O_top(O_top[5]),
	.Tile_X0Y10_B_O_top(O_top[4]),
	.Tile_X0Y11_A_O_top(O_top[3]),
	.Tile_X0Y11_B_O_top(O_top[2]),
	.Tile_X0Y12_A_O_top(O_top[1]),
	.Tile_X0Y12_B_O_top(O_top[0]),

	.Tile_X0Y1_A_config_C_bit0(A_config_C[47]),
	.Tile_X0Y1_A_config_C_bit1(A_config_C[46]),
	.Tile_X0Y1_A_config_C_bit2(A_config_C[45]),
	.Tile_X0Y1_A_config_C_bit3(A_config_C[44]),
	.Tile_X0Y2_A_config_C_bit0(A_config_C[43]),
	.Tile_X0Y2_A_config_C_bit1(A_config_C[42]),
	.Tile_X0Y2_A_config_C_bit2(A_config_C[41]),
	.Tile_X0Y2_A_config_C_bit3(A_config_C[40]),
	.Tile_X0Y3_A_config_C_bit0(A_config_C[39]),
	.Tile_X0Y3_A_config_C_bit1(A_config_C[38]),
	.Tile_X0Y3_A_config_C_bit2(A_config_C[37]),
	.Tile_X0Y3_A_config_C_bit3(A_config_C[36]),
	.Tile_X0Y4_A_config_C_bit0(A_config_C[35]),
	.Tile_X0Y4_A_config_C_bit1(A_config_C[34]),
	.Tile_X0Y4_A_config_C_bit2(A_config_C[33]),
	.Tile_X0Y4_A_config_C_bit3(A_config_C[32]),
	.Tile_X0Y5_A_config_C_bit0(A_config_C[31]),
	.Tile_X0Y5_A_config_C_bit1(A_config_C[30]),
	.Tile_X0Y5_A_config_C_bit2(A_config_C[29]),
	.Tile_X0Y5_A_config_C_bit3(A_config_C[28]),
	.Tile_X0Y6_A_config_C_bit0(A_config_C[27]),
	.Tile_X0Y6_A_config_C_bit1(A_config_C[26]),
	.Tile_X0Y6_A_config_C_bit2(A_config_C[25]),
	.Tile_X0Y6_A_config_C_bit3(A_config_C[24]),
	.Tile_X0Y7_A_config_C_bit0(A_config_C[23]),
	.Tile_X0Y7_A_config_C_bit1(A_config_C[22]),
	.Tile_X0Y7_A_config_C_bit2(A_config_C[21]),
	.Tile_X0Y7_A_config_C_bit3(A_config_C[20]),
	.Tile_X0Y8_A_config_C_bit0(A_config_C[19]),
	.Tile_X0Y8_A_config_C_bit1(A_config_C[18]),
	.Tile_X0Y8_A_config_C_bit2(A_config_C[17]),
	.Tile_X0Y8_A_config_C_bit3(A_config_C[16]),
	.Tile_X0Y9_A_config_C_bit0(A_config_C[15]),
	.Tile_X0Y9_A_config_C_bit1(A_config_C[14]),
	.Tile_X0Y9_A_config_C_bit2(A_config_C[13]),
	.Tile_X0Y9_A_config_C_bit3(A_config_C[12]),
	.Tile_X0Y10_A_config_C_bit0(A_config_C[11]),
	.Tile_X0Y10_A_config_C_bit1(A_config_C[10]),
	.Tile_X0Y10_A_config_C_bit2(A_config_C[9]),
	.Tile_X0Y10_A_config_C_bit3(A_config_C[8]),
	.Tile_X0Y11_A_config_C_bit0(A_config_C[7]),
	.Tile_X0Y11_A_config_C_bit1(A_config_C[6]),
	.Tile_X0Y11_A_config_C_bit2(A_config_C[5]),
	.Tile_X0Y11_A_config_C_bit3(A_config_C[4]),
	.Tile_X0Y12_A_config_C_bit0(A_config_C[3]),
	.Tile_X0Y12_A_config_C_bit1(A_config_C[2]),
	.Tile_X0Y12_A_config_C_bit2(A_config_C[1]),
	.Tile_X0Y12_A_config_C_bit3(A_config_C[0]),

	.Tile_X0Y1_B_config_C_bit0(B_config_C[47]),
	.Tile_X0Y1_B_config_C_bit1(B_config_C[46]),
	.Tile_X0Y1_B_config_C_bit2(B_config_C[45]),
	.Tile_X0Y1_B_config_C_bit3(B_config_C[44]),
	.Tile_X0Y2_B_config_C_bit0(B_config_C[43]),
	.Tile_X0Y2_B_config_C_bit1(B_config_C[42]),
	.Tile_X0Y2_B_config_C_bit2(B_config_C[41]),
	.Tile_X0Y2_B_config_C_bit3(B_config_C[40]),
	.Tile_X0Y3_B_config_C_bit0(B_config_C[39]),
	.Tile_X0Y3_B_config_C_bit1(B_config_C[38]),
	.Tile_X0Y3_B_config_C_bit2(B_config_C[37]),
	.Tile_X0Y3_B_config_C_bit3(B_config_C[36]),
	.Tile_X0Y4_B_config_C_bit0(B_config_C[35]),
	.Tile_X0Y4_B_config_C_bit1(B_config_C[34]),
	.Tile_X0Y4_B_config_C_bit2(B_config_C[33]),
	.Tile_X0Y4_B_config_C_bit3(B_config_C[32]),
	.Tile_X0Y5_B_config_C_bit0(B_config_C[31]),
	.Tile_X0Y5_B_config_C_bit1(B_config_C[30]),
	.Tile_X0Y5_B_config_C_bit2(B_config_C[29]),
	.Tile_X0Y5_B_config_C_bit3(B_config_C[28]),
	.Tile_X0Y6_B_config_C_bit0(B_config_C[27]),
	.Tile_X0Y6_B_config_C_bit1(B_config_C[26]),
	.Tile_X0Y6_B_config_C_bit2(B_config_C[25]),
	.Tile_X0Y6_B_config_C_bit3(B_config_C[24]),
	.Tile_X0Y7_B_config_C_bit0(B_config_C[23]),
	.Tile_X0Y7_B_config_C_bit1(B_config_C[22]),
	.Tile_X0Y7_B_config_C_bit2(B_config_C[21]),
	.Tile_X0Y7_B_config_C_bit3(B_config_C[20]),
	.Tile_X0Y8_B_config_C_bit0(B_config_C[19]),
	.Tile_X0Y8_B_config_C_bit1(B_config_C[18]),
	.Tile_X0Y8_B_config_C_bit2(B_config_C[17]),
	.Tile_X0Y8_B_config_C_bit3(B_config_C[16]),
	.Tile_X0Y9_B_config_C_bit0(B_config_C[15]),
	.Tile_X0Y9_B_config_C_bit1(B_config_C[14]),
	.Tile_X0Y9_B_config_C_bit2(B_config_C[13]),
	.Tile_X0Y9_B_config_C_bit3(B_config_C[12]),
	.Tile_X0Y10_B_config_C_bit0(B_config_C[11]),
	.Tile_X0Y10_B_config_C_bit1(B_config_C[10]),
	.Tile_X0Y10_B_config_C_bit2(B_config_C[9]),
	.Tile_X0Y10_B_config_C_bit3(B_config_C[8]),
	.Tile_X0Y11_B_config_C_bit0(B_config_C[7]),
	.Tile_X0Y11_B_config_C_bit1(B_config_C[6]),
	.Tile_X0Y11_B_config_C_bit2(B_config_C[5]),
	.Tile_X0Y11_B_config_C_bit3(B_config_C[4]),
	.Tile_X0Y12_B_config_C_bit0(B_config_C[3]),
	.Tile_X0Y12_B_config_C_bit1(B_config_C[2]),
	.Tile_X0Y12_B_config_C_bit2(B_config_C[1]),
	.Tile_X0Y12_B_config_C_bit3(B_config_C[0]),

	.Tile_X9Y1_RAM2FAB_D0_I0(RAM2FAB_D[191]),
	.Tile_X9Y1_RAM2FAB_D0_I1(RAM2FAB_D[190]),
	.Tile_X9Y1_RAM2FAB_D0_I2(RAM2FAB_D[189]),
	.Tile_X9Y1_RAM2FAB_D0_I3(RAM2FAB_D[188]),
	.Tile_X9Y1_RAM2FAB_D1_I0(RAM2FAB_D[187]),
	.Tile_X9Y1_RAM2FAB_D1_I1(RAM2FAB_D[186]),
	.Tile_X9Y1_RAM2FAB_D1_I2(RAM2FAB_D[185]),
	.Tile_X9Y1_RAM2FAB_D1_I3(RAM2FAB_D[184]),
	.Tile_X9Y1_RAM2FAB_D2_I0(RAM2FAB_D[183]),
	.Tile_X9Y1_RAM2FAB_D2_I1(RAM2FAB_D[182]),
	.Tile_X9Y1_RAM2FAB_D2_I2(RAM2FAB_D[181]),
	.Tile_X9Y1_RAM2FAB_D2_I3(RAM2FAB_D[180]),
	.Tile_X9Y1_RAM2FAB_D3_I0(RAM2FAB_D[179]),
	.Tile_X9Y1_RAM2FAB_D3_I1(RAM2FAB_D[178]),
	.Tile_X9Y1_RAM2FAB_D3_I2(RAM2FAB_D[177]),
	.Tile_X9Y1_RAM2FAB_D3_I3(RAM2FAB_D[176]),
	.Tile_X9Y2_RAM2FAB_D0_I0(RAM2FAB_D[175]),
	.Tile_X9Y2_RAM2FAB_D0_I1(RAM2FAB_D[174]),
	.Tile_X9Y2_RAM2FAB_D0_I2(RAM2FAB_D[173]),
	.Tile_X9Y2_RAM2FAB_D0_I3(RAM2FAB_D[172]),
	.Tile_X9Y2_RAM2FAB_D1_I0(RAM2FAB_D[171]),
	.Tile_X9Y2_RAM2FAB_D1_I1(RAM2FAB_D[170]),
	.Tile_X9Y2_RAM2FAB_D1_I2(RAM2FAB_D[169]),
	.Tile_X9Y2_RAM2FAB_D1_I3(RAM2FAB_D[168]),
	.Tile_X9Y2_RAM2FAB_D2_I0(RAM2FAB_D[167]),
	.Tile_X9Y2_RAM2FAB_D2_I1(RAM2FAB_D[166]),
	.Tile_X9Y2_RAM2FAB_D2_I2(RAM2FAB_D[165]),
	.Tile_X9Y2_RAM2FAB_D2_I3(RAM2FAB_D[164]),
	.Tile_X9Y2_RAM2FAB_D3_I0(RAM2FAB_D[163]),
	.Tile_X9Y2_RAM2FAB_D3_I1(RAM2FAB_D[162]),
	.Tile_X9Y2_RAM2FAB_D3_I2(RAM2FAB_D[161]),
	.Tile_X9Y2_RAM2FAB_D3_I3(RAM2FAB_D[160]),
	.Tile_X9Y3_RAM2FAB_D0_I0(RAM2FAB_D[159]),
	.Tile_X9Y3_RAM2FAB_D0_I1(RAM2FAB_D[158]),
	.Tile_X9Y3_RAM2FAB_D0_I2(RAM2FAB_D[157]),
	.Tile_X9Y3_RAM2FAB_D0_I3(RAM2FAB_D[156]),
	.Tile_X9Y3_RAM2FAB_D1_I0(RAM2FAB_D[155]),
	.Tile_X9Y3_RAM2FAB_D1_I1(RAM2FAB_D[154]),
	.Tile_X9Y3_RAM2FAB_D1_I2(RAM2FAB_D[153]),
	.Tile_X9Y3_RAM2FAB_D1_I3(RAM2FAB_D[152]),
	.Tile_X9Y3_RAM2FAB_D2_I0(RAM2FAB_D[151]),
	.Tile_X9Y3_RAM2FAB_D2_I1(RAM2FAB_D[150]),
	.Tile_X9Y3_RAM2FAB_D2_I2(RAM2FAB_D[149]),
	.Tile_X9Y3_RAM2FAB_D2_I3(RAM2FAB_D[148]),
	.Tile_X9Y3_RAM2FAB_D3_I0(RAM2FAB_D[147]),
	.Tile_X9Y3_RAM2FAB_D3_I1(RAM2FAB_D[146]),
	.Tile_X9Y3_RAM2FAB_D3_I2(RAM2FAB_D[145]),
	.Tile_X9Y3_RAM2FAB_D3_I3(RAM2FAB_D[144]),
	.Tile_X9Y4_RAM2FAB_D0_I0(RAM2FAB_D[143]),
	.Tile_X9Y4_RAM2FAB_D0_I1(RAM2FAB_D[142]),
	.Tile_X9Y4_RAM2FAB_D0_I2(RAM2FAB_D[141]),
	.Tile_X9Y4_RAM2FAB_D0_I3(RAM2FAB_D[140]),
	.Tile_X9Y4_RAM2FAB_D1_I0(RAM2FAB_D[139]),
	.Tile_X9Y4_RAM2FAB_D1_I1(RAM2FAB_D[138]),
	.Tile_X9Y4_RAM2FAB_D1_I2(RAM2FAB_D[137]),
	.Tile_X9Y4_RAM2FAB_D1_I3(RAM2FAB_D[136]),
	.Tile_X9Y4_RAM2FAB_D2_I0(RAM2FAB_D[135]),
	.Tile_X9Y4_RAM2FAB_D2_I1(RAM2FAB_D[134]),
	.Tile_X9Y4_RAM2FAB_D2_I2(RAM2FAB_D[133]),
	.Tile_X9Y4_RAM2FAB_D2_I3(RAM2FAB_D[132]),
	.Tile_X9Y4_RAM2FAB_D3_I0(RAM2FAB_D[131]),
	.Tile_X9Y4_RAM2FAB_D3_I1(RAM2FAB_D[130]),
	.Tile_X9Y4_RAM2FAB_D3_I2(RAM2FAB_D[129]),
	.Tile_X9Y4_RAM2FAB_D3_I3(RAM2FAB_D[128]),
	.Tile_X9Y5_RAM2FAB_D0_I0(RAM2FAB_D[127]),
	.Tile_X9Y5_RAM2FAB_D0_I1(RAM2FAB_D[126]),
	.Tile_X9Y5_RAM2FAB_D0_I2(RAM2FAB_D[125]),
	.Tile_X9Y5_RAM2FAB_D0_I3(RAM2FAB_D[124]),
	.Tile_X9Y5_RAM2FAB_D1_I0(RAM2FAB_D[123]),
	.Tile_X9Y5_RAM2FAB_D1_I1(RAM2FAB_D[122]),
	.Tile_X9Y5_RAM2FAB_D1_I2(RAM2FAB_D[121]),
	.Tile_X9Y5_RAM2FAB_D1_I3(RAM2FAB_D[120]),
	.Tile_X9Y5_RAM2FAB_D2_I0(RAM2FAB_D[119]),
	.Tile_X9Y5_RAM2FAB_D2_I1(RAM2FAB_D[118]),
	.Tile_X9Y5_RAM2FAB_D2_I2(RAM2FAB_D[117]),
	.Tile_X9Y5_RAM2FAB_D2_I3(RAM2FAB_D[116]),
	.Tile_X9Y5_RAM2FAB_D3_I0(RAM2FAB_D[115]),
	.Tile_X9Y5_RAM2FAB_D3_I1(RAM2FAB_D[114]),
	.Tile_X9Y5_RAM2FAB_D3_I2(RAM2FAB_D[113]),
	.Tile_X9Y5_RAM2FAB_D3_I3(RAM2FAB_D[112]),
	.Tile_X9Y6_RAM2FAB_D0_I0(RAM2FAB_D[111]),
	.Tile_X9Y6_RAM2FAB_D0_I1(RAM2FAB_D[110]),
	.Tile_X9Y6_RAM2FAB_D0_I2(RAM2FAB_D[109]),
	.Tile_X9Y6_RAM2FAB_D0_I3(RAM2FAB_D[108]),
	.Tile_X9Y6_RAM2FAB_D1_I0(RAM2FAB_D[107]),
	.Tile_X9Y6_RAM2FAB_D1_I1(RAM2FAB_D[106]),
	.Tile_X9Y6_RAM2FAB_D1_I2(RAM2FAB_D[105]),
	.Tile_X9Y6_RAM2FAB_D1_I3(RAM2FAB_D[104]),
	.Tile_X9Y6_RAM2FAB_D2_I0(RAM2FAB_D[103]),
	.Tile_X9Y6_RAM2FAB_D2_I1(RAM2FAB_D[102]),
	.Tile_X9Y6_RAM2FAB_D2_I2(RAM2FAB_D[101]),
	.Tile_X9Y6_RAM2FAB_D2_I3(RAM2FAB_D[100]),
	.Tile_X9Y6_RAM2FAB_D3_I0(RAM2FAB_D[99]),
	.Tile_X9Y6_RAM2FAB_D3_I1(RAM2FAB_D[98]),
	.Tile_X9Y6_RAM2FAB_D3_I2(RAM2FAB_D[97]),
	.Tile_X9Y6_RAM2FAB_D3_I3(RAM2FAB_D[96]),
	.Tile_X9Y7_RAM2FAB_D0_I0(RAM2FAB_D[95]),
	.Tile_X9Y7_RAM2FAB_D0_I1(RAM2FAB_D[94]),
	.Tile_X9Y7_RAM2FAB_D0_I2(RAM2FAB_D[93]),
	.Tile_X9Y7_RAM2FAB_D0_I3(RAM2FAB_D[92]),
	.Tile_X9Y7_RAM2FAB_D1_I0(RAM2FAB_D[91]),
	.Tile_X9Y7_RAM2FAB_D1_I1(RAM2FAB_D[90]),
	.Tile_X9Y7_RAM2FAB_D1_I2(RAM2FAB_D[89]),
	.Tile_X9Y7_RAM2FAB_D1_I3(RAM2FAB_D[88]),
	.Tile_X9Y7_RAM2FAB_D2_I0(RAM2FAB_D[87]),
	.Tile_X9Y7_RAM2FAB_D2_I1(RAM2FAB_D[86]),
	.Tile_X9Y7_RAM2FAB_D2_I2(RAM2FAB_D[85]),
	.Tile_X9Y7_RAM2FAB_D2_I3(RAM2FAB_D[84]),
	.Tile_X9Y7_RAM2FAB_D3_I0(RAM2FAB_D[83]),
	.Tile_X9Y7_RAM2FAB_D3_I1(RAM2FAB_D[82]),
	.Tile_X9Y7_RAM2FAB_D3_I2(RAM2FAB_D[81]),
	.Tile_X9Y7_RAM2FAB_D3_I3(RAM2FAB_D[80]),
	.Tile_X9Y8_RAM2FAB_D0_I0(RAM2FAB_D[79]),
	.Tile_X9Y8_RAM2FAB_D0_I1(RAM2FAB_D[78]),
	.Tile_X9Y8_RAM2FAB_D0_I2(RAM2FAB_D[77]),
	.Tile_X9Y8_RAM2FAB_D0_I3(RAM2FAB_D[76]),
	.Tile_X9Y8_RAM2FAB_D1_I0(RAM2FAB_D[75]),
	.Tile_X9Y8_RAM2FAB_D1_I1(RAM2FAB_D[74]),
	.Tile_X9Y8_RAM2FAB_D1_I2(RAM2FAB_D[73]),
	.Tile_X9Y8_RAM2FAB_D1_I3(RAM2FAB_D[72]),
	.Tile_X9Y8_RAM2FAB_D2_I0(RAM2FAB_D[71]),
	.Tile_X9Y8_RAM2FAB_D2_I1(RAM2FAB_D[70]),
	.Tile_X9Y8_RAM2FAB_D2_I2(RAM2FAB_D[69]),
	.Tile_X9Y8_RAM2FAB_D2_I3(RAM2FAB_D[68]),
	.Tile_X9Y8_RAM2FAB_D3_I0(RAM2FAB_D[67]),
	.Tile_X9Y8_RAM2FAB_D3_I1(RAM2FAB_D[66]),
	.Tile_X9Y8_RAM2FAB_D3_I2(RAM2FAB_D[65]),
	.Tile_X9Y8_RAM2FAB_D3_I3(RAM2FAB_D[64]),
	.Tile_X9Y9_RAM2FAB_D0_I0(RAM2FAB_D[63]),
	.Tile_X9Y9_RAM2FAB_D0_I1(RAM2FAB_D[62]),
	.Tile_X9Y9_RAM2FAB_D0_I2(RAM2FAB_D[61]),
	.Tile_X9Y9_RAM2FAB_D0_I3(RAM2FAB_D[60]),
	.Tile_X9Y9_RAM2FAB_D1_I0(RAM2FAB_D[59]),
	.Tile_X9Y9_RAM2FAB_D1_I1(RAM2FAB_D[58]),
	.Tile_X9Y9_RAM2FAB_D1_I2(RAM2FAB_D[57]),
	.Tile_X9Y9_RAM2FAB_D1_I3(RAM2FAB_D[56]),
	.Tile_X9Y9_RAM2FAB_D2_I0(RAM2FAB_D[55]),
	.Tile_X9Y9_RAM2FAB_D2_I1(RAM2FAB_D[54]),
	.Tile_X9Y9_RAM2FAB_D2_I2(RAM2FAB_D[53]),
	.Tile_X9Y9_RAM2FAB_D2_I3(RAM2FAB_D[52]),
	.Tile_X9Y9_RAM2FAB_D3_I0(RAM2FAB_D[51]),
	.Tile_X9Y9_RAM2FAB_D3_I1(RAM2FAB_D[50]),
	.Tile_X9Y9_RAM2FAB_D3_I2(RAM2FAB_D[49]),
	.Tile_X9Y9_RAM2FAB_D3_I3(RAM2FAB_D[48]),
	.Tile_X9Y10_RAM2FAB_D0_I0(RAM2FAB_D[47]),
	.Tile_X9Y10_RAM2FAB_D0_I1(RAM2FAB_D[46]),
	.Tile_X9Y10_RAM2FAB_D0_I2(RAM2FAB_D[45]),
	.Tile_X9Y10_RAM2FAB_D0_I3(RAM2FAB_D[44]),
	.Tile_X9Y10_RAM2FAB_D1_I0(RAM2FAB_D[43]),
	.Tile_X9Y10_RAM2FAB_D1_I1(RAM2FAB_D[42]),
	.Tile_X9Y10_RAM2FAB_D1_I2(RAM2FAB_D[41]),
	.Tile_X9Y10_RAM2FAB_D1_I3(RAM2FAB_D[40]),
	.Tile_X9Y10_RAM2FAB_D2_I0(RAM2FAB_D[39]),
	.Tile_X9Y10_RAM2FAB_D2_I1(RAM2FAB_D[38]),
	.Tile_X9Y10_RAM2FAB_D2_I2(RAM2FAB_D[37]),
	.Tile_X9Y10_RAM2FAB_D2_I3(RAM2FAB_D[36]),
	.Tile_X9Y10_RAM2FAB_D3_I0(RAM2FAB_D[35]),
	.Tile_X9Y10_RAM2FAB_D3_I1(RAM2FAB_D[34]),
	.Tile_X9Y10_RAM2FAB_D3_I2(RAM2FAB_D[33]),
	.Tile_X9Y10_RAM2FAB_D3_I3(RAM2FAB_D[32]),
	.Tile_X9Y11_RAM2FAB_D0_I0(RAM2FAB_D[31]),
	.Tile_X9Y11_RAM2FAB_D0_I1(RAM2FAB_D[30]),
	.Tile_X9Y11_RAM2FAB_D0_I2(RAM2FAB_D[29]),
	.Tile_X9Y11_RAM2FAB_D0_I3(RAM2FAB_D[28]),
	.Tile_X9Y11_RAM2FAB_D1_I0(RAM2FAB_D[27]),
	.Tile_X9Y11_RAM2FAB_D1_I1(RAM2FAB_D[26]),
	.Tile_X9Y11_RAM2FAB_D1_I2(RAM2FAB_D[25]),
	.Tile_X9Y11_RAM2FAB_D1_I3(RAM2FAB_D[24]),
	.Tile_X9Y11_RAM2FAB_D2_I0(RAM2FAB_D[23]),
	.Tile_X9Y11_RAM2FAB_D2_I1(RAM2FAB_D[22]),
	.Tile_X9Y11_RAM2FAB_D2_I2(RAM2FAB_D[21]),
	.Tile_X9Y11_RAM2FAB_D2_I3(RAM2FAB_D[20]),
	.Tile_X9Y11_RAM2FAB_D3_I0(RAM2FAB_D[19]),
	.Tile_X9Y11_RAM2FAB_D3_I1(RAM2FAB_D[18]),
	.Tile_X9Y11_RAM2FAB_D3_I2(RAM2FAB_D[17]),
	.Tile_X9Y11_RAM2FAB_D3_I3(RAM2FAB_D[16]),
	.Tile_X9Y12_RAM2FAB_D0_I0(RAM2FAB_D[15]),
	.Tile_X9Y12_RAM2FAB_D0_I1(RAM2FAB_D[14]),
	.Tile_X9Y12_RAM2FAB_D0_I2(RAM2FAB_D[13]),
	.Tile_X9Y12_RAM2FAB_D0_I3(RAM2FAB_D[12]),
	.Tile_X9Y12_RAM2FAB_D1_I0(RAM2FAB_D[11]),
	.Tile_X9Y12_RAM2FAB_D1_I1(RAM2FAB_D[10]),
	.Tile_X9Y12_RAM2FAB_D1_I2(RAM2FAB_D[9]),
	.Tile_X9Y12_RAM2FAB_D1_I3(RAM2FAB_D[8]),
	.Tile_X9Y12_RAM2FAB_D2_I0(RAM2FAB_D[7]),
	.Tile_X9Y12_RAM2FAB_D2_I1(RAM2FAB_D[6]),
	.Tile_X9Y12_RAM2FAB_D2_I2(RAM2FAB_D[5]),
	.Tile_X9Y12_RAM2FAB_D2_I3(RAM2FAB_D[4]),
	.Tile_X9Y12_RAM2FAB_D3_I0(RAM2FAB_D[3]),
	.Tile_X9Y12_RAM2FAB_D3_I1(RAM2FAB_D[2]),
	.Tile_X9Y12_RAM2FAB_D3_I2(RAM2FAB_D[1]),
	.Tile_X9Y12_RAM2FAB_D3_I3(RAM2FAB_D[0]),

	.Tile_X9Y1_FAB2RAM_D0_O0(FAB2RAM_D[191]),
	.Tile_X9Y1_FAB2RAM_D0_O1(FAB2RAM_D[190]),
	.Tile_X9Y1_FAB2RAM_D0_O2(FAB2RAM_D[189]),
	.Tile_X9Y1_FAB2RAM_D0_O3(FAB2RAM_D[188]),
	.Tile_X9Y1_FAB2RAM_D1_O0(FAB2RAM_D[187]),
	.Tile_X9Y1_FAB2RAM_D1_O1(FAB2RAM_D[186]),
	.Tile_X9Y1_FAB2RAM_D1_O2(FAB2RAM_D[185]),
	.Tile_X9Y1_FAB2RAM_D1_O3(FAB2RAM_D[184]),
	.Tile_X9Y1_FAB2RAM_D2_O0(FAB2RAM_D[183]),
	.Tile_X9Y1_FAB2RAM_D2_O1(FAB2RAM_D[182]),
	.Tile_X9Y1_FAB2RAM_D2_O2(FAB2RAM_D[181]),
	.Tile_X9Y1_FAB2RAM_D2_O3(FAB2RAM_D[180]),
	.Tile_X9Y1_FAB2RAM_D3_O0(FAB2RAM_D[179]),
	.Tile_X9Y1_FAB2RAM_D3_O1(FAB2RAM_D[178]),
	.Tile_X9Y1_FAB2RAM_D3_O2(FAB2RAM_D[177]),
	.Tile_X9Y1_FAB2RAM_D3_O3(FAB2RAM_D[176]),
	.Tile_X9Y2_FAB2RAM_D0_O0(FAB2RAM_D[175]),
	.Tile_X9Y2_FAB2RAM_D0_O1(FAB2RAM_D[174]),
	.Tile_X9Y2_FAB2RAM_D0_O2(FAB2RAM_D[173]),
	.Tile_X9Y2_FAB2RAM_D0_O3(FAB2RAM_D[172]),
	.Tile_X9Y2_FAB2RAM_D1_O0(FAB2RAM_D[171]),
	.Tile_X9Y2_FAB2RAM_D1_O1(FAB2RAM_D[170]),
	.Tile_X9Y2_FAB2RAM_D1_O2(FAB2RAM_D[169]),
	.Tile_X9Y2_FAB2RAM_D1_O3(FAB2RAM_D[168]),
	.Tile_X9Y2_FAB2RAM_D2_O0(FAB2RAM_D[167]),
	.Tile_X9Y2_FAB2RAM_D2_O1(FAB2RAM_D[166]),
	.Tile_X9Y2_FAB2RAM_D2_O2(FAB2RAM_D[165]),
	.Tile_X9Y2_FAB2RAM_D2_O3(FAB2RAM_D[164]),
	.Tile_X9Y2_FAB2RAM_D3_O0(FAB2RAM_D[163]),
	.Tile_X9Y2_FAB2RAM_D3_O1(FAB2RAM_D[162]),
	.Tile_X9Y2_FAB2RAM_D3_O2(FAB2RAM_D[161]),
	.Tile_X9Y2_FAB2RAM_D3_O3(FAB2RAM_D[160]),
	.Tile_X9Y3_FAB2RAM_D0_O0(FAB2RAM_D[159]),
	.Tile_X9Y3_FAB2RAM_D0_O1(FAB2RAM_D[158]),
	.Tile_X9Y3_FAB2RAM_D0_O2(FAB2RAM_D[157]),
	.Tile_X9Y3_FAB2RAM_D0_O3(FAB2RAM_D[156]),
	.Tile_X9Y3_FAB2RAM_D1_O0(FAB2RAM_D[155]),
	.Tile_X9Y3_FAB2RAM_D1_O1(FAB2RAM_D[154]),
	.Tile_X9Y3_FAB2RAM_D1_O2(FAB2RAM_D[153]),
	.Tile_X9Y3_FAB2RAM_D1_O3(FAB2RAM_D[152]),
	.Tile_X9Y3_FAB2RAM_D2_O0(FAB2RAM_D[151]),
	.Tile_X9Y3_FAB2RAM_D2_O1(FAB2RAM_D[150]),
	.Tile_X9Y3_FAB2RAM_D2_O2(FAB2RAM_D[149]),
	.Tile_X9Y3_FAB2RAM_D2_O3(FAB2RAM_D[148]),
	.Tile_X9Y3_FAB2RAM_D3_O0(FAB2RAM_D[147]),
	.Tile_X9Y3_FAB2RAM_D3_O1(FAB2RAM_D[146]),
	.Tile_X9Y3_FAB2RAM_D3_O2(FAB2RAM_D[145]),
	.Tile_X9Y3_FAB2RAM_D3_O3(FAB2RAM_D[144]),
	.Tile_X9Y4_FAB2RAM_D0_O0(FAB2RAM_D[143]),
	.Tile_X9Y4_FAB2RAM_D0_O1(FAB2RAM_D[142]),
	.Tile_X9Y4_FAB2RAM_D0_O2(FAB2RAM_D[141]),
	.Tile_X9Y4_FAB2RAM_D0_O3(FAB2RAM_D[140]),
	.Tile_X9Y4_FAB2RAM_D1_O0(FAB2RAM_D[139]),
	.Tile_X9Y4_FAB2RAM_D1_O1(FAB2RAM_D[138]),
	.Tile_X9Y4_FAB2RAM_D1_O2(FAB2RAM_D[137]),
	.Tile_X9Y4_FAB2RAM_D1_O3(FAB2RAM_D[136]),
	.Tile_X9Y4_FAB2RAM_D2_O0(FAB2RAM_D[135]),
	.Tile_X9Y4_FAB2RAM_D2_O1(FAB2RAM_D[134]),
	.Tile_X9Y4_FAB2RAM_D2_O2(FAB2RAM_D[133]),
	.Tile_X9Y4_FAB2RAM_D2_O3(FAB2RAM_D[132]),
	.Tile_X9Y4_FAB2RAM_D3_O0(FAB2RAM_D[131]),
	.Tile_X9Y4_FAB2RAM_D3_O1(FAB2RAM_D[130]),
	.Tile_X9Y4_FAB2RAM_D3_O2(FAB2RAM_D[129]),
	.Tile_X9Y4_FAB2RAM_D3_O3(FAB2RAM_D[128]),
	.Tile_X9Y5_FAB2RAM_D0_O0(FAB2RAM_D[127]),
	.Tile_X9Y5_FAB2RAM_D0_O1(FAB2RAM_D[126]),
	.Tile_X9Y5_FAB2RAM_D0_O2(FAB2RAM_D[125]),
	.Tile_X9Y5_FAB2RAM_D0_O3(FAB2RAM_D[124]),
	.Tile_X9Y5_FAB2RAM_D1_O0(FAB2RAM_D[123]),
	.Tile_X9Y5_FAB2RAM_D1_O1(FAB2RAM_D[122]),
	.Tile_X9Y5_FAB2RAM_D1_O2(FAB2RAM_D[121]),
	.Tile_X9Y5_FAB2RAM_D1_O3(FAB2RAM_D[120]),
	.Tile_X9Y5_FAB2RAM_D2_O0(FAB2RAM_D[119]),
	.Tile_X9Y5_FAB2RAM_D2_O1(FAB2RAM_D[118]),
	.Tile_X9Y5_FAB2RAM_D2_O2(FAB2RAM_D[117]),
	.Tile_X9Y5_FAB2RAM_D2_O3(FAB2RAM_D[116]),
	.Tile_X9Y5_FAB2RAM_D3_O0(FAB2RAM_D[115]),
	.Tile_X9Y5_FAB2RAM_D3_O1(FAB2RAM_D[114]),
	.Tile_X9Y5_FAB2RAM_D3_O2(FAB2RAM_D[113]),
	.Tile_X9Y5_FAB2RAM_D3_O3(FAB2RAM_D[112]),
	.Tile_X9Y6_FAB2RAM_D0_O0(FAB2RAM_D[111]),
	.Tile_X9Y6_FAB2RAM_D0_O1(FAB2RAM_D[110]),
	.Tile_X9Y6_FAB2RAM_D0_O2(FAB2RAM_D[109]),
	.Tile_X9Y6_FAB2RAM_D0_O3(FAB2RAM_D[108]),
	.Tile_X9Y6_FAB2RAM_D1_O0(FAB2RAM_D[107]),
	.Tile_X9Y6_FAB2RAM_D1_O1(FAB2RAM_D[106]),
	.Tile_X9Y6_FAB2RAM_D1_O2(FAB2RAM_D[105]),
	.Tile_X9Y6_FAB2RAM_D1_O3(FAB2RAM_D[104]),
	.Tile_X9Y6_FAB2RAM_D2_O0(FAB2RAM_D[103]),
	.Tile_X9Y6_FAB2RAM_D2_O1(FAB2RAM_D[102]),
	.Tile_X9Y6_FAB2RAM_D2_O2(FAB2RAM_D[101]),
	.Tile_X9Y6_FAB2RAM_D2_O3(FAB2RAM_D[100]),
	.Tile_X9Y6_FAB2RAM_D3_O0(FAB2RAM_D[99]),
	.Tile_X9Y6_FAB2RAM_D3_O1(FAB2RAM_D[98]),
	.Tile_X9Y6_FAB2RAM_D3_O2(FAB2RAM_D[97]),
	.Tile_X9Y6_FAB2RAM_D3_O3(FAB2RAM_D[96]),
	.Tile_X9Y7_FAB2RAM_D0_O0(FAB2RAM_D[95]),
	.Tile_X9Y7_FAB2RAM_D0_O1(FAB2RAM_D[94]),
	.Tile_X9Y7_FAB2RAM_D0_O2(FAB2RAM_D[93]),
	.Tile_X9Y7_FAB2RAM_D0_O3(FAB2RAM_D[92]),
	.Tile_X9Y7_FAB2RAM_D1_O0(FAB2RAM_D[91]),
	.Tile_X9Y7_FAB2RAM_D1_O1(FAB2RAM_D[90]),
	.Tile_X9Y7_FAB2RAM_D1_O2(FAB2RAM_D[89]),
	.Tile_X9Y7_FAB2RAM_D1_O3(FAB2RAM_D[88]),
	.Tile_X9Y7_FAB2RAM_D2_O0(FAB2RAM_D[87]),
	.Tile_X9Y7_FAB2RAM_D2_O1(FAB2RAM_D[86]),
	.Tile_X9Y7_FAB2RAM_D2_O2(FAB2RAM_D[85]),
	.Tile_X9Y7_FAB2RAM_D2_O3(FAB2RAM_D[84]),
	.Tile_X9Y7_FAB2RAM_D3_O0(FAB2RAM_D[83]),
	.Tile_X9Y7_FAB2RAM_D3_O1(FAB2RAM_D[82]),
	.Tile_X9Y7_FAB2RAM_D3_O2(FAB2RAM_D[81]),
	.Tile_X9Y7_FAB2RAM_D3_O3(FAB2RAM_D[80]),
	.Tile_X9Y8_FAB2RAM_D0_O0(FAB2RAM_D[79]),
	.Tile_X9Y8_FAB2RAM_D0_O1(FAB2RAM_D[78]),
	.Tile_X9Y8_FAB2RAM_D0_O2(FAB2RAM_D[77]),
	.Tile_X9Y8_FAB2RAM_D0_O3(FAB2RAM_D[76]),
	.Tile_X9Y8_FAB2RAM_D1_O0(FAB2RAM_D[75]),
	.Tile_X9Y8_FAB2RAM_D1_O1(FAB2RAM_D[74]),
	.Tile_X9Y8_FAB2RAM_D1_O2(FAB2RAM_D[73]),
	.Tile_X9Y8_FAB2RAM_D1_O3(FAB2RAM_D[72]),
	.Tile_X9Y8_FAB2RAM_D2_O0(FAB2RAM_D[71]),
	.Tile_X9Y8_FAB2RAM_D2_O1(FAB2RAM_D[70]),
	.Tile_X9Y8_FAB2RAM_D2_O2(FAB2RAM_D[69]),
	.Tile_X9Y8_FAB2RAM_D2_O3(FAB2RAM_D[68]),
	.Tile_X9Y8_FAB2RAM_D3_O0(FAB2RAM_D[67]),
	.Tile_X9Y8_FAB2RAM_D3_O1(FAB2RAM_D[66]),
	.Tile_X9Y8_FAB2RAM_D3_O2(FAB2RAM_D[65]),
	.Tile_X9Y8_FAB2RAM_D3_O3(FAB2RAM_D[64]),
	.Tile_X9Y9_FAB2RAM_D0_O0(FAB2RAM_D[63]),
	.Tile_X9Y9_FAB2RAM_D0_O1(FAB2RAM_D[62]),
	.Tile_X9Y9_FAB2RAM_D0_O2(FAB2RAM_D[61]),
	.Tile_X9Y9_FAB2RAM_D0_O3(FAB2RAM_D[60]),
	.Tile_X9Y9_FAB2RAM_D1_O0(FAB2RAM_D[59]),
	.Tile_X9Y9_FAB2RAM_D1_O1(FAB2RAM_D[58]),
	.Tile_X9Y9_FAB2RAM_D1_O2(FAB2RAM_D[57]),
	.Tile_X9Y9_FAB2RAM_D1_O3(FAB2RAM_D[56]),
	.Tile_X9Y9_FAB2RAM_D2_O0(FAB2RAM_D[55]),
	.Tile_X9Y9_FAB2RAM_D2_O1(FAB2RAM_D[54]),
	.Tile_X9Y9_FAB2RAM_D2_O2(FAB2RAM_D[53]),
	.Tile_X9Y9_FAB2RAM_D2_O3(FAB2RAM_D[52]),
	.Tile_X9Y9_FAB2RAM_D3_O0(FAB2RAM_D[51]),
	.Tile_X9Y9_FAB2RAM_D3_O1(FAB2RAM_D[50]),
	.Tile_X9Y9_FAB2RAM_D3_O2(FAB2RAM_D[49]),
	.Tile_X9Y9_FAB2RAM_D3_O3(FAB2RAM_D[48]),
	.Tile_X9Y10_FAB2RAM_D0_O0(FAB2RAM_D[47]),
	.Tile_X9Y10_FAB2RAM_D0_O1(FAB2RAM_D[46]),
	.Tile_X9Y10_FAB2RAM_D0_O2(FAB2RAM_D[45]),
	.Tile_X9Y10_FAB2RAM_D0_O3(FAB2RAM_D[44]),
	.Tile_X9Y10_FAB2RAM_D1_O0(FAB2RAM_D[43]),
	.Tile_X9Y10_FAB2RAM_D1_O1(FAB2RAM_D[42]),
	.Tile_X9Y10_FAB2RAM_D1_O2(FAB2RAM_D[41]),
	.Tile_X9Y10_FAB2RAM_D1_O3(FAB2RAM_D[40]),
	.Tile_X9Y10_FAB2RAM_D2_O0(FAB2RAM_D[39]),
	.Tile_X9Y10_FAB2RAM_D2_O1(FAB2RAM_D[38]),
	.Tile_X9Y10_FAB2RAM_D2_O2(FAB2RAM_D[37]),
	.Tile_X9Y10_FAB2RAM_D2_O3(FAB2RAM_D[36]),
	.Tile_X9Y10_FAB2RAM_D3_O0(FAB2RAM_D[35]),
	.Tile_X9Y10_FAB2RAM_D3_O1(FAB2RAM_D[34]),
	.Tile_X9Y10_FAB2RAM_D3_O2(FAB2RAM_D[33]),
	.Tile_X9Y10_FAB2RAM_D3_O3(FAB2RAM_D[32]),
	.Tile_X9Y11_FAB2RAM_D0_O0(FAB2RAM_D[31]),
	.Tile_X9Y11_FAB2RAM_D0_O1(FAB2RAM_D[30]),
	.Tile_X9Y11_FAB2RAM_D0_O2(FAB2RAM_D[29]),
	.Tile_X9Y11_FAB2RAM_D0_O3(FAB2RAM_D[28]),
	.Tile_X9Y11_FAB2RAM_D1_O0(FAB2RAM_D[27]),
	.Tile_X9Y11_FAB2RAM_D1_O1(FAB2RAM_D[26]),
	.Tile_X9Y11_FAB2RAM_D1_O2(FAB2RAM_D[25]),
	.Tile_X9Y11_FAB2RAM_D1_O3(FAB2RAM_D[24]),
	.Tile_X9Y11_FAB2RAM_D2_O0(FAB2RAM_D[23]),
	.Tile_X9Y11_FAB2RAM_D2_O1(FAB2RAM_D[22]),
	.Tile_X9Y11_FAB2RAM_D2_O2(FAB2RAM_D[21]),
	.Tile_X9Y11_FAB2RAM_D2_O3(FAB2RAM_D[20]),
	.Tile_X9Y11_FAB2RAM_D3_O0(FAB2RAM_D[19]),
	.Tile_X9Y11_FAB2RAM_D3_O1(FAB2RAM_D[18]),
	.Tile_X9Y11_FAB2RAM_D3_O2(FAB2RAM_D[17]),
	.Tile_X9Y11_FAB2RAM_D3_O3(FAB2RAM_D[16]),
	.Tile_X9Y12_FAB2RAM_D0_O0(FAB2RAM_D[15]),
	.Tile_X9Y12_FAB2RAM_D0_O1(FAB2RAM_D[14]),
	.Tile_X9Y12_FAB2RAM_D0_O2(FAB2RAM_D[13]),
	.Tile_X9Y12_FAB2RAM_D0_O3(FAB2RAM_D[12]),
	.Tile_X9Y12_FAB2RAM_D1_O0(FAB2RAM_D[11]),
	.Tile_X9Y12_FAB2RAM_D1_O1(FAB2RAM_D[10]),
	.Tile_X9Y12_FAB2RAM_D1_O2(FAB2RAM_D[9]),
	.Tile_X9Y12_FAB2RAM_D1_O3(FAB2RAM_D[8]),
	.Tile_X9Y12_FAB2RAM_D2_O0(FAB2RAM_D[7]),
	.Tile_X9Y12_FAB2RAM_D2_O1(FAB2RAM_D[6]),
	.Tile_X9Y12_FAB2RAM_D2_O2(FAB2RAM_D[5]),
	.Tile_X9Y12_FAB2RAM_D2_O3(FAB2RAM_D[4]),
	.Tile_X9Y12_FAB2RAM_D3_O0(FAB2RAM_D[3]),
	.Tile_X9Y12_FAB2RAM_D3_O1(FAB2RAM_D[2]),
	.Tile_X9Y12_FAB2RAM_D3_O2(FAB2RAM_D[1]),
	.Tile_X9Y12_FAB2RAM_D3_O3(FAB2RAM_D[0]),

	.Tile_X9Y1_FAB2RAM_A0_O0(FAB2RAM_A[95]),
	.Tile_X9Y1_FAB2RAM_A0_O1(FAB2RAM_A[94]),
	.Tile_X9Y1_FAB2RAM_A0_O2(FAB2RAM_A[93]),
	.Tile_X9Y1_FAB2RAM_A0_O3(FAB2RAM_A[92]),
	.Tile_X9Y1_FAB2RAM_A1_O0(FAB2RAM_A[91]),
	.Tile_X9Y1_FAB2RAM_A1_O1(FAB2RAM_A[90]),
	.Tile_X9Y1_FAB2RAM_A1_O2(FAB2RAM_A[89]),
	.Tile_X9Y1_FAB2RAM_A1_O3(FAB2RAM_A[88]),
	.Tile_X9Y2_FAB2RAM_A0_O0(FAB2RAM_A[87]),
	.Tile_X9Y2_FAB2RAM_A0_O1(FAB2RAM_A[86]),
	.Tile_X9Y2_FAB2RAM_A0_O2(FAB2RAM_A[85]),
	.Tile_X9Y2_FAB2RAM_A0_O3(FAB2RAM_A[84]),
	.Tile_X9Y2_FAB2RAM_A1_O0(FAB2RAM_A[83]),
	.Tile_X9Y2_FAB2RAM_A1_O1(FAB2RAM_A[82]),
	.Tile_X9Y2_FAB2RAM_A1_O2(FAB2RAM_A[81]),
	.Tile_X9Y2_FAB2RAM_A1_O3(FAB2RAM_A[80]),
	.Tile_X9Y3_FAB2RAM_A0_O0(FAB2RAM_A[79]),
	.Tile_X9Y3_FAB2RAM_A0_O1(FAB2RAM_A[78]),
	.Tile_X9Y3_FAB2RAM_A0_O2(FAB2RAM_A[77]),
	.Tile_X9Y3_FAB2RAM_A0_O3(FAB2RAM_A[76]),
	.Tile_X9Y3_FAB2RAM_A1_O0(FAB2RAM_A[75]),
	.Tile_X9Y3_FAB2RAM_A1_O1(FAB2RAM_A[74]),
	.Tile_X9Y3_FAB2RAM_A1_O2(FAB2RAM_A[73]),
	.Tile_X9Y3_FAB2RAM_A1_O3(FAB2RAM_A[72]),
	.Tile_X9Y4_FAB2RAM_A0_O0(FAB2RAM_A[71]),
	.Tile_X9Y4_FAB2RAM_A0_O1(FAB2RAM_A[70]),
	.Tile_X9Y4_FAB2RAM_A0_O2(FAB2RAM_A[69]),
	.Tile_X9Y4_FAB2RAM_A0_O3(FAB2RAM_A[68]),
	.Tile_X9Y4_FAB2RAM_A1_O0(FAB2RAM_A[67]),
	.Tile_X9Y4_FAB2RAM_A1_O1(FAB2RAM_A[66]),
	.Tile_X9Y4_FAB2RAM_A1_O2(FAB2RAM_A[65]),
	.Tile_X9Y4_FAB2RAM_A1_O3(FAB2RAM_A[64]),
	.Tile_X9Y5_FAB2RAM_A0_O0(FAB2RAM_A[63]),
	.Tile_X9Y5_FAB2RAM_A0_O1(FAB2RAM_A[62]),
	.Tile_X9Y5_FAB2RAM_A0_O2(FAB2RAM_A[61]),
	.Tile_X9Y5_FAB2RAM_A0_O3(FAB2RAM_A[60]),
	.Tile_X9Y5_FAB2RAM_A1_O0(FAB2RAM_A[59]),
	.Tile_X9Y5_FAB2RAM_A1_O1(FAB2RAM_A[58]),
	.Tile_X9Y5_FAB2RAM_A1_O2(FAB2RAM_A[57]),
	.Tile_X9Y5_FAB2RAM_A1_O3(FAB2RAM_A[56]),
	.Tile_X9Y6_FAB2RAM_A0_O0(FAB2RAM_A[55]),
	.Tile_X9Y6_FAB2RAM_A0_O1(FAB2RAM_A[54]),
	.Tile_X9Y6_FAB2RAM_A0_O2(FAB2RAM_A[53]),
	.Tile_X9Y6_FAB2RAM_A0_O3(FAB2RAM_A[52]),
	.Tile_X9Y6_FAB2RAM_A1_O0(FAB2RAM_A[51]),
	.Tile_X9Y6_FAB2RAM_A1_O1(FAB2RAM_A[50]),
	.Tile_X9Y6_FAB2RAM_A1_O2(FAB2RAM_A[49]),
	.Tile_X9Y6_FAB2RAM_A1_O3(FAB2RAM_A[48]),
	.Tile_X9Y7_FAB2RAM_A0_O0(FAB2RAM_A[47]),
	.Tile_X9Y7_FAB2RAM_A0_O1(FAB2RAM_A[46]),
	.Tile_X9Y7_FAB2RAM_A0_O2(FAB2RAM_A[45]),
	.Tile_X9Y7_FAB2RAM_A0_O3(FAB2RAM_A[44]),
	.Tile_X9Y7_FAB2RAM_A1_O0(FAB2RAM_A[43]),
	.Tile_X9Y7_FAB2RAM_A1_O1(FAB2RAM_A[42]),
	.Tile_X9Y7_FAB2RAM_A1_O2(FAB2RAM_A[41]),
	.Tile_X9Y7_FAB2RAM_A1_O3(FAB2RAM_A[40]),
	.Tile_X9Y8_FAB2RAM_A0_O0(FAB2RAM_A[39]),
	.Tile_X9Y8_FAB2RAM_A0_O1(FAB2RAM_A[38]),
	.Tile_X9Y8_FAB2RAM_A0_O2(FAB2RAM_A[37]),
	.Tile_X9Y8_FAB2RAM_A0_O3(FAB2RAM_A[36]),
	.Tile_X9Y8_FAB2RAM_A1_O0(FAB2RAM_A[35]),
	.Tile_X9Y8_FAB2RAM_A1_O1(FAB2RAM_A[34]),
	.Tile_X9Y8_FAB2RAM_A1_O2(FAB2RAM_A[33]),
	.Tile_X9Y8_FAB2RAM_A1_O3(FAB2RAM_A[32]),
	.Tile_X9Y9_FAB2RAM_A0_O0(FAB2RAM_A[31]),
	.Tile_X9Y9_FAB2RAM_A0_O1(FAB2RAM_A[30]),
	.Tile_X9Y9_FAB2RAM_A0_O2(FAB2RAM_A[29]),
	.Tile_X9Y9_FAB2RAM_A0_O3(FAB2RAM_A[28]),
	.Tile_X9Y9_FAB2RAM_A1_O0(FAB2RAM_A[27]),
	.Tile_X9Y9_FAB2RAM_A1_O1(FAB2RAM_A[26]),
	.Tile_X9Y9_FAB2RAM_A1_O2(FAB2RAM_A[25]),
	.Tile_X9Y9_FAB2RAM_A1_O3(FAB2RAM_A[24]),
	.Tile_X9Y10_FAB2RAM_A0_O0(FAB2RAM_A[23]),
	.Tile_X9Y10_FAB2RAM_A0_O1(FAB2RAM_A[22]),
	.Tile_X9Y10_FAB2RAM_A0_O2(FAB2RAM_A[21]),
	.Tile_X9Y10_FAB2RAM_A0_O3(FAB2RAM_A[20]),
	.Tile_X9Y10_FAB2RAM_A1_O0(FAB2RAM_A[19]),
	.Tile_X9Y10_FAB2RAM_A1_O1(FAB2RAM_A[18]),
	.Tile_X9Y10_FAB2RAM_A1_O2(FAB2RAM_A[17]),
	.Tile_X9Y10_FAB2RAM_A1_O3(FAB2RAM_A[16]),
	.Tile_X9Y11_FAB2RAM_A0_O0(FAB2RAM_A[15]),
	.Tile_X9Y11_FAB2RAM_A0_O1(FAB2RAM_A[14]),
	.Tile_X9Y11_FAB2RAM_A0_O2(FAB2RAM_A[13]),
	.Tile_X9Y11_FAB2RAM_A0_O3(FAB2RAM_A[12]),
	.Tile_X9Y11_FAB2RAM_A1_O0(FAB2RAM_A[11]),
	.Tile_X9Y11_FAB2RAM_A1_O1(FAB2RAM_A[10]),
	.Tile_X9Y11_FAB2RAM_A1_O2(FAB2RAM_A[9]),
	.Tile_X9Y11_FAB2RAM_A1_O3(FAB2RAM_A[8]),
	.Tile_X9Y12_FAB2RAM_A0_O0(FAB2RAM_A[7]),
	.Tile_X9Y12_FAB2RAM_A0_O1(FAB2RAM_A[6]),
	.Tile_X9Y12_FAB2RAM_A0_O2(FAB2RAM_A[5]),
	.Tile_X9Y12_FAB2RAM_A0_O3(FAB2RAM_A[4]),
	.Tile_X9Y12_FAB2RAM_A1_O0(FAB2RAM_A[3]),
	.Tile_X9Y12_FAB2RAM_A1_O1(FAB2RAM_A[2]),
	.Tile_X9Y12_FAB2RAM_A1_O2(FAB2RAM_A[1]),
	.Tile_X9Y12_FAB2RAM_A1_O3(FAB2RAM_A[0]),

	.Tile_X9Y1_FAB2RAM_C_O0(FAB2RAM_C[47]),
	.Tile_X9Y1_FAB2RAM_C_O1(FAB2RAM_C[46]),
	.Tile_X9Y1_FAB2RAM_C_O2(FAB2RAM_C[45]),
	.Tile_X9Y1_FAB2RAM_C_O3(FAB2RAM_C[44]),
	.Tile_X9Y2_FAB2RAM_C_O0(FAB2RAM_C[43]),
	.Tile_X9Y2_FAB2RAM_C_O1(FAB2RAM_C[42]),
	.Tile_X9Y2_FAB2RAM_C_O2(FAB2RAM_C[41]),
	.Tile_X9Y2_FAB2RAM_C_O3(FAB2RAM_C[40]),
	.Tile_X9Y3_FAB2RAM_C_O0(FAB2RAM_C[39]),
	.Tile_X9Y3_FAB2RAM_C_O1(FAB2RAM_C[38]),
	.Tile_X9Y3_FAB2RAM_C_O2(FAB2RAM_C[37]),
	.Tile_X9Y3_FAB2RAM_C_O3(FAB2RAM_C[36]),
	.Tile_X9Y4_FAB2RAM_C_O0(FAB2RAM_C[35]),
	.Tile_X9Y4_FAB2RAM_C_O1(FAB2RAM_C[34]),
	.Tile_X9Y4_FAB2RAM_C_O2(FAB2RAM_C[33]),
	.Tile_X9Y4_FAB2RAM_C_O3(FAB2RAM_C[32]),
	.Tile_X9Y5_FAB2RAM_C_O0(FAB2RAM_C[31]),
	.Tile_X9Y5_FAB2RAM_C_O1(FAB2RAM_C[30]),
	.Tile_X9Y5_FAB2RAM_C_O2(FAB2RAM_C[29]),
	.Tile_X9Y5_FAB2RAM_C_O3(FAB2RAM_C[28]),
	.Tile_X9Y6_FAB2RAM_C_O0(FAB2RAM_C[27]),
	.Tile_X9Y6_FAB2RAM_C_O1(FAB2RAM_C[26]),
	.Tile_X9Y6_FAB2RAM_C_O2(FAB2RAM_C[25]),
	.Tile_X9Y6_FAB2RAM_C_O3(FAB2RAM_C[24]),
	.Tile_X9Y7_FAB2RAM_C_O0(FAB2RAM_C[23]),
	.Tile_X9Y7_FAB2RAM_C_O1(FAB2RAM_C[22]),
	.Tile_X9Y7_FAB2RAM_C_O2(FAB2RAM_C[21]),
	.Tile_X9Y7_FAB2RAM_C_O3(FAB2RAM_C[20]),
	.Tile_X9Y8_FAB2RAM_C_O0(FAB2RAM_C[19]),
	.Tile_X9Y8_FAB2RAM_C_O1(FAB2RAM_C[18]),
	.Tile_X9Y8_FAB2RAM_C_O2(FAB2RAM_C[17]),
	.Tile_X9Y8_FAB2RAM_C_O3(FAB2RAM_C[16]),
	.Tile_X9Y9_FAB2RAM_C_O0(FAB2RAM_C[15]),
	.Tile_X9Y9_FAB2RAM_C_O1(FAB2RAM_C[14]),
	.Tile_X9Y9_FAB2RAM_C_O2(FAB2RAM_C[13]),
	.Tile_X9Y9_FAB2RAM_C_O3(FAB2RAM_C[12]),
	.Tile_X9Y10_FAB2RAM_C_O0(FAB2RAM_C[11]),
	.Tile_X9Y10_FAB2RAM_C_O1(FAB2RAM_C[10]),
	.Tile_X9Y10_FAB2RAM_C_O2(FAB2RAM_C[9]),
	.Tile_X9Y10_FAB2RAM_C_O3(FAB2RAM_C[8]),
	.Tile_X9Y11_FAB2RAM_C_O0(FAB2RAM_C[7]),
	.Tile_X9Y11_FAB2RAM_C_O1(FAB2RAM_C[6]),
	.Tile_X9Y11_FAB2RAM_C_O2(FAB2RAM_C[5]),
	.Tile_X9Y11_FAB2RAM_C_O3(FAB2RAM_C[4]),
	.Tile_X9Y12_FAB2RAM_C_O0(FAB2RAM_C[3]),
	.Tile_X9Y12_FAB2RAM_C_O1(FAB2RAM_C[2]),
	.Tile_X9Y12_FAB2RAM_C_O2(FAB2RAM_C[1]),
	.Tile_X9Y12_FAB2RAM_C_O3(FAB2RAM_C[0]),

	.Tile_X9Y1_Config_accessC_bit0(Config_accessC[47]),
	.Tile_X9Y1_Config_accessC_bit1(Config_accessC[46]),
	.Tile_X9Y1_Config_accessC_bit2(Config_accessC[45]),
	.Tile_X9Y1_Config_accessC_bit3(Config_accessC[44]),
	.Tile_X9Y2_Config_accessC_bit0(Config_accessC[43]),
	.Tile_X9Y2_Config_accessC_bit1(Config_accessC[42]),
	.Tile_X9Y2_Config_accessC_bit2(Config_accessC[41]),
	.Tile_X9Y2_Config_accessC_bit3(Config_accessC[40]),
	.Tile_X9Y3_Config_accessC_bit0(Config_accessC[39]),
	.Tile_X9Y3_Config_accessC_bit1(Config_accessC[38]),
	.Tile_X9Y3_Config_accessC_bit2(Config_accessC[37]),
	.Tile_X9Y3_Config_accessC_bit3(Config_accessC[36]),
	.Tile_X9Y4_Config_accessC_bit0(Config_accessC[35]),
	.Tile_X9Y4_Config_accessC_bit1(Config_accessC[34]),
	.Tile_X9Y4_Config_accessC_bit2(Config_accessC[33]),
	.Tile_X9Y4_Config_accessC_bit3(Config_accessC[32]),
	.Tile_X9Y5_Config_accessC_bit0(Config_accessC[31]),
	.Tile_X9Y5_Config_accessC_bit1(Config_accessC[30]),
	.Tile_X9Y5_Config_accessC_bit2(Config_accessC[29]),
	.Tile_X9Y5_Config_accessC_bit3(Config_accessC[28]),
	.Tile_X9Y6_Config_accessC_bit0(Config_accessC[27]),
	.Tile_X9Y6_Config_accessC_bit1(Config_accessC[26]),
	.Tile_X9Y6_Config_accessC_bit2(Config_accessC[25]),
	.Tile_X9Y6_Config_accessC_bit3(Config_accessC[24]),
	.Tile_X9Y7_Config_accessC_bit0(Config_accessC[23]),
	.Tile_X9Y7_Config_accessC_bit1(Config_accessC[22]),
	.Tile_X9Y7_Config_accessC_bit2(Config_accessC[21]),
	.Tile_X9Y7_Config_accessC_bit3(Config_accessC[20]),
	.Tile_X9Y8_Config_accessC_bit0(Config_accessC[19]),
	.Tile_X9Y8_Config_accessC_bit1(Config_accessC[18]),
	.Tile_X9Y8_Config_accessC_bit2(Config_accessC[17]),
	.Tile_X9Y8_Config_accessC_bit3(Config_accessC[16]),
	.Tile_X9Y9_Config_accessC_bit0(Config_accessC[15]),
	.Tile_X9Y9_Config_accessC_bit1(Config_accessC[14]),
	.Tile_X9Y9_Config_accessC_bit2(Config_accessC[13]),
	.Tile_X9Y9_Config_accessC_bit3(Config_accessC[12]),
	.Tile_X9Y10_Config_accessC_bit0(Config_accessC[11]),
	.Tile_X9Y10_Config_accessC_bit1(Config_accessC[10]),
	.Tile_X9Y10_Config_accessC_bit2(Config_accessC[9]),
	.Tile_X9Y10_Config_accessC_bit3(Config_accessC[8]),
	.Tile_X9Y11_Config_accessC_bit0(Config_accessC[7]),
	.Tile_X9Y11_Config_accessC_bit1(Config_accessC[6]),
	.Tile_X9Y11_Config_accessC_bit2(Config_accessC[5]),
	.Tile_X9Y11_Config_accessC_bit3(Config_accessC[4]),
	.Tile_X9Y12_Config_accessC_bit0(Config_accessC[3]),
	.Tile_X9Y12_Config_accessC_bit1(Config_accessC[2]),
	.Tile_X9Y12_Config_accessC_bit2(Config_accessC[1]),
	.Tile_X9Y12_Config_accessC_bit3(Config_accessC[0]),

	//declarations
	.UserCLK(CLK),
	.FrameData(FrameData),
	.FrameStrobe(FrameSelect)
	);

// Bottom 2 RAMs replaced by WB IF

/*
	BlockRAM_1KB Inst_BlockRAM_0 (
	.clk(CLK),
	.rd_addr(FAB2RAM_A[7:0]),
	.rd_data(RAM2FAB_D[31:0]),
	.wr_addr(FAB2RAM_A[15:8]),
	.wr_data(FAB2RAM_D[31:0]),
	.C0(FAB2RAM_C[0]),
	.C1(FAB2RAM_C[1]),
	.C2(FAB2RAM_C[2]),
	.C3(FAB2RAM_C[3]),
	.C4(FAB2RAM_C[4]),
	.C5(FAB2RAM_C[5])
	);

	BlockRAM_1KB Inst_BlockRAM_1 (
	.clk(CLK),
	.rd_addr(FAB2RAM_A[23:16]),
	.rd_data(RAM2FAB_D[63:32]),
	.wr_addr(FAB2RAM_A[31:24]),
	.wr_data(FAB2RAM_D[63:32]),
	.C0(FAB2RAM_C[8]),
	.C1(FAB2RAM_C[9]),
	.C2(FAB2RAM_C[10]),
	.C3(FAB2RAM_C[11]),
	.C4(FAB2RAM_C[12]),
	.C5(FAB2RAM_C[13])
	);
*/
	BlockRAM_1KB Inst_BlockRAM_2 (
	.clk(CLK),
	.rd_addr(FAB2RAM_A[39:32]),
	.rd_data(RAM2FAB_D[95:64]),
	.wr_addr(FAB2RAM_A[47:40]),
	.wr_data(FAB2RAM_D[95:64]),
	.C0(FAB2RAM_C[16]),
	.C1(FAB2RAM_C[17]),
	.C2(FAB2RAM_C[18]),
	.C3(FAB2RAM_C[19]),
	.C4(FAB2RAM_C[20]),
	.C5(FAB2RAM_C[21])
	);

	BlockRAM_1KB Inst_BlockRAM_3 (
	.clk(CLK),
	.rd_addr(FAB2RAM_A[55:48]),
	.rd_data(RAM2FAB_D[127:96]),
	.wr_addr(FAB2RAM_A[63:56]),
	.wr_data(FAB2RAM_D[127:96]),
	.C0(FAB2RAM_C[24]),
	.C1(FAB2RAM_C[25]),
	.C2(FAB2RAM_C[26]),
	.C3(FAB2RAM_C[27]),
	.C4(FAB2RAM_C[28]),
	.C5(FAB2RAM_C[29])
	);

	BlockRAM_1KB Inst_BlockRAM_4 (
	.clk(CLK),
	.rd_addr(FAB2RAM_A[71:64]),
	.rd_data(RAM2FAB_D[159:128]),
	.wr_addr(FAB2RAM_A[79:72]),
	.wr_data(FAB2RAM_D[159:128]),
	.C0(FAB2RAM_C[32]),
	.C1(FAB2RAM_C[33]),
	.C2(FAB2RAM_C[34]),
	.C3(FAB2RAM_C[35]),
	.C4(FAB2RAM_C[36]),
	.C5(FAB2RAM_C[37])
	);

	BlockRAM_1KB Inst_BlockRAM_5 (
	.clk(CLK),
	.rd_addr(FAB2RAM_A[87:80]),
	.rd_data(RAM2FAB_D[191:160]),
	.wr_addr(FAB2RAM_A[95:88]),
	.wr_data(FAB2RAM_D[191:160]),
	.C0(FAB2RAM_C[40]),
	.C1(FAB2RAM_C[41]),
	.C2(FAB2RAM_C[42]),
	.C3(FAB2RAM_C[43]),
	.C4(FAB2RAM_C[44]),
	.C5(FAB2RAM_C[45])
	);

	assign FrameData = {32'h12345678,FrameRegister,32'h12345678};

endmodule

module sky130_fd_sc_hd__inv (
	Y,
	A
	);
	output Y;
	input  A;

	assign Y=~A;
endmodule
