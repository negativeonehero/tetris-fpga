module tone_gen (
    input  wire        clk_25MHz,
    input  wire        rst_n,
    input  wire        enable,
    input  wire [19:0] half_period,
    output reg         audio_out
);

    reg [19:0] cnt;

    always @(posedge clk_25MHz or negedge rst_n) begin
        if (!rst_n) begin
            cnt       <= 20'd0;
            audio_out <= 1'b0;
        end else if (!enable || (half_period == 20'd0)) begin
            cnt       <= 20'd0;
            audio_out <= 1'b0;
        end else if (cnt == half_period - 20'd1) begin
            cnt       <= 20'd0;
            audio_out <= ~audio_out;
        end else begin
            cnt <= cnt + 20'd1;
        end
    end

endmodule

module tetris_audio #(
    parameter ROM_DEPTH = 2048,
    parameter [7:0] VOLUME = 8'd16   // 0=silent, 255=max
)(
    input  wire clk_25MHz,
    input  wire rst_n,
    input  wire play_enable,
    input  wire restart,
    output wire buzzer_out
);

    // ------------------------------------------------------------
    // 1 ms tick for note durations
    // ------------------------------------------------------------
    reg [14:0] tick1k_cnt;
    reg        tick_1khz;

    always @(posedge clk_25MHz or negedge rst_n) begin
        if (!rst_n) begin
            tick1k_cnt <= 15'd0;
            tick_1khz  <= 1'b0;
        end else begin
            if (tick1k_cnt == 15'd24999) begin
                tick1k_cnt <= 15'd0;
                tick_1khz  <= 1'b1;
            end else begin
                tick1k_cnt <= tick1k_cnt + 15'd1;
                tick_1khz  <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------
    // Song ROM: [35:16] = half_period, [15:0] = duration_ms
    // ------------------------------------------------------------
    reg [35:0] song_rom [0:ROM_DEPTH-1];

    integer i;
    initial begin
        for (i = 0; i < ROM_DEPTH; i = i + 1)
            song_rom[i] = 36'd0;

        $readmemh("korobeiniki.mem", song_rom);
    end

    // ------------------------------------------------------------
    // Sequencer
    // ------------------------------------------------------------
    reg [10:0] rom_addr;
    reg [19:0] cur_half_period;
    reg [15:0] ticks_left;
    reg        song_done;

    wire [35:0] word0     = song_rom[0];
    wire [35:0] next_word = song_rom[rom_addr + 11'd1];

    wire [19:0] word0_half = word0[35:16];
    wire [15:0] word0_dur  = word0[15:0];

    wire [19:0] next_half  = next_word[35:16];
    wire [15:0] next_dur   = next_word[15:0];

    wire next_is_end = (next_word == 36'd0);
    wire word0_is_end = (word0 == 36'd0);

    always @(posedge clk_25MHz or negedge rst_n) begin
        if (!rst_n) begin
            rom_addr        <= 11'd0;
            cur_half_period <= 20'd0;
            ticks_left      <= 16'd0;
            song_done       <= 1'b1;
        end else if (restart) begin
            rom_addr        <= 11'd0;
            cur_half_period <= word0_half;
            ticks_left      <= word0_dur;
            song_done       <= word0_is_end;
        end else if (play_enable && !song_done && tick_1khz) begin
            if (ticks_left > 16'd1) begin
                ticks_left <= ticks_left - 16'd1;
            end else begin
                if (next_is_end) begin
                    // stop instead of looping
                    cur_half_period <= 20'd0;
                    ticks_left      <= 16'd0;
                    song_done       <= 1'b1;
                end else begin
                    rom_addr        <= rom_addr + 11'd1;
                    cur_half_period <= next_half;
                    ticks_left      <= next_dur;
                end
            end
        end
    end

    // ------------------------------------------------------------
    // Raw tone generator
    // ------------------------------------------------------------
    wire raw_tone;
    wire tone_enable = play_enable && !song_done && (cur_half_period != 20'd0);

    tone_gen u_tone (
        .clk_25MHz  (clk_25MHz),
        .rst_n      (rst_n),
        .enable     (tone_enable),
        .half_period(cur_half_period),
        .audio_out  (raw_tone)
    );

    // ------------------------------------------------------------
    // Volume control by ultrasonic PWM gating
    // 25 MHz / 256 = ~97.7 kHz PWM
    // ------------------------------------------------------------
    reg [7:0] pwm_ctr;

    always @(posedge clk_25MHz or negedge rst_n) begin
        if (!rst_n)
            pwm_ctr <= 8'd0;
        else
            pwm_ctr <= pwm_ctr + 8'd1;
    end

    assign buzzer_out = raw_tone & (pwm_ctr < VOLUME);

endmodule