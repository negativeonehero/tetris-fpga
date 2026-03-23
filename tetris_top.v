module tetris_top (
    input  wire       CLOCK_50,
    input  wire [5:0] KEY,
    input  wire [9:0] SW,

    output wire [4:0] VGA_R,
    output wire [5:0] VGA_G,
    output wire [4:0] VGA_B,
    output wire       VGA_HS,
    output wire       VGA_VS
);

    wire clk_25MHz;
    wire locked;
    wire rst_n = locked;

    master_pll u_pll (
        .inclk0(CLOCK_50),
        .c0(clk_25MHz),
        .locked(locked)
    );

    reg [11:0] tick_counter_10khz;
    reg        tick_10khz;

    always @(posedge clk_25MHz or negedge rst_n) begin
        if (!rst_n) begin
            tick_counter_10khz <= 12'd0;
            tick_10khz         <= 1'b0;
        end else begin
            if (tick_counter_10khz >= 12'd2511) begin
                tick_counter_10khz <= 12'd0;
                tick_10khz         <= 1'b1;
            end else begin
                tick_counter_10khz <= tick_counter_10khz + 12'd1;
                tick_10khz         <= 1'b0;
            end
        end
    end

    wire btn_rotate_ccw = 1'b0;

    wire k0 = ~KEY[0];
    wire k1 = ~KEY[1];
    wire k2 = ~KEY[2];
    wire k3 = ~KEY[3];
    wire [3:0] keys = {k3, k2, k1, k0};

    reg raw_left, raw_right, raw_rotate_cw, raw_soft_drop;
    reg raw_hold, raw_hard_drop, raw_start;

    always @(*) begin
        raw_left      = 1'b0;
        raw_right     = 1'b0;
        raw_rotate_cw = 1'b0;
        raw_soft_drop = 1'b0;
        raw_hold      = 1'b0;
        raw_hard_drop = 1'b0;
        raw_start     = 1'b0;

        case (keys)
            4'b0010: raw_left      = 1'b1;
            4'b0100: raw_right     = 1'b1;
            4'b1000: raw_rotate_cw = 1'b1;
            4'b0001: raw_soft_drop = 1'b1;
            4'b0011: raw_hold      = 1'b1;
            4'b1001: raw_hard_drop = 1'b1;
            4'b1110: raw_start     = 1'b1;
            default: ;
        endcase
    end

    reg start_prev, rotate_prev, hard_drop_prev, hold_prev;
    reg btn_start, btn_rotate_cw, btn_hard_drop, btn_hold;
    reg btn_left, btn_right, btn_soft_drop;

    always @(posedge clk_25MHz or negedge rst_n) begin
        if (!rst_n) begin
            start_prev      <= 1'b0;
            rotate_prev     <= 1'b0;
            hard_drop_prev  <= 1'b0;
            hold_prev       <= 1'b0;

            btn_start       <= 1'b0;
            btn_rotate_cw   <= 1'b0;
            btn_hard_drop   <= 1'b0;
            btn_hold        <= 1'b0;
            btn_left        <= 1'b0;
            btn_right       <= 1'b0;
            btn_soft_drop   <= 1'b0;
        end else if (tick_10khz) begin
            btn_left      <= raw_left;
            btn_right     <= raw_right;
            btn_soft_drop <= raw_soft_drop;

            btn_start      <= raw_start     & ~start_prev;
            btn_rotate_cw  <= raw_rotate_cw & ~rotate_prev;
            btn_hard_drop  <= raw_hard_drop & ~hard_drop_prev;
            btn_hold       <= raw_hold      & ~hold_prev;

            start_prev     <= raw_start;
            rotate_prev    <= raw_rotate_cw;
            hard_drop_prev <= raw_hard_drop;
            hold_prev      <= raw_hold;
        end
    end

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
    wire         game_over;

    wire [15:0] next_piece_shape;
    wire [15:0] hold_piece_shape;

    bag_generator u_bag (
        .clk_25MHz(clk_25MHz),
        .rst_n(rst_n),
        .btn_start(btn_start),
        .next_piece_req(next_piece_req),
        .next_piece(next_piece_from_bag),
        .piece_valid(piece_valid)
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

        .btn_start(btn_start),
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
        .game_over(game_over)
    );

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

        .matrix_occ(matrix_occ),
        .piece_x(piece_x),
        .piece_y(piece_y),
        .piece_type(piece_type),
        .piece_shape(current_piece_shape),
        .ghost_y(ghost_y),

        .score(score),
        .total_lines(total_lines),
        .current_level(current_level),

        .next_piece_type(next_piece_from_bag),
        .next_piece_shape(next_piece_shape),
        .hold_piece_type(hold_piece_type),
        .hold_piece_shape(hold_piece_shape),
        .hold_valid(hold_valid),

        .rgb_out(rgb_out)
    );

    wire [15:0] final_rgb = video_on ? rgb_out : 16'h0000;

    assign VGA_R = final_rgb[15:11];
    assign VGA_G = final_rgb[10:5];
    assign VGA_B = final_rgb[4:0];

endmodule