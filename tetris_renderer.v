module font_rom (
    input wire clk,
    input wire [6:0] ascii_code,
    input wire [2:0] row_idx,
    output reg [7:0] row_pixels
);
    reg [7:0] rom [0:4095];
    initial begin
        $readmemh("512_8_bold.mi", rom);
    end
    wire [9:0] rom_addr = {ascii_code[6:0], row_idx[2:0]};
    always @(posedge clk) begin
        row_pixels <= rom[rom_addr];
    end

endmodule

module tetris_renderer (
    input wire clk_25MHz,
    input wire rst_n,
    input wire [9:0] pixel_x,
    input wire [9:0] pixel_y,
    
	 input wire [399:0] matrix_occ,
    input wire signed [4:0] piece_x,
    input wire [5:0] piece_y,
    input wire [2:0] piece_type,
    input wire [15:0] piece_shape,
    input wire [5:0] ghost_y,
    
    input wire [31:0] score,
    input wire [15:0] total_lines,
	 input wire [4:0] current_level,
    
    input wire [2:0] next_piece_type,
    input wire [15:0] next_piece_shape, 
    input wire [2:0] hold_piece_type,
    input wire [15:0] hold_piece_shape,
    input wire hold_valid,
    
    output reg [15:0] rgb_out
);

    // --- COORDINATE CONSTANTS ---
    localparam MATRIX_X = 10'd240;   localparam MATRIX_Y = 10'd80;
    localparam NEXT_BOX_X = 10'd440; localparam NEXT_BOX_Y = 10'd80;
    localparam HOLD_BOX_X = 10'd100; localparam HOLD_BOX_Y = 10'd80;
    localparam SCORE_X = 10'd100;    localparam SCORE_Y = 10'd200;
	 localparam SCORE_W = 10'd80;     localparam SCORE_H = 10'd96;

    // --- BCD SCORE ---
    wire [3:0] score_bcd [9:0];
	 wire [3:0] lines_bcd [4:0];
	 wire [3:0] level_bcd [2:0];
    reg bcd_en;
    always @(posedge clk_25MHz) bcd_en <= (pixel_x == 0 && pixel_y == 0);

    bin2bcd32 score_converter (
        .CLK(clk_25MHz), .RST(rst_n), .en(bcd_en), .bin(score),
        .bcd0(score_bcd[0]), .bcd1(score_bcd[1]), .bcd2(score_bcd[2]), .bcd3(score_bcd[3]), 
        .bcd4(score_bcd[4]), .bcd5(score_bcd[5]), .bcd6(score_bcd[6]));
	 
    bin2bcd32 lines_converter (.CLK(clk_25MHz), .RST(rst_n), .en(bcd_en), .bin({16'd0, total_lines}),
        .bcd0(lines_bcd[0]), .bcd1(lines_bcd[1]), .bcd2(lines_bcd[2]), .bcd3(lines_bcd[3]), .bcd4(lines_bcd[4]));
        
    bin2bcd32 level_converter (.CLK(clk_25MHz), .RST(rst_n), .en(bcd_en), .bin({24'd0, current_level}),
        .bcd0(level_bcd[0]), .bcd1(level_bcd[1]), .bcd2(level_bcd[2]));

    // ========================================================================
    // CYCLE 0: COMBINATIONAL ADDRESS & BOUNDARY CALCULATIONS
    // ========================================================================
    
    // 1. Matrix Index Math (The "No-Multiplier" trick)
    wire [9:0] mat_local_x = pixel_x - MATRIX_X;
    wire [9:0] mat_local_y = pixel_y - MATRIX_Y;
    
    wire [3:0] grid_x = mat_local_x[7:4]; // 0 to 9
    wire [4:0] grid_y = mat_local_y[8:4]; // 0 to 19
    wire [5:0] flat_row = grid_y + 6'd20; // 20 to 39 (Visible screen offset)
    
    // Calculate index = (flat_row * 10) + grid_x = (flat_row * 8) + (flat_row * 2) + grid_x
    wire [8:0] flat_idx = {flat_row, 3'b000} + {2'b00, flat_row, 1'b0} + grid_x;

    // 2. Mino Bounding Box Checks
    wire signed [5:0] s_engine_col = $signed({2'b00, grid_x}); // Cast grid to signed
    wire [5:0] engine_row = flat_row;
    
    wire active_x_match = (s_engine_col >= piece_x) && (s_engine_col < piece_x + 4);
    wire active_y_match = (engine_row >= piece_y) && (engine_row < piece_y + 4);
    wire [3:0] active_shape_idx = 15 - ((engine_row - piece_y) * 4 + (s_engine_col - piece_x));
    
    wire ghost_x_match = (s_engine_col >= piece_x) && (s_engine_col < piece_x + 4);
    wire ghost_y_match = (engine_row >= ghost_y) && (engine_row < ghost_y + 4);
    wire [3:0] ghost_shape_idx = 15 - ((engine_row - ghost_y) * 4 + (s_engine_col - piece_x));

    // 3. Text Calculation
    wire [9:0] text_col = (pixel_x - SCORE_X) >> 3;
    wire [9:0] text_row = (pixel_y - SCORE_Y) >> 3;
    wire [2:0] font_y = (pixel_y - SCORE_Y) & 3'h7;
    
    reg [6:0] ascii_char;
	 
    always @(*) begin
        ascii_char = 7'h20; // Default to space
        if (text_row == 0) begin
            case (text_col)
                0: ascii_char = 7'h53; 1: ascii_char = 7'h43; 2: ascii_char = 7'h4F;
                3: ascii_char = 7'h52; 4: ascii_char = 7'h45;
            endcase
        end else if (text_row == 2) begin
            case (text_col)
                0: ascii_char = 7'h30+score_bcd[6]; 1: ascii_char = 7'h30+score_bcd[5];
                2: ascii_char = 7'h30+score_bcd[4]; 3: ascii_char = 7'h30+score_bcd[3];
                4: ascii_char = 7'h30+score_bcd[2]; 5: ascii_char = 7'h30+score_bcd[1];
                6: ascii_char = 7'h30+score_bcd[0];
            endcase
        end else if (text_row == 4) begin
            case (text_col)
                0: ascii_char = 7'h4C; 1: ascii_char = 7'h49; 2: ascii_char = 7'h4E; 
                3: ascii_char = 7'h45; 4: ascii_char = 7'h53;
            endcase
        end else if (text_row == 6) begin
            case (text_col)
                0: ascii_char = 7'h30 + lines_bcd[4]; 1: ascii_char = 7'h30 + lines_bcd[3];
                2: ascii_char = 7'h30 + lines_bcd[2]; 3: ascii_char = 7'h30 + lines_bcd[1];
                4: ascii_char = 7'h30 + lines_bcd[0];
            endcase
        end else if (text_row == 8) begin
            case (text_col)
                0: ascii_char = 7'h4C; 1: ascii_char = 7'h45; 2: ascii_char = 7'h56;
					 3: ascii_char = 7'h45; 4: ascii_char = 7'h4C;
            endcase
        end else if (text_row == 10) begin
            case (text_col)
                0: ascii_char = 7'h30 + level_bcd[2]; 1: ascii_char = 7'h30 + level_bcd[1];
                2: ascii_char = 7'h30 + level_bcd[0];
            endcase
		  end
    end

    wire [7:0] font_row_pixels;
    font_rom text_font (
        .clk(clk_25MHz),
        .ascii_code(ascii_char),
        .row_idx(font_y),
        .row_pixels(font_row_pixels)
    );

    // ========================================================================
    // CYCLE 1: CLOCKED PIPELINE REGISTERS
    // ========================================================================
    reg [9:0] px_d1, py_d1;
    reg is_active_mino_d1, is_ghost_mino_d1, is_next_mino_d1, is_hld_mino_d1;
    reg mat_is_border_d1, nxt_is_border_d1, hld_is_border_d1;
	 reg is_locked_cell_d1;
	 
	 // Local box coordinates for border alignments
    wire [9:0] nxt_local_x = pixel_x - NEXT_BOX_X;
    wire [9:0] nxt_local_y = pixel_y - NEXT_BOX_Y;
    
    wire [9:0] hld_local_x = pixel_x - HOLD_BOX_X;
    wire [9:0] hld_local_y = pixel_y - HOLD_BOX_Y;

    always @(posedge clk_25MHz) begin
        // Delay coordinates
        px_d1 <= pixel_x;
        py_d1 <= pixel_y;

        // Matrix Data Fetch
        if (pixel_x >= MATRIX_X && pixel_x < MATRIX_X + 160 && 
            pixel_y >= MATRIX_Y && pixel_y < MATRIX_Y + 320) begin
            
            is_locked_cell_d1 <= matrix_occ[flat_idx];
            is_active_mino_d1 <= (active_x_match && active_y_match) ? piece_shape[active_shape_idx] : 1'b0;
            is_ghost_mino_d1 <= (ghost_x_match && ghost_y_match) ? piece_shape[ghost_shape_idx] : 1'b0;
            mat_is_border_d1 <= (mat_local_x[3:0] < 2 || mat_local_x[3:0] > 13 || mat_local_y[3:0] < 2 || mat_local_y[3:0] > 13);
        end else begin
            is_active_mino_d1 <= 1'b0;
            is_ghost_mino_d1 <= 1'b0;
            mat_is_border_d1 <= 1'b0;
        end

        // Box Data Fetch
        nxt_is_border_d1 <= (nxt_local_x[3:0] < 2 || nxt_local_x[3:0] > 13 || nxt_local_y[3:0] < 2 || nxt_local_y[3:0] > 13);
        is_next_mino_d1 <= next_piece_shape[15 - (((pixel_y-NEXT_BOX_Y)>>4)*4 + ((pixel_x-NEXT_BOX_X)>>4))];
        
        hld_is_border_d1 <= (hld_local_x[3:0] < 2 || hld_local_x[3:0] > 13 || hld_local_y[3:0] < 2 || hld_local_y[3:0] > 13);
        is_hld_mino_d1 <= hold_valid && hold_piece_shape[15 - (((pixel_y-HOLD_BOX_Y)>>4)*4 + ((pixel_x-HOLD_BOX_X)>>4))];
		  end

    // ========================================================================
    // FINAL CYCLE: RGB MULTIPLEXER
    // ========================================================================
    function [15:0] get_rgb565(input [2:0] ptype);
        case (ptype)
            3'd1: get_rgb565 = 16'h07FF; 3'd2: get_rgb565 = 16'h001F;
            3'd3: get_rgb565 = 16'hFBA0; 3'd4: get_rgb565 = 16'hFFE0;
            3'd5: get_rgb565 = 16'h07E0; 3'd6: get_rgb565 = 16'h801F;
            3'd7: get_rgb565 = 16'hF800; default: get_rgb565 = 16'h0000;
        endcase
    endfunction

    wire draw_text = font_row_pixels[7 - ((px_d1 - SCORE_X) & 3'h7)];

    always @(*) begin
        rgb_out = 16'h1082; // Background
        
        if (px_d1 >= MATRIX_X && px_d1 < MATRIX_X + 160 && py_d1 >= MATRIX_Y && py_d1 < MATRIX_Y + 320) begin
            if (mat_is_border_d1) begin
                if (is_ghost_mino_d1) rgb_out = get_rgb565(piece_type);
                else rgb_out = 16'h2104; 
            end else begin
                if (is_active_mino_d1) rgb_out = get_rgb565(piece_type);
                else if (is_locked_cell_d1) rgb_out = 16'hAD55;
                else rgb_out = 16'h0000;
            end
        end 
        else if (px_d1 >= NEXT_BOX_X && px_d1 < NEXT_BOX_X + 64 && py_d1 >= NEXT_BOX_Y && py_d1 < NEXT_BOX_Y + 64) begin
            if (is_next_mino_d1) rgb_out = nxt_is_border_d1 ? 16'h0000 : get_rgb565(next_piece_type);
            else rgb_out = 16'h0000;
        end 
        else if (px_d1 >= HOLD_BOX_X && px_d1 < HOLD_BOX_X + 64 && py_d1 >= HOLD_BOX_Y && py_d1 < HOLD_BOX_Y + 64) begin
            if (is_hld_mino_d1) rgb_out = hld_is_border_d1 ? 16'h0000 : get_rgb565(hold_piece_type);
            else rgb_out = 16'h0000;
        end 
        else if (px_d1 >= SCORE_X && px_d1 < SCORE_X + SCORE_W &&
                 py_d1 >= SCORE_Y && py_d1 < SCORE_Y + SCORE_H) begin
            if (draw_text) rgb_out = 16'hFFFF;
        end
    end
endmodule