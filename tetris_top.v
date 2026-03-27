module tetris_top (
    input  wire       CLOCK_50,
    input  wire [3:0] KEY,
    input  wire [9:0] SW,

    output wire [4:0] VGA_R,
    output wire [5:0] VGA_G,
    output wire [4:0] VGA_B,
    output wire       VGA_HS,
    output wire       VGA_VS,
    output wire       BUZZER
);

    // ============================================================
    // Clocks / reset
    // ============================================================
    wire clk_25MHz;
    wire locked;
    wire rst_n = locked;

    master_pll u_pll (
        .inclk0(CLOCK_50),
        .c0(clk_25MHz),
        .locked(locked)
    );

    // ============================================================
    // 10 kHz tick
    // ============================================================
    reg [11:0] tick_counter_10khz;
    reg        tick_10khz;

    always @(posedge clk_25MHz or negedge rst_n) begin
        if (!rst_n) begin
            tick_counter_10khz <= 12'd0;
            tick_10khz         <= 1'b0;
        end else begin
            if (tick_counter_10khz >= 12'd2499) begin
                tick_counter_10khz <= 12'd0;
                tick_10khz         <= 1'b1;
            end else begin
                tick_counter_10khz <= tick_counter_10khz + 12'd1;
                tick_10khz         <= 1'b0;
            end
        end
    end

    // ============================================================
    // Engine/game state wires
    // ============================================================
    wire game_over;
    wire game_ready;
    wire game_active;

    // ============================================================
    // Key decode
    // Active-low board keys -> active-high internal
    // keys = {KEY3, KEY2, KEY1, KEY0}
    // ============================================================
    wire k0 = ~KEY[0];
    wire k1 = ~KEY[1];
    wire k2 = ~KEY[2];
    wire k3 = ~KEY[3];
    wire [3:0] keys = {k3, k2, k1, k0};

    wire btn_rotate_ccw = 1'b0;

    // Raw decoded actions
    reg raw_start;
    reg raw_level_down;
    reg raw_level_up;

    reg raw_left;
    reg raw_right;
    reg raw_rotate_cw;
    reg raw_soft_drop;
    reg raw_hold;
    reg raw_hard_drop;
    reg raw_reset_game;

    // ------------------------------------------------------------
    // READY mode:
    //   KEY0             -> start
    //   KEY1             -> level down
    //   KEY2             -> level up
    //
    // Non-READY mode:
    //   KEY0             -> soft drop
    //   KEY1             -> left
    //   KEY2             -> right
    //   KEY3             -> rotate cw
    //   KEY1+KEY2        -> hold
    //   KEY0+KEY3        -> hard drop
    //   KEY1+KEY2+KEY3   -> reset game
    //
    // Exact combo matching avoids overlaps.
    // ------------------------------------------------------------
    always @(*) begin
        raw_start      = 1'b0;
        raw_level_down = 1'b0;
        raw_level_up   = 1'b0;

        raw_left       = 1'b0;
        raw_right      = 1'b0;
        raw_rotate_cw  = 1'b0;
        raw_soft_drop  = 1'b0;
        raw_hold       = 1'b0;
        raw_hard_drop  = 1'b0;
        raw_reset_game = 1'b0;

        if (game_ready) begin
            case (keys)
                4'b0001: raw_start      = 1'b1; // KEY0
                4'b0010: raw_level_down = 1'b1; // KEY1
                4'b0100: raw_level_up   = 1'b1; // KEY2
                default: ;
            endcase
        end else begin
            case (keys)
                4'b0001: raw_soft_drop  = 1'b1; // KEY0
                4'b0010: raw_left       = 1'b1; // KEY1
                4'b0100: raw_right      = 1'b1; // KEY2
                4'b1000: raw_rotate_cw  = 1'b1; // KEY3
                4'b0110: raw_hold       = 1'b1; // KEY1 + KEY2
                4'b1001: raw_hard_drop  = 1'b1; // KEY0 + KEY3
                4'b1110: raw_reset_game = 1'b1; // KEY1 + KEY2 + KEY3
                default: ;
            endcase
        end
    end

    // ============================================================
    // Input shaping / edge detection
    // ============================================================
    reg start_prev, level_down_prev, level_up_prev;
    reg rotate_prev, hard_drop_prev, hold_prev, reset_prev;

    reg btn_start_game;
    reg btn_level_down;
    reg btn_level_up;

    reg btn_left;
    reg btn_right;
    reg btn_rotate_cw;
    reg btn_soft_drop;
    reg btn_hold;
    reg btn_hard_drop;
    reg btn_reset_game;

    always @(posedge clk_25MHz or negedge rst_n) begin
        if (!rst_n) begin
            start_prev      <= 1'b0;
            level_down_prev <= 1'b0;
            level_up_prev   <= 1'b0;
            rotate_prev     <= 1'b0;
            hard_drop_prev  <= 1'b0;
            hold_prev       <= 1'b0;
            reset_prev      <= 1'b0;

            btn_start_game  <= 1'b0;
            btn_level_down  <= 1'b0;
            btn_level_up    <= 1'b0;

            btn_left        <= 1'b0;
            btn_right       <= 1'b0;
            btn_rotate_cw   <= 1'b0;
            btn_soft_drop   <= 1'b0;
            btn_hold        <= 1'b0;
            btn_hard_drop   <= 1'b0;
            btn_reset_game  <= 1'b0;
        end else if (tick_10khz) begin
            // READY-mode pulses
            btn_start_game <= raw_start      & ~start_prev;
            btn_level_down <= raw_level_down & ~level_down_prev;
            btn_level_up   <= raw_level_up   & ~level_up_prev;

            // Gameplay held / pulse inputs
            btn_left      <= game_active ? raw_left      : 1'b0;
            btn_right     <= game_active ? raw_right     : 1'b0;
            btn_soft_drop <= game_active ? raw_soft_drop : 1'b0;

            btn_rotate_cw <= game_active ? (raw_rotate_cw & ~rotate_prev)   : 1'b0;
            btn_hard_drop <= game_active ? (raw_hard_drop & ~hard_drop_prev) : 1'b0;
            btn_hold      <= game_active ? (raw_hold & ~hold_prev)           : 1'b0;

            // Reset combo allowed whenever not READY
            btn_reset_game <= raw_reset_game & ~reset_prev;

            // Previous-state tracking
            start_prev      <= raw_start;
            level_down_prev <= raw_level_down;
            level_up_prev   <= raw_level_up;
            rotate_prev     <= raw_rotate_cw;
            hard_drop_prev  <= raw_hard_drop;
            hold_prev       <= raw_hold;
            reset_prev      <= raw_reset_game;
        end
    end

    // ============================================================
    // Start-level selection
    // Clamp to 1..15 for your gravity LUT
    // ============================================================
    reg [4:0] selected_start_level;

    always @(posedge clk_25MHz or negedge rst_n) begin
        if (!rst_n) begin
            selected_start_level <= 5'd1;
        end else if (tick_10khz) begin
            if (btn_level_down && selected_start_level > 5'd1)
                selected_start_level <= selected_start_level - 5'd1;
            else if (btn_level_up && selected_start_level < 5'd15)
                selected_start_level <= selected_start_level + 5'd1;
        end
    end

    // ============================================================
    // Bag / engine / gameplay signals
    // ============================================================
    wire [2:0] next_piece_from_bag;
    wire       piece_valid;
    wire       next_piece_req;

    wire signed [4:0] piece_x;
    wire [5:0]        piece_y;
    wire [2:0]        piece_type;
    wire [1:0]        piece_rot;
    wire [15:0]       current_piece_shape;
    wire [5:0]        ghost_y;

    wire [2:0]        hold_piece_type;
    wire              hold_valid;

    wire [399:0] matrix_occ;
    wire [4:0]   current_level;
    wire [31:0]  score;
    wire [15:0]  total_lines;

    wire [15:0] next_piece_shape;
    wire [15:0] hold_piece_shape;

    bag_generator u_bag (
        .clk_25MHz    (clk_25MHz),
        .rst_n        (rst_n),
        .btn_start    (btn_start_game),
        .next_piece_req(next_piece_req),
        .next_piece   (next_piece_from_bag),
        .piece_valid  (piece_valid)
    );

    function [15:0] preview_shape_lut;
        input [2:0] piece_type;
        begin
            case (piece_type)
                3'd1: preview_shape_lut = 16'h0F00; // I
                3'd2: preview_shape_lut = 16'h8E00; // J
                3'd3: preview_shape_lut = 16'h2E00; // L
                3'd4: preview_shape_lut = 16'h6600; // O
                3'd5: preview_shape_lut = 16'h6C00; // S
                3'd6: preview_shape_lut = 16'h4E00; // T
                3'd7: preview_shape_lut = 16'hC600; // Z
                default: preview_shape_lut = 16'h0000;
            endcase
        end
    endfunction

    assign next_piece_shape = preview_shape_lut(next_piece_from_bag);
    assign hold_piece_shape = preview_shape_lut(hold_piece_type);

    tetris_engine u_engine (
        .clk_25MHz(clk_25MHz),
        .rst_n(rst_n),
        .tick_10khz(tick_10khz),

        .btn_reset_game(btn_reset_game),
        .btn_start(btn_start_game),
        .start_level(selected_start_level),

        .btn_left(btn_left),
        .btn_right(btn_right),
        .btn_rotate_cw(btn_rotate_cw),
        .btn_rotate_ccw(btn_rotate_ccw),
        .btn_soft_drop(btn_soft_drop),
        .btn_hard_drop(btn_hard_drop),
        .btn_hold(btn_hold),

        .next_piece_from_bag(next_piece_from_bag),
        .piece_valid(piece_valid),
        .next_piece_req(next_piece_req),

        .hold_piece(hold_piece_type),
        .hold_valid(hold_valid),

        .current_piece_shape(current_piece_shape),
        .ghost_y(ghost_y),

        .piece_x(piece_x),
        .piece_y(piece_y),
        .piece_type(piece_type),
        .piece_rot(piece_rot),

        .matrix_occ(matrix_occ),
        .current_level(current_level),
        .score(score),
        .total_lines(total_lines),

        .game_over(game_over),
        .game_ready(game_ready),
        .game_active(game_active)
    );

    // ============================================================
    // Render blanking during reset clear
    // ============================================================
    reg render_blank;

    always @(posedge clk_25MHz or negedge rst_n) begin
        if (!rst_n)
            render_blank <= 1'b1;
        else if (btn_reset_game)
            render_blank <= 1'b1;
        else if (game_ready)
            render_blank <= 1'b0;
    end

    wire [399:0] render_matrix_occ =
        render_blank ? 400'd0 : matrix_occ;

    wire signed [4:0] render_piece_x =
        render_blank ? 5'sd0 : piece_x;

    wire [5:0] render_piece_y =
        render_blank ? 6'd0 : piece_y;

    wire [2:0] render_piece_type =
        render_blank ? 3'd0 : piece_type;

    wire [15:0] render_piece_shape =
        render_blank ? 16'h0000 : current_piece_shape;

    wire [5:0] render_ghost_y =
        render_blank ? 6'd63 : ghost_y;

    // Hide next/hold previews in READY
    wire [2:0] render_next_piece_type =
        game_ready ? 3'd0 : next_piece_from_bag;

    wire [15:0] render_next_piece_shape =
        game_ready ? 16'h0000 : next_piece_shape;

    wire [2:0] render_hold_piece_type =
        game_ready ? 3'd0 : hold_piece_type;

    wire [15:0] render_hold_piece_shape =
        game_ready ? 16'h0000 : hold_piece_shape;

    wire render_hold_valid =
        game_ready ? 1'b0 : hold_valid;

    // ============================================================
    // VGA
    // ============================================================
    wire video_on;
    wire [9:0] pixel_x;
    wire [9:0] pixel_y;

    vga_sync u_vga (
        .clk_25MHz(clk_25MHz),
        .rst_n(rst_n),
        .hsync(VGA_HS),
        .vsync(VGA_VS),
        .video_on(video_on),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y)
    );

    wire [15:0] rgb_out;
    tetris_renderer u_renderer (
        .clk_25MHz(clk_25MHz),
        .rst_n(rst_n),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),

        .matrix_occ(render_matrix_occ),
        .piece_x(render_piece_x),
        .piece_y(render_piece_y),
        .piece_type(render_piece_type),
        .piece_shape(render_piece_shape),
        .ghost_y(render_ghost_y),

        .score(score),
        .total_lines(total_lines),
        .current_level(current_level),

        .next_piece_type(render_next_piece_type),
        .next_piece_shape(render_next_piece_shape),
        .hold_piece_type(render_hold_piece_type),
        .hold_piece_shape(render_hold_piece_shape),
        .hold_valid(render_hold_valid),

        .rgb_out(rgb_out)
    );

    wire [15:0] final_rgb = video_on ? rgb_out : 16'h0000;

    assign VGA_R = final_rgb[15:11];
    assign VGA_G = final_rgb[10:5];
    assign VGA_B = final_rgb[4:0];

    // ============================================================
    // Audio
    // ============================================================
    wire buzzer_raw;

    tetris_audio #(
        .ROM_DEPTH(2048),
		  .VOLUME(8'd191)
    ) u_audio (
        .clk_25MHz  (clk_25MHz),
        .rst_n      (rst_n),
        .play_enable(game_active),
        .restart    (btn_start_game),
        .buzzer_out (buzzer_raw)
    );

    // If your buzzer is wired active-low, change to ~buzzer_raw
    assign BUZZER = ~buzzer_raw;

endmodule