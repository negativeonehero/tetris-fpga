module srs_rom (
    input  wire [2:0] piece_type,
    input  wire [1:0] current_rot,
    input  wire [1:0] next_rot,
    input  wire [2:0] test_index, // 0..4
    output reg  signed [3:0] offset_x,
    output reg  signed [3:0] offset_y
);

    wire is_i   = (piece_type == 3'd1);
    wire is_o   = (piece_type == 3'd4);
    wire dir_cw = (next_rot == (current_rot + 2'd1));

    reg [1:0] kick_case;
    reg [1:0] mag_a, mag_b;

    function signed [3:0] smag;
        input sign_pos;
        input [1:0] mag;
        begin
            case (mag)
                2'd0: smag =  4'sd0;
                2'd1: smag = sign_pos ?  4'sd1 : -4'sd1;
                2'd2: smag = sign_pos ?  4'sd2 : -4'sd2;
                default: smag = sign_pos ?  4'sd3 : -4'sd3;
            endcase
        end
    endfunction

    always @(*) begin
        offset_x  = 4'sd0;
        offset_y  = 4'sd0;
        kick_case = 2'd0;
        mag_a     = 2'd0;
        mag_b     = 2'd0;

        if (!is_o && (test_index != 3'd0) && (current_rot != next_rot)) begin
            if (!is_i) begin
                // JLSTZ
                case (current_rot)
                    2'd0: kick_case = dir_cw ? 2'd0 : 2'd2;
                    2'd1: kick_case = 2'd1;
                    2'd2: kick_case = dir_cw ? 2'd2 : 2'd0;
                    default: kick_case = 2'd3; // rot = 3
                endcase

                case (test_index)
                    3'd1: begin
                        offset_x = smag(kick_case[1] ^ kick_case[0], 2'd1);
                        offset_y = 4'sd0;
                    end
                    3'd2: begin
                        offset_x = smag(kick_case[1] ^ kick_case[0], 2'd1);
                        offset_y = smag(kick_case[0], 2'd1);
                    end
                    3'd3: begin
                        offset_x = 4'sd0;
                        offset_y = smag(~kick_case[0], 2'd2);
                    end
                    3'd4: begin
                        offset_x = smag(kick_case[1] ^ kick_case[0], 2'd1);
                        offset_y = smag(~kick_case[0], 2'd2);
                    end
                    default: begin
                        offset_x = 4'sd0;
                        offset_y = 4'sd0;
                    end
                endcase
            end else begin
                // I piece
                case (current_rot)
                    2'd0: kick_case = dir_cw ? 2'd0 : 2'd2;
                    2'd1: kick_case = dir_cw ? 2'd2 : 2'd1;
                    2'd2: kick_case = dir_cw ? 2'd1 : 2'd3;
                    default: kick_case = dir_cw ? 2'd3 : 2'd0; // rot = 3
                endcase

                mag_a = kick_case[1] ? 2'd1 : 2'd2;
                mag_b = kick_case[1] ? 2'd2 : 2'd1;

                case (test_index)
                    3'd1: begin
                        offset_x = smag( kick_case[0], mag_a);
                        offset_y = 4'sd0;
                    end
                    3'd2: begin
                        offset_x = smag(~kick_case[0], mag_b);
                        offset_y = 4'sd0;
                    end
                    3'd3: begin
                        offset_x = smag( kick_case[0], mag_a);
                        offset_y = smag(~(kick_case[1] ^ kick_case[0]), mag_b);
                    end
                    3'd4: begin
                        offset_x = smag(~kick_case[0], mag_b);
                        offset_y = smag(  kick_case[1] ^ kick_case[0],  mag_a);
                    end
                    default: begin
                        offset_x = 4'sd0;
                        offset_y = 4'sd0;
                    end
                endcase
            end
        end
    end
endmodule

module bag_generator (
    input  wire       clk_25MHz,
    input  wire       rst_n,
    input  wire       btn_start,
    input  wire       next_piece_req,
    output reg  [2:0] next_piece,
    output reg        piece_valid
);
    reg [7:0] entropy_counter;
    reg [7:0] lfsr;
    reg [7:0] drawn_mask;   // bit 0 unused, bits 1..7 used
    reg [2:0] pieces_drawn;
    reg       state;        // 0 = GENERATE, 1 = READY

    localparam GENERATE = 1'b0;
    localparam READY    = 1'b1;

    wire feedback = lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3];
    wire [7:0] lfsr_next = (lfsr == 8'd0) ? 8'hA5 : {lfsr[6:0], feedback};

    wire [2:0] candidate      = lfsr_next[2:0];
    wire       candidate_ok   = (candidate != 3'd0) && !drawn_mask[candidate];

    always @(posedge clk_25MHz or negedge rst_n) begin
        if (!rst_n) begin
            entropy_counter <= 8'h01;
            lfsr            <= 8'hA5;
            drawn_mask      <= 8'b0;
            pieces_drawn    <= 3'd0;
            next_piece      <= 3'd0;
            piece_valid     <= 1'b0;
            state           <= GENERATE;
        end else begin
            entropy_counter <= entropy_counter + 8'd1;

            if (btn_start) begin
                lfsr         <= (entropy_counter == 8'd0) ? 8'h5A : entropy_counter;
                drawn_mask   <= 8'b0;
                pieces_drawn <= 3'd0;
                next_piece   <= 3'd0;
                piece_valid  <= 1'b0;
                state        <= GENERATE;
            end else begin
                case (state)
                    GENERATE: begin
                        lfsr <= lfsr_next;
                        if (candidate_ok) begin
                            next_piece <= candidate;
                            piece_valid <= 1'b1;
                            state <= READY;

                            if (pieces_drawn == 3'd6) begin
                                drawn_mask   <= 8'b0;
                                pieces_drawn <= 3'd0;
                            end else begin
                                drawn_mask[candidate] <= 1'b1;
                                pieces_drawn <= pieces_drawn + 3'd1;
                            end
                        end
                    end

                    READY: begin
                        if (next_piece_req) begin
                            piece_valid <= 1'b0;
                            state <= GENERATE;
                        end
                    end
                endcase
            end
        end
    end
endmodule

// =========================================================================
// MAIN TETRIS ENGINE
// =========================================================================
module tetris_engine (
    input  wire        clk_25MHz,
    input  wire        rst_n,
    input  wire        tick_10khz,

    input  wire        btn_reset_game,
    input  wire        btn_start,
    input  wire [4:0]  start_level,

    input  wire        btn_left,
    input  wire        btn_right,
    input  wire        btn_rotate_cw,
    input  wire        btn_rotate_ccw,
    input  wire        btn_soft_drop,
    input  wire        btn_hard_drop,
    input  wire        btn_hold,

    input  wire [2:0]  next_piece_from_bag,
    input  wire        piece_valid,
    output reg         next_piece_req,

    output reg  [2:0]  hold_piece,
    output reg         hold_valid,

    output wire [15:0] current_piece_shape,
    output reg  [5:0]  ghost_y,

    output reg  signed [4:0] piece_x,
    output reg  [5:0]        piece_y,
    output reg  [2:0]        piece_type,
    output reg  [1:0]        piece_rot,

    output wire [399:0] matrix_occ,

    output reg  [4:0]  current_level,
    output reg  [31:0] score,
    output reg  [15:0] total_lines,

    output wire        game_over,
    output wire        game_ready,
    output wire        game_active
);

    // ------------------------------------------------------------
    // Board
    // ------------------------------------------------------------
    reg [9:0] board [0:39];

    genvar g;
    generate
        for (g = 0; g < 40; g = g + 1) begin : GEN_MATRIX_OCC
            assign matrix_occ[g*10 +: 10] = board[g];
        end
    endgenerate

    function cell_occ;
        input signed [5:0] x;
        input signed [6:0] y;
        begin
            if (x < 0 || x > 9 || y > 39)
                cell_occ = 1'b1;
            else if (y < 0)
                cell_occ = 1'b0;
            else
                cell_occ = board[y[5:0]][x[3:0]];
        end
    endfunction

    // ------------------------------------------------------------
    // Small LUT helpers
    // ------------------------------------------------------------
    function [15:0] shape_lut;
        input [2:0] p;
        input [1:0] r;
        begin
            case ({p,r})
                5'b001_00: shape_lut = 16'h0F00; // I
                5'b001_01: shape_lut = 16'h2222;
                5'b001_10: shape_lut = 16'h00F0;
                5'b001_11: shape_lut = 16'h4444;

                5'b010_00: shape_lut = 16'h8E00; // J
                5'b010_01: shape_lut = 16'h6440;
                5'b010_10: shape_lut = 16'h0E20;
                5'b010_11: shape_lut = 16'h44C0;

                5'b011_00: shape_lut = 16'h2E00; // L
                5'b011_01: shape_lut = 16'h4460;
                5'b011_10: shape_lut = 16'h0E80;
                5'b011_11: shape_lut = 16'hC440;

                5'b100_00,
                5'b100_01,
                5'b100_10,
                5'b100_11: shape_lut = 16'h6600; // O

                5'b101_00: shape_lut = 16'h6C00; // S
                5'b101_01: shape_lut = 16'h4620;
                5'b101_10: shape_lut = 16'h06C0;
                5'b101_11: shape_lut = 16'h8C40;

                5'b110_00: shape_lut = 16'h4E00; // T
                5'b110_01: shape_lut = 16'h4640;
                5'b110_10: shape_lut = 16'h0E40;
                5'b110_11: shape_lut = 16'h4C40;

                5'b111_00: shape_lut = 16'hC600; // Z
                5'b111_01: shape_lut = 16'h2640;
                5'b111_10: shape_lut = 16'h0C60;
                5'b111_11: shape_lut = 16'h4C80;

                default:   shape_lut = 16'h0000;
            endcase
        end
    endfunction

    function [13:0] gravity_lut;
        input [4:0] level;
        begin
            case (level)
                5'd1:  gravity_lut = 14'd10002;
                5'd2:  gravity_lut = 14'd7932;
                5'd3:  gravity_lut = 14'd6180;
                5'd4:  gravity_lut = 14'd4729;
                5'd5:  gravity_lut = 14'd3553;
                5'd6:  gravity_lut = 14'd2621;
                5'd7:  gravity_lut = 14'd1897;
                5'd8:  gravity_lut = 14'd1348;
                5'd9:  gravity_lut = 14'd939;
                5'd10: gravity_lut = 14'd642;
                5'd11: gravity_lut = 14'd430;
                5'd12: gravity_lut = 14'd282;
                5'd13: gravity_lut = 14'd182;
                5'd14: gravity_lut = 14'd114;
                5'd15: gravity_lut = 14'd71;
                default: gravity_lut = 14'd71;
            endcase
        end
    endfunction

    function [13:0] soft_gravity_lut;
        input [4:0] level;
        begin
            case (level)
                5'd1:  soft_gravity_lut = 14'd500;
                5'd2:  soft_gravity_lut = 14'd396;
                5'd3:  soft_gravity_lut = 14'd309;
                5'd4:  soft_gravity_lut = 14'd236;
                5'd5:  soft_gravity_lut = 14'd177;
                5'd6:  soft_gravity_lut = 14'd131;
                5'd7:  soft_gravity_lut = 14'd94;
                5'd8:  soft_gravity_lut = 14'd67;
                5'd9:  soft_gravity_lut = 14'd46;
                5'd10: soft_gravity_lut = 14'd32;
                5'd11: soft_gravity_lut = 14'd21;
                5'd12: soft_gravity_lut = 14'd14;
                5'd13: soft_gravity_lut = 14'd9;
                5'd14: soft_gravity_lut = 14'd5;
                5'd15: soft_gravity_lut = 14'd3;
                default: soft_gravity_lut = 14'd3;
            endcase
        end
    endfunction

    // ------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------
    localparam STATE_INIT       = 4'd0,
               STATE_READY      = 4'd1,
               STATE_GENERATE   = 4'd2,
               STATE_FALLING    = 4'd3,
               STATE_SRS        = 4'd4,
               STATE_CC         = 4'd5,
               STATE_LOCK_MINOS = 4'd6,
               STATE_ELIMINATE  = 4'd7,
               STATE_SHIFT_ROWS = 4'd8,
               STATE_GAME_OVER  = 4'd9;

    reg [3:0] current_state;

    assign game_over   = (current_state == STATE_GAME_OVER);
    assign game_ready  = (current_state == STATE_READY);
    assign game_active = (current_state != STATE_INIT) &&
                         (current_state != STATE_READY) &&
                         (current_state != STATE_GAME_OVER);

    // ------------------------------------------------------------
    // Collision-check operation mode
    // ------------------------------------------------------------
    localparam CCM_SPAWN = 3'd0,
               CCM_EVAL  = 3'd1,
               CCM_SRS   = 3'd2,
               CCM_HDROP = 3'd3,
               CCM_GHOST = 3'd4;

    reg [2:0] cc_mode;

    // ------------------------------------------------------------
    // Piece shape handling
    // ------------------------------------------------------------
    reg  [15:0] piece_shape;
    reg  [1:0]  target_rot;
    wire [15:0] next_rotation_shape;

    assign current_piece_shape = piece_shape;
    assign next_rotation_shape = shape_lut(piece_type, target_rot);

    reg  [2:0] srs_test_index;
    wire signed [3:0] srs_offset_x, srs_offset_y;

    srs_rom srs_inst (
        .piece_type(piece_type),
        .current_rot(piece_rot),
        .next_rot(target_rot),
        .test_index(srs_test_index),
        .offset_x(srs_offset_x),
        .offset_y(srs_offset_y)
    );

    // ------------------------------------------------------------
    // Sequential collision checker
    // ------------------------------------------------------------
    reg        cc_start;
    reg        cc_busy;
    reg        cc_done;
    reg        cc_collision;
    reg [3:0]  cc_bit_idx;

    reg signed [5:0] test_x;
    reg signed [6:0] test_y;
    reg [15:0]       test_shape;
    reg              check_step;      // 0=move/spawn, 1=floor check
    reg              is_gravity_move;

    wire [1:0] cc_r = cc_bit_idx[3:2];
    wire [1:0] cc_c = cc_bit_idx[1:0];

    wire signed [5:0] cc_x = test_x + $signed({4'd0, cc_c});
    wire signed [6:0] cc_y = test_y + $signed({5'd0, cc_r});

    wire cc_hit = test_shape[15 - cc_bit_idx] && cell_occ(cc_x, cc_y);

    always @(posedge clk_25MHz or negedge rst_n) begin
        if (!rst_n) begin
            cc_busy      <= 1'b0;
            cc_done      <= 1'b0;
            cc_collision <= 1'b0;
            cc_bit_idx   <= 4'd0;
        end else begin
            cc_done <= 1'b0;

            if (cc_start) begin
                cc_busy      <= 1'b1;
                cc_collision <= 1'b0;
                cc_bit_idx   <= 4'd0;
            end else if (cc_busy) begin
                if (cc_hit) begin
                    cc_busy      <= 1'b0;
                    cc_collision <= 1'b1;
                    cc_done      <= 1'b1;
                end else if (cc_bit_idx == 4'd15) begin
                    cc_busy      <= 1'b0;
                    cc_collision <= 1'b0;
                    cc_done      <= 1'b1;
                end else begin
                    cc_bit_idx <= cc_bit_idx + 4'd1;
                end
            end
        end
    end

    // ------------------------------------------------------------
    // Timers / gameplay regs
    // ------------------------------------------------------------
    reg [13:0] fall_timer;
    reg [12:0] lock_timer;
    reg [3:0]  lock_moves;
    reg [5:0]  lowest_reached_y;
    reg        can_hold;
    reg        is_touching_floor;

    reg [11:0] das_timer;
    reg        das_active;

    reg [13:0] gravity_r;
    reg [13:0] soft_gravity_r;

    localparam LOCK_DELAY_TICKS = 13'd5001;
    localparam DAS_DELAY        = 12'd3000;
    localparam ARR_SPEED        = 12'd500;

    // ------------------------------------------------------------
    // Ghost
    // ------------------------------------------------------------
    reg [6:0] ghost_scan_y;
    reg       ghost_dirty;

    // ------------------------------------------------------------
    // Scoring / T-spin / line clear
    // ------------------------------------------------------------
    wire signed [5:0] piece_x_s = piece_x;
    wire signed [6:0] piece_y_s = $signed({1'b0, piece_y});

    wire c_tl = cell_occ(piece_x_s,         piece_y_s);
    wire c_tr = cell_occ(piece_x_s + 6'sd2, piece_y_s);
    wire c_bl = cell_occ(piece_x_s,         piece_y_s + 7'sd2);
    wire c_br = cell_occ(piece_x_s + 6'sd2, piece_y_s + 7'sd2);

    wire [2:0] corner_count = c_tl + c_tr + c_bl + c_br;

    reg        last_move_was_spin;
    reg [2:0]  last_srs_point;
    reg        b2b_active;
    reg [15:0] next_level_threshold;

    wire is_t_spin = (piece_type == 3'd6) && last_move_was_spin && (corner_count >= 3);

    reg is_mini_t_spin;
    always @(*) begin
        is_mini_t_spin = 1'b0;
        if (is_t_spin && last_srs_point != 3'd4) begin
            case (piece_rot)
                2'd0: if (!(c_tl && c_tr)) is_mini_t_spin = 1'b1;
                2'd1: if (!(c_tr && c_br)) is_mini_t_spin = 1'b1;
                2'd2: if (!(c_bl && c_br)) is_mini_t_spin = 1'b1;
                2'd3: if (!(c_tl && c_bl)) is_mini_t_spin = 1'b1;
            endcase
        end
    end

    reg [2:0]  lines_cleared_comb;
    reg [10:0] base_score;

    always @(*) begin
        base_score = 11'd0;
        case (lines_cleared_comb)
            3'd0: if (is_t_spin) base_score = is_mini_t_spin ? 11'd100 : 11'd400;
            3'd1: if (is_t_spin) base_score = is_mini_t_spin ? 11'd200 : 11'd800; else base_score = 11'd100;
            3'd2: if (is_t_spin) base_score = 11'd1200; else base_score = 11'd300;
            3'd3: if (is_t_spin) base_score = 11'd1600; else base_score = 11'd500;
            3'd4: base_score = 11'd800;
            default: base_score = 11'd0;
        endcase
    end

    wire is_difficult = (lines_cleared_comb == 3'd4) || (is_t_spin && (lines_cleared_comb != 3'd0));
    wire [15:0] action_score    = base_score * current_level;
    wire [15:0] final_score_add = (b2b_active && is_difficult) ? (action_score + (action_score >> 1)) : action_score;

    reg [5:0] clear_r;
    reg [5:0] shift_r;
    reg [4:0] lock_idx;
    reg       pending_soft_drop_score;
    reg [5:0] harddrop_origin_y;

    wire current_row_full = &board[clear_r];
    wire [5:0] harddrop_land_y = (test_y <= 7'sd0) ? 6'd0 : (test_y - 7'sd1);

    integer rr;

    // ------------------------------------------------------------
    // Main FSM
    // ------------------------------------------------------------
    always @(posedge clk_25MHz or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= STATE_INIT;

            next_piece_req <= 1'b0;
            hold_piece     <= 3'd0;
            hold_valid     <= 1'b0;

            piece_x        <= 5'sd4;
            piece_y        <= 6'd19;
            piece_type     <= 3'd0;
            piece_rot      <= 2'd0;
            piece_shape    <= 16'h0000;
            ghost_y        <= 6'd63;

            current_level  <= 5'd1;
            score          <= 32'd0;
            total_lines    <= 16'd0;

            fall_timer       <= 14'd0;
            lock_timer       <= 13'd0;
            lock_moves       <= 4'd0;
            lowest_reached_y <= 6'd0;
            can_hold         <= 1'b1;
            is_touching_floor<= 1'b0;
            das_timer        <= 12'd0;
            das_active       <= 1'b0;

            gravity_r        <= gravity_lut(5'd1);
            soft_gravity_r   <= soft_gravity_lut(5'd1);

            target_rot       <= 2'd0;
            srs_test_index   <= 3'd0;
            cc_mode          <= CCM_SPAWN;

            last_move_was_spin <= 1'b0;
            last_srs_point     <= 3'd0;
            b2b_active         <= 1'b0;
            next_level_threshold <= 16'd10;

            clear_r          <= 6'd39;
            shift_r          <= 6'd0;
            lock_idx         <= 5'd0;
            lines_cleared_comb <= 3'd0;
            pending_soft_drop_score <= 1'b0;
            harddrop_origin_y <= 6'd0;

            ghost_scan_y <= 7'd0;
            ghost_dirty  <= 1'b0;

            test_x         <= 6'sd0;
            test_y         <= 7'sd0;
            test_shape     <= 16'd0;
            check_step     <= 1'b0;
            is_gravity_move<= 1'b0;
            cc_start       <= 1'b0;

            for (rr = 0; rr < 40; rr = rr + 1)
                board[rr] <= 10'b0;
        end else begin
            next_piece_req <= 1'b0;
            cc_start       <= 1'b0;

            // ----------------------------------------------------
            // Global game-reset button -> clear to READY via INIT
            // ----------------------------------------------------
            if (btn_reset_game) begin
                hold_piece     <= 3'd0;
                hold_valid     <= 1'b0;

                piece_x        <= 5'sd4;
                piece_y        <= 6'd19;
                piece_type     <= 3'd0;
                piece_rot      <= 2'd0;
                piece_shape    <= 16'h0000;
                ghost_y        <= 6'd63;

                current_level  <= start_level;
                score          <= 32'd0;
                total_lines    <= 16'd0;

                fall_timer       <= 14'd0;
                lock_timer       <= 13'd0;
                lock_moves       <= 4'd0;
                lowest_reached_y <= 6'd0;
                can_hold         <= 1'b1;
                is_touching_floor<= 1'b0;
                das_timer        <= 12'd0;
                das_active       <= 1'b0;

                gravity_r        <= gravity_lut(start_level);
                soft_gravity_r   <= soft_gravity_lut(start_level);

                target_rot       <= 2'd0;
                srs_test_index   <= 3'd0;
                cc_mode          <= CCM_SPAWN;

                last_move_was_spin <= 1'b0;
                last_srs_point     <= 3'd0;
                b2b_active         <= 1'b0;
                next_level_threshold <= 16'd10;

                clear_r          <= 6'd39;
                shift_r          <= 6'd0;
                lock_idx         <= 5'd0;
                lines_cleared_comb <= 3'd0;
                pending_soft_drop_score <= 1'b0;
                harddrop_origin_y <= 6'd0;

                ghost_scan_y <= 7'd0;
                ghost_dirty  <= 1'b0;

                test_x         <= 6'sd0;
                test_y         <= 7'sd0;
                test_shape     <= 16'd0;
                check_step     <= 1'b0;
                is_gravity_move<= 1'b0;

                current_state <= STATE_INIT;
            end else begin
                case (current_state)

                    // ------------------------------------------------
                    // Full-speed worker: generic collision-wait state
                    // ------------------------------------------------
                    STATE_CC: begin
                        if (cc_done) begin
                            case (cc_mode)

                                // ------------------------------------
                                // Spawn collision + initial floor check
                                // ------------------------------------
                                CCM_SPAWN: begin
                                    if (!check_step) begin
                                        if (cc_collision) begin
                                            ghost_y <= 6'd63;
                                            current_state <= STATE_GAME_OVER;
                                        end else begin
                                            test_y     <= test_y + 7'sd1;
                                            check_step <= 1'b1;
                                            cc_start   <= 1'b1;
                                            current_state <= STATE_CC;
                                        end
                                    end else begin
                                        last_move_was_spin      <= 1'b0;
                                        pending_soft_drop_score <= 1'b0;
                                        fall_timer              <= 14'd0;
                                        lock_timer              <= 13'd0;
                                        lock_moves              <= 4'd0;
                                        is_touching_floor       <= cc_collision;
                                        lowest_reached_y        <= piece_y;

                                        ghost_y      <= piece_y;
                                        ghost_scan_y <= piece_y_s + 7'd1;
                                        ghost_dirty  <= 1'b0;

                                        test_x       <= piece_x_s;
                                        test_y       <= piece_y_s + 7'd1;
                                        test_shape   <= piece_shape;
                                        cc_mode      <= CCM_GHOST;
                                        cc_start     <= 1'b1;
                                        current_state <= STATE_CC;
                                    end
                                end

                                // ------------------------------------
                                // Move / gravity evaluation
                                // ------------------------------------
                                CCM_EVAL: begin
                                    if (!check_step) begin
                                        if (!cc_collision) begin
                                            piece_x            <= test_x[4:0];
                                            last_move_was_spin <= 1'b0;
                                            ghost_dirty        <= 1'b1;
                                        end else begin
                                            ghost_dirty        <= 1'b0;
                                        end

                                        test_x     <= (!cc_collision) ? test_x : piece_x_s;
                                        test_y     <= piece_y_s + 7'sd1;
                                        test_shape <= piece_shape;
                                        check_step <= 1'b1;
                                        cc_start   <= 1'b1;
                                        current_state <= STATE_CC;
                                    end else begin
                                        is_touching_floor       <= cc_collision;
                                        pending_soft_drop_score <= 1'b0;

                                        if (is_gravity_move) begin
                                            if (!cc_collision) begin
                                                piece_y <= test_y[5:0];

                                                if (pending_soft_drop_score)
                                                    score <= score + 32'd1;

                                                if (test_y[5:0] > lowest_reached_y) begin
                                                    lowest_reached_y <= test_y[5:0];
                                                    lock_moves <= 4'd0;
                                                end

                                                ghost_y      <= test_y[5:0];
                                                ghost_scan_y <= test_y + 7'd1;
                                                ghost_dirty  <= 1'b0;

                                                test_x       <= piece_x_s;
                                                test_y       <= test_y + 7'd1;
                                                test_shape   <= piece_shape;
                                                cc_mode      <= CCM_GHOST;
                                                cc_start     <= 1'b1;
                                                lock_timer   <= 13'd0;
                                                current_state <= STATE_CC;
                                            end else begin
                                                ghost_dirty  <= 1'b0;
                                                current_state <= STATE_FALLING;
                                            end
                                        end else begin
                                            if (cc_collision && lock_moves < 4'd15) begin
                                                lock_timer <= 13'd0;
                                                lock_moves <= lock_moves + 4'd1;
                                            end

                                            if (ghost_dirty) begin
                                                ghost_y      <= piece_y;
                                                ghost_scan_y <= piece_y_s + 7'd1;
                                                ghost_dirty  <= 1'b0;

                                                test_x       <= (!cc_collision) ? test_x : piece_x_s;
                                                test_y       <= piece_y_s + 7'd1;
                                                test_shape   <= piece_shape;
                                                cc_mode      <= CCM_GHOST;
                                                cc_start     <= 1'b1;
                                                current_state <= STATE_CC;
                                            end else begin
                                                current_state <= STATE_FALLING;
                                            end
                                        end
                                    end
                                end

                                // ------------------------------------
                                // Rotation check result
                                // ------------------------------------
                                CCM_SRS: begin
                                    if (!cc_collision) begin
                                        piece_x <= test_x[4:0];
                                        piece_y <= test_y[5:0];
                                        piece_rot <= target_rot;
                                        piece_shape <= next_rotation_shape;
                                        last_srs_point <= srs_test_index;
                                        last_move_was_spin <= 1'b1;
                                        is_gravity_move <= 1'b0;
                                        pending_soft_drop_score <= 1'b0;
                                        ghost_dirty <= 1'b1;

                                        test_y     <= test_y + 7'd1;
                                        test_shape <= next_rotation_shape;
                                        check_step <= 1'b1;
                                        cc_mode    <= CCM_EVAL;
                                        cc_start   <= 1'b1;
                                        current_state <= STATE_CC;
                                    end else begin
                                        if (srs_test_index < 3'd4) begin
                                            srs_test_index <= srs_test_index + 3'd1;
                                            current_state  <= STATE_SRS;
                                        end else begin
                                            current_state  <= STATE_FALLING;
                                        end
                                    end
                                end

                                // ------------------------------------
                                // Hard-drop scan
                                // ------------------------------------
                                CCM_HDROP: begin
                                    if (cc_collision) begin
                                        piece_y <= harddrop_land_y;
                                        ghost_y <= harddrop_land_y;
                                        score   <= score + ((harddrop_land_y - harddrop_origin_y) << 1);
                                        lock_timer <= LOCK_DELAY_TICKS;
                                        is_touching_floor <= 1'b1;
                                        last_move_was_spin <= 1'b0;
                                        pending_soft_drop_score <= 1'b0;
                                        ghost_dirty <= 1'b0;
                                        current_state <= STATE_FALLING;
                                    end else begin
                                        test_y   <= test_y + 7'd1;
                                        cc_start <= 1'b1;
                                        current_state <= STATE_CC;
                                    end
                                end

                                // ------------------------------------
                                // Ghost scan
                                // ------------------------------------
                                CCM_GHOST: begin
                                    if (cc_collision) begin
                                        ghost_y <= ghost_scan_y[5:0] - 6'd1;
                                        ghost_dirty <= 1'b0;
                                        current_state <= STATE_FALLING;
                                    end else begin
                                        ghost_scan_y <= ghost_scan_y + 7'd1;
                                        test_y       <= ghost_scan_y + 7'd1;
                                        cc_start     <= 1'b1;
                                        current_state <= STATE_CC;
                                    end
                                end

                                default: begin
                                    current_state <= STATE_GAME_OVER;
                                end
                            endcase
                        end
                    end

                    // ------------------------------------------------
                    // Full-speed worker: SRS test launch
                    // ------------------------------------------------
                    STATE_SRS: begin
                        test_x     <= piece_x_s + srs_offset_x;
                        test_y     <= piece_y_s + srs_offset_y;
                        test_shape <= next_rotation_shape;
                        cc_mode    <= CCM_SRS;
                        cc_start   <= 1'b1;
                        current_state <= STATE_CC;
                    end

                    // ------------------------------------------------
                    // Full-speed worker: lock current piece into board
                    // ------------------------------------------------
                    STATE_LOCK_MINOS: begin
                        if (lock_idx > 5'd15) begin
                            lines_cleared_comb <= 3'd0;
                            clear_r            <= 6'd39;
                            current_state      <= STATE_ELIMINATE;
                        end else begin
                            if (piece_shape[15 - lock_idx]) begin
                                board[piece_y + lock_idx[3:2]][piece_x + lock_idx[1:0]] <= 1'b1;
                            end
                            lock_idx <= lock_idx + 5'd1;
                        end
                    end

                    // ------------------------------------------------
                    // Full-speed worker: scan for full rows
                    // ------------------------------------------------
                    STATE_ELIMINATE: begin
                        if (current_row_full) begin
                            lines_cleared_comb <= lines_cleared_comb + 3'd1;
                            shift_r            <= clear_r;
                            current_state      <= STATE_SHIFT_ROWS;
                        end else begin
                            if (clear_r == 6'd0) begin
                                can_hold <= 1'b1;
                                pending_soft_drop_score <= 1'b0;
                                ghost_y <= 6'd63;
                                ghost_dirty <= 1'b0;

                                score       <= score + final_score_add;
                                total_lines <= total_lines + lines_cleared_comb;

                                if (lines_cleared_comb > 0)
                                    b2b_active <= is_difficult;

                                if ((total_lines + lines_cleared_comb) >= next_level_threshold) begin
                                    current_level <= current_level + 5'd1;
                                    next_level_threshold <= next_level_threshold + 16'd10;
                                    gravity_r      <= gravity_lut(current_level + 5'd1);
                                    soft_gravity_r <= soft_gravity_lut(current_level + 5'd1);
                                end

                                current_state <= STATE_GENERATE;
                            end else begin
                                clear_r <= clear_r - 6'd1;
                            end
                        end
                    end

                    // ------------------------------------------------
                    // Full-speed worker: shift rows down
                    // ------------------------------------------------
                    STATE_SHIFT_ROWS: begin
                        if (shift_r > 6'd0) begin
                            board[shift_r] <= board[shift_r - 6'd1];
                            shift_r <= shift_r - 6'd1;
                        end else begin
                            board[0] <= 10'b0;
                            current_state <= STATE_ELIMINATE;
                        end
                    end

                    // ------------------------------------------------
                    // Tick-gated gameplay / setup states
                    // ------------------------------------------------
                    default: begin
                        if (tick_10khz) begin
                            case (current_state)

                                STATE_INIT: begin
                                    ghost_y <= 6'd63;
                                    ghost_dirty <= 1'b0;

                                    if (clear_r > 6'd0) begin
                                        board[clear_r] <= 10'b0;
                                        clear_r <= clear_r - 6'd1;
                                    end else begin
                                        board[0] <= 10'b0;

                                        score <= 32'd0;
                                        total_lines <= 16'd0;
                                        current_level <= start_level;
                                        next_level_threshold <= 16'd10;
                                        gravity_r      <= gravity_lut(start_level);
                                        soft_gravity_r <= soft_gravity_lut(start_level);

                                        hold_valid <= 1'b0;
                                        hold_piece <= 3'd0;
                                        piece_type <= 3'd0;
                                        piece_rot  <= 2'd0;
                                        piece_shape<= 16'h0000;
                                        piece_x    <= 5'sd4;
                                        piece_y    <= 6'd19;

                                        can_hold <= 1'b1;
                                        b2b_active <= 1'b0;
                                        current_state <= STATE_READY;
                                    end
                                end

                                STATE_READY: begin
                                    ghost_y <= 6'd63;
                                    ghost_dirty <= 1'b0;

                                    piece_type  <= 3'd0;
                                    piece_rot   <= 2'd0;
                                    piece_shape <= 16'h0000;
                                    piece_x     <= 5'sd4;
                                    piece_y     <= 6'd19;

                                    current_level  <= start_level;
                                    gravity_r      <= gravity_lut(start_level);
                                    soft_gravity_r <= soft_gravity_lut(start_level);
                                    next_level_threshold <= 16'd10;

                                    fall_timer       <= 14'd0;
                                    lock_timer       <= 13'd0;
                                    lock_moves       <= 4'd0;
                                    lowest_reached_y <= 6'd0;
                                    can_hold         <= 1'b1;
                                    is_touching_floor<= 1'b0;
                                    das_timer        <= 12'd0;
                                    das_active       <= 1'b0;
                                    pending_soft_drop_score <= 1'b0;
                                    last_move_was_spin <= 1'b0;
                                    last_srs_point     <= 3'd0;

                                    if (btn_start) begin
                                        current_state <= STATE_GENERATE;
                                    end
                                end

                                STATE_GENERATE: begin
                                    ghost_y <= 6'd63;
                                    ghost_dirty <= 1'b0;

                                    if (piece_valid) begin
                                        piece_type  <= next_piece_from_bag;
                                        piece_rot   <= 2'd0;
                                        piece_shape <= shape_lut(next_piece_from_bag, 2'd0);
                                        piece_x     <= 5'sd4;
                                        piece_y     <= 6'd19;

                                        pending_soft_drop_score <= 1'b0;
                                        next_piece_req <= 1'b1;

                                        test_x     <= 6'sd4;
                                        test_y     <= 7'sd19;
                                        test_shape <= shape_lut(next_piece_from_bag, 2'd0);
                                        check_step <= 1'b0;
                                        cc_mode    <= CCM_SPAWN;
                                        cc_start   <= 1'b1;
                                        current_state <= STATE_CC;
                                    end
                                end

                                STATE_FALLING: begin
                                    current_state <= STATE_FALLING;
                                    fall_timer <= fall_timer + 14'd1;

                                    if (btn_hard_drop) begin
                                        pending_soft_drop_score <= 1'b0;
                                        is_gravity_move <= 1'b0;
                                        harddrop_origin_y <= piece_y;
                                        ghost_dirty <= 1'b0;

                                        test_x     <= piece_x_s;
                                        test_y     <= piece_y_s + 7'sd1;
                                        test_shape <= piece_shape;
                                        cc_mode    <= CCM_HDROP;
                                        cc_start   <= 1'b1;
                                        current_state <= STATE_CC;
                                    end
                                    else if (btn_hold && can_hold) begin
                                        pending_soft_drop_score <= 1'b0;
                                        is_gravity_move <= 1'b0;
                                        can_hold <= 1'b0;
                                        ghost_y <= 6'd63;
                                        ghost_dirty <= 1'b0;

                                        if (hold_valid) begin
                                            piece_type  <= hold_piece;
                                            hold_piece  <= piece_type;
                                            piece_rot   <= 2'd0;
                                            piece_shape <= shape_lut(hold_piece, 2'd0);
                                            piece_x     <= 5'sd4;
                                            piece_y     <= 6'd19;

                                            test_x     <= 6'sd4;
                                            test_y     <= 7'sd19;
                                            test_shape <= shape_lut(hold_piece, 2'd0);
                                            check_step <= 1'b0;
                                            cc_mode    <= CCM_SPAWN;
                                            cc_start   <= 1'b1;
                                            current_state <= STATE_CC;
                                        end else begin
                                            hold_piece <= piece_type;
                                            hold_valid <= 1'b1;
                                            current_state <= STATE_GENERATE;
                                        end
                                    end
                                    else if (btn_rotate_cw || btn_rotate_ccw) begin
                                        pending_soft_drop_score <= 1'b0;
                                        is_gravity_move <= 1'b0;
                                        target_rot <= btn_rotate_cw ? (piece_rot + 2'd1) : (piece_rot - 2'd1);
                                        srs_test_index <= 3'd0;
                                        current_state <= STATE_SRS;
                                    end
                                    else if (btn_left && (!das_active || das_timer >= (das_active ? ARR_SPEED : DAS_DELAY))) begin
                                        pending_soft_drop_score <= 1'b0;
                                        test_x     <= piece_x_s - 6'sd1;
                                        test_y     <= piece_y_s;
                                        test_shape <= piece_shape;
                                        check_step <= 1'b0;
                                        is_gravity_move <= 1'b0;
                                        cc_mode    <= CCM_EVAL;
                                        cc_start   <= 1'b1;
                                        current_state <= STATE_CC;
                                        das_timer  <= 12'd0;
                                        das_active <= 1'b1;
                                    end
                                    else if (btn_right && (!das_active || das_timer >= (das_active ? ARR_SPEED : DAS_DELAY))) begin
                                        pending_soft_drop_score <= 1'b0;
                                        test_x     <= piece_x_s + 6'sd1;
                                        test_y     <= piece_y_s;
                                        test_shape <= piece_shape;
                                        check_step <= 1'b0;
                                        is_gravity_move <= 1'b0;
                                        cc_mode    <= CCM_EVAL;
                                        cc_start   <= 1'b1;
                                        current_state <= STATE_CC;
                                        das_timer  <= 12'd0;
                                        das_active <= 1'b1;
                                    end
                                    else begin
                                        pending_soft_drop_score <= 1'b0;

                                        if (btn_left || btn_right)
                                            das_timer <= das_timer + 12'd1;
                                        else
                                            das_active <= 1'b0;

                                        if (btn_soft_drop && fall_timer >= soft_gravity_r) begin
                                            fall_timer <= 14'd0;
                                            pending_soft_drop_score <= 1'b1;
                                            test_x     <= piece_x_s;
                                            test_y     <= piece_y_s + 7'sd1;
                                            test_shape <= piece_shape;
                                            check_step <= 1'b1;
                                            is_gravity_move <= 1'b1;
                                            cc_mode    <= CCM_EVAL;
                                            cc_start   <= 1'b1;
                                            current_state <= STATE_CC;
                                        end
                                        else if (!btn_soft_drop && fall_timer >= gravity_r) begin
                                            fall_timer <= 14'd0;
                                            pending_soft_drop_score <= 1'b0;
                                            test_x     <= piece_x_s;
                                            test_y     <= piece_y_s + 7'sd1;
                                            test_shape <= piece_shape;
                                            check_step <= 1'b1;
                                            is_gravity_move <= 1'b1;
                                            cc_mode    <= CCM_EVAL;
                                            cc_start   <= 1'b1;
                                            current_state <= STATE_CC;
                                        end
                                        else if (is_touching_floor) begin
                                            if (lock_timer >= LOCK_DELAY_TICKS || lock_moves >= 4'd15) begin
                                                if (piece_y < 6'd21) begin
                                                    ghost_y <= 6'd63;
                                                    current_state <= STATE_GAME_OVER;
                                                end else begin
                                                    lock_idx <= 5'd0;
                                                    current_state <= STATE_LOCK_MINOS;
                                                end
                                            end else begin
                                                lock_timer <= lock_timer + 13'd1;
                                            end
                                        end
                                    end
                                end

                                STATE_GAME_OVER: begin
                                    ghost_y <= 6'd63;
                                    ghost_dirty <= 1'b0;
                                    current_state <= STATE_GAME_OVER;
                                end

                                default: begin
                                    current_state <= STATE_GAME_OVER;
                                end
                            endcase
                        end
                    end
                endcase
            end
        end
    end
endmodule