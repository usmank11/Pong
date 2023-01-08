`default_nettype none
`timescale 1ns / 1ps

module top_pong #(parameter CORDW=10) (    // coordinate width
    input  wire logic clk_pix,             // pixel clock
    input  wire logic reset,             // reset
    input  wire logic start,            // start
    input  wire logic up,              // up
    input  wire logic down,              // down
    output      logic [CORDW-1:0] sdl_sx,  // horizontal SDL position
    output      logic [CORDW-1:0] sdl_sy,  // vertical SDL position
    output      logic sdl_de,              // data enable
    output      logic [7:0] sdl_r,         // red (8-bit)
    output      logic [7:0] sdl_g,         // green (8-bit)
    output      logic [7:0] sdl_b          // blue (8-bit)
    );

    // parameters
    localparam WIN        =  4;  // score needed to win a game (max 9)
    localparam SPEEDUP    =  5;  // speed up ball after this many shots (max 16)
    localparam BALL_SIZE  =  8;  // ball size in pixels
    localparam BALL_ISPX  =  5;  // initial horizontal ball speed
    localparam BALL_ISPY  =  3;  // initial vertical ball speed
    localparam PAD_HEIGHT = 48;  // paddle height in pixels
    localparam PAD_WIDTH  = 10;  // paddle width in pixels
    localparam PAD_OFFS   = 32;  // paddle distance from edge of screen in pixels
    localparam PAD_SPY    =  3;  // vertical paddle speed

    // display sync signals and coordinates
    logic [CORDW-1:0] sx, sy;
    logic de;
    display display_inst (
        .clk_pix,
        .rst_pix(reset),
        .sx,
        .sy,
        /* verilator lint_off PINCONNECTEMPTY */
        .hsync(),
        .vsync(),
        /* verilator lint_on PINCONNECTEMPTY */
        .de
    );

    // screen dimensions
    localparam H_RES = 640;  // horizontal screen resolution
    localparam V_RES = 480;  // vertical screen resolution

    logic frame;
    always_comb frame = (sy == V_RES && sx == 0);

    // score
    logic [3:0] score_l;  // left score
    logic [3:0] score_r;  // right score

    // signals
    logic ball, padl, padr;

    // ball properties
    logic [CORDW-1:0] ball_x, ball_y;  // position
    logic [CORDW-1:0] ball_spx;        // horizontal speed
    logic [CORDW-1:0] ball_spy;        // vertical speed
    logic [3:0] shot_cnt;              // shot counter
    logic ball_dx, ball_dy;            // direction: 0 is right/down
    logic ball_dx_prev;                // direction in previous tick
    logic coll_r, coll_l;              // screen collision flags

    // paddle properties
    logic [CORDW-1:0] padl_y, padr_y;  // vertical position of paddles
    logic [CORDW-1:0] ai_y, play_y;    // vertical position of AI and player paddle

    always_comb begin
        padl_y = play_y;
        padr_y = ai_y;
    end

    // debounce buttons
    logic sig_start, sig_up, sig_dn;
    /* verilator lint_off PINCONNECTEMPTY */
    debounce deb_start (.clk(clk_pix), .in(start), .out(), .ondn(), .onup(sig_start));
    debounce deb_up (.clk(clk_pix), .in(up), .out(sig_up), .ondn(), .onup());
    debounce deb_dn (.clk(clk_pix), .in(down), .out(sig_dn), .ondn(), .onup());
    /* verilator lint_on PINCONNECTEMPTY */

    // state
    enum {NEW_GAME, POSITION, READY, POINT, END_GAME, PLAY} state, state_next;
    always_comb begin
        case (state)
            NEW_GAME: state_next = POSITION;
            POSITION: state_next = READY;
            READY: state_next = (sig_start) ? PLAY : READY;
            POINT: state_next = (sig_start) ? POSITION : POINT;
            END_GAME: state_next = (sig_start) ? NEW_GAME : END_GAME;
            PLAY: begin
                if (coll_l || coll_r) begin
                    if ((score_l == WIN) || (score_r == WIN)) state_next = END_GAME;
                    else state_next = POINT;
                end else state_next = PLAY;
            end
            default: state_next = NEW_GAME;
        endcase
        if (reset) state_next = NEW_GAME;
    end

    // update state
    always_ff @(posedge clk_pix) state <= state_next;


    // Player control
    always_ff @(posedge clk_pix) begin
        if (state == POSITION) play_y <= (V_RES - PAD_HEIGHT)/2;
        else if (frame && state == PLAY) begin
            if (sig_dn) begin
                if (play_y + PAD_HEIGHT + PAD_SPY >= V_RES-1) begin
                    play_y <= V_RES - PAD_HEIGHT - 1;
                end else play_y <= play_y + PAD_SPY;
            end else if (sig_up) begin
                if (play_y < PAD_SPY) begin
                    play_y <= 0;
                end else play_y <= play_y - PAD_SPY;
            end
        end
    end

    // AI control
    always_ff @(posedge clk_pix) begin
        if (state == POSITION) ai_y <= (V_RES - PAD_HEIGHT)/2;
        else if (frame && state == PLAY) begin
            if (ai_y + PAD_HEIGHT/2 < ball_y) begin
                if (ai_y + PAD_HEIGHT + PAD_SPY >= V_RES-1) begin
                    ai_y <= V_RES - PAD_HEIGHT - 1;
                end else ai_y <= ai_y + PAD_SPY;
            end else if (ai_y + PAD_HEIGHT/2 > ball_y + BALL_SIZE) begin
                if (ai_y < PAD_SPY) begin 
                    ai_y <= 0;
                end else ai_y <= ai_y - PAD_SPY;
            end
        end
    end

    // ball control
    always_ff @(posedge clk_pix) begin
        case (state)
            NEW_GAME: begin
                score_l <= 0;  // reset score
                score_r <= 0;
            end

            POSITION: begin
                coll_l <= 0;
                coll_r <= 0;
                ball_spx <= BALL_ISPX;
                ball_spy <= BALL_ISPY;
                shot_cnt <= 0;


                ball_y <= (V_RES - BALL_SIZE)/2;
                if (coll_r) begin
                    ball_x <= H_RES - (PAD_OFFS + PAD_WIDTH + BALL_SIZE);
                    ball_dx <= 1;
                end else begin
                    ball_x <= PAD_OFFS + PAD_WIDTH;
                    ball_dx <= 0;
                end
            end

            PLAY: begin
                if (frame) begin
                    // horizontal ball position
                    if (ball_dx == 0) begin  // move right
                        if (ball_x + BALL_SIZE + ball_spx >= H_RES-1) begin
                            ball_x <= H_RES-BALL_SIZE;  // move to edge of screen
                            score_l <= score_l + 1;
                            coll_r <= 1;
                        end else ball_x <= ball_x + ball_spx;
                    end else begin  // moving left
                        if (ball_x < ball_spx) begin
                            ball_x <= 0;  // move to edge of screen
                            score_r <= score_r + 1;
                            coll_l <= 1;
                        end else ball_x <= ball_x - ball_spx;
                    end

                    // vertical ball position
                    if (ball_dy == 0) begin  // move down
                        if (ball_y + BALL_SIZE + ball_spy >= V_RES-1)
                            ball_dy <= 1;
                        else ball_y <= ball_y + ball_spy;
                    end else begin  // move up
                        if (ball_y < ball_spy)
                            ball_dy <= 0;
                        else ball_y <= ball_y - ball_spy;
                    end

                    if (ball_dx_prev != ball_dx) shot_cnt <= shot_cnt + 1;
                    if (shot_cnt == SPEEDUP) begin  // increase speed
                        ball_spx <= (ball_spx < PAD_WIDTH) ? ball_spx + 1 : ball_spx;
                        ball_spy <= ball_spy + 1;
                        shot_cnt <= 0;
                    end
                end
            end
        endcase

        // change direction if collision
        if (ball && padl && ball_dx==1) ball_dx <= 0;  // left paddle
        if (ball && padr && ball_dx==0) ball_dx <= 1;  // right paddle

        // record ball direction
        if (frame) ball_dx_prev <= ball_dx;
    end

    always_comb begin
        ball = (sx >= ball_x) && (sx < ball_x + BALL_SIZE)
               && (sy >= ball_y) && (sy < ball_y + BALL_SIZE);
        padl = (sx >= PAD_OFFS) && (sx < PAD_OFFS + PAD_WIDTH)
               && (sy >= padl_y) && (sy < padl_y + PAD_HEIGHT);
        padr = (sx >= H_RES - PAD_OFFS - PAD_WIDTH - 1) && (sx < H_RES - PAD_OFFS - 1)
               && (sy >= padr_y) && (sy < padr_y + PAD_HEIGHT);
    end

    // drawing score
    logic pix_score;
    score score_inst (
        .clk_pix,
        .sx,
        .sy,
        .score_l,
        .score_r,
        .pix(pix_score)
    );

    // colours
    logic [3:0] paint_r, paint_g, paint_b;
    always_comb begin
        if (pix_score) {paint_r, paint_g, paint_b} = 12'hFFF;  // score
        else if (ball) {paint_r, paint_g, paint_b} = 12'hFFF;  // ball
        else if (padl || padr) {paint_r, paint_g, paint_b} = 12'hFFF;  // paddles
        else {paint_r, paint_g, paint_b} = 12'h000;  // background
    end

    // SDL output
    always_ff @(posedge clk_pix) begin
        sdl_sx <= sx;
        sdl_sy <= sy;
        sdl_de <= de;
        sdl_r <= {2{paint_r}};
        sdl_g <= {2{paint_g}};
        sdl_b <= {2{paint_b}};
    end
endmodule