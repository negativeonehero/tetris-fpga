module vga_sync (
    input wire clk_25MHz,
    input wire rst_n,
    output reg hsync,
    output reg vsync,
    output wire video_on,
    output reg [9:0] pixel_x,
    output reg [9:0] pixel_y
);

    localparam H_ACTIVE = 640;
    localparam H_FRONT  = 16;
    localparam H_SYNC   = 96;
    localparam H_BACK   = 48;
    localparam H_TOTAL  = 800;

    localparam V_ACTIVE = 480;
    localparam V_FRONT  = 10;
    localparam V_SYNC   = 2;
    localparam V_BACK   = 33;
    localparam V_TOTAL  = 525;

    always @(posedge clk_25MHz or negedge rst_n) begin
        if (!rst_n) begin
            pixel_x <= 0;
            pixel_y <= 0;
        end else begin
            if (pixel_x == H_TOTAL - 1) begin
                pixel_x <= 0;
                if (pixel_y == V_TOTAL - 1)
                    pixel_y <= 0;
                else
                    pixel_y <= pixel_y + 10'd1;
            end else begin
                pixel_x <= pixel_x + 10'd1;
            end
        end
    end

    always @(posedge clk_25MHz or negedge rst_n) begin
        if (!rst_n) begin
            hsync <= 1'b1;
            vsync <= 1'b1;
        end else begin
            hsync <= ~((pixel_x >= (H_ACTIVE + H_FRONT)) && (pixel_x < (H_ACTIVE + H_FRONT + H_SYNC)));
            vsync <= ~((pixel_y >= (V_ACTIVE + V_FRONT)) && (pixel_y < (V_ACTIVE + V_FRONT + V_SYNC)));
        end
    end

    assign video_on = (pixel_x < H_ACTIVE) && (pixel_y < V_ACTIVE);

endmodule