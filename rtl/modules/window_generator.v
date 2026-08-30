// Assume square image and square kernal
`define DATA_WIDTH 8
module window_generator #(
        parameter IMG_WIDTH = 32,
        parameter KRN_WIDTH = 3
    )(
        input  wire                  clk,
        input  wire                  rst,
        input  wire                  shift_en,
        input  wire                  mul_en,
        input  wire                  sum_en,
        input  wire [`DATA_WIDTH-1:0] IMG_IN,
        input  wire [`DATA_WIDTH-1:0] KRN_IN
        //output wire 
    );

    integer i,j;

    reg [`DATA_WIDTH-1:0] buffer [0:KRN_WIDTH-2][0:IMG_WIDTH-1];
    reg [`DATA_WIDTH-1:0] buf_min[0:KRN_WIDTH-1];
    reg [`DATA_WIDTH-1:0] kernal [0:KRN_WIDTH-1][0:KRN_WIDTH-1];

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            for(i = 0; i < KRN_WIDTH-1; i = i+1) begin
                for(j = 0; j < IMG_WIDTH; j = j+1) begin
                    buffer[i][j] <= {`DATA_WIDTH{1'b0}};
                end
            end

            for(j = 0; j < KRN_WIDTH; j = j+1) begin
                buf_min[j] <= {`DATA_WIDTH{1'b0}};
            end

            for(i = 0; i < KRN_WIDTH; i = i+1) begin
                for(j = 0; j < KRN_WIDTH; j = j+1) begin
                    kernal[i][j] <= {`DATA_WIDTH{1'b0}};
                end
            end
        end

        else if(shift_en) begin
            for(j = KRN_WIDTH-1; j > 0; j = j-1) begin
                buf_min[j] <= buf_min[j-1];
            end
            buf_min[0] <= buffer[KRN_WIDTH-2][IMG_WIDTH-1];
            
            for(i = KRN_WIDTH-2; i >= 0; i = i-1) begin
                for(j = IMG_WIDTH-1; j >= 1; j = j-1) begin
                    buffer[i][j] <= buffer[i][j-1];
                end
                if(i) begin
                    buffer[i][0] <= buffer[i-1][IMG_WIDTH-1];
                end 
            end
            buffer[0][0] <= IMG_IN;
        end
    end
endmodule