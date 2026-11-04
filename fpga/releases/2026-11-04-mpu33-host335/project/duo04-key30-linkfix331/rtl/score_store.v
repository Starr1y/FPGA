// 2 x 2048 x 32 synchronous banks. Only the inactive bank is written.
// Commands 69 begin,70 chunk,71 commit,72 abort,73 readback,74 query.
module score_store(input clk,rst_n,abort,playing,
 input command,input[7:0]kind,input[6:0]length,input[511:0]payload,
 output reg ack,output reg[7:0]code,output busy,output reg uploading,loaded,committed,
 output reg[31:0]transfer_id,active_crc,output reg[11:0]uploaded,total,
 output reg[1:0]profile,output reg[15:0]revision,
 input[10:0]read_address,output[31:0]read_word,
 output reg[10:0]readback_index,output reg[31:0]readback_word,output reg[15:0]readback_revision);
 reg[31:0]bank0[0:2047] /* synthesis syn_ramstyle="block_ram" */;
 reg[31:0]bank1[0:2047] /* synthesis syn_ramstyle="block_ram" */;
 reg active_bank;reg[31:0]q0,q1;
 reg[3:0]state;reg[1:0]byte_index;reg[3:0]word_index,block_count;
 reg[10:0]block_offset;reg[383:0]block_data;reg[31:0]word_q,crc,crc_before,expected_crc;
 reg[11:0]expected_count;reg[1:0]expected_profile;reg duplicate;
 wire[10:0]upload_address=block_offset+{7'b0,word_index};
 wire[10:0]active_address=state==6 || state==7 ? readback_index : read_address;
 wire[10:0]address0=active_bank ? upload_address : active_address;
 wire[10:0]address1=active_bank ? active_address : upload_address;
 wire map_valid;wire[6:0]map_note;
 dual_note_map map(.profile(word_q[1:0]),.zone(word_q[7:4]),.octave(word_q[3:2]),.chord(1'b0),.member(2'b0),.valid(map_valid),.midi_note(map_note));
 wire word_valid=map_valid && map_note==word_q[15:9] && word_q[15:9]>=36 && word_q[15:9]<=83 &&
                 word_q[31:16]>=100 && word_q[31:16]<=10000 && word_q[1:0]==expected_profile;
 wire write_word=state==1 && word_valid && !duplicate;
 assign read_word=active_bank ? q1 : q0;
 assign busy=state!=0;
 always @(posedge clk)begin
  if(write_word && active_bank)bank0[upload_address]<=word_q;
  if(write_word && !active_bank)bank1[upload_address]<=word_q;
  q0<=bank0[address0];q1<=bank1[address1];
 end
 function[31:0]crc_byte;input[31:0]c;input[7:0]b;integer j;reg[31:0]v;
 begin v=c^{24'b0,b};for(j=0;j<8;j=j+1)v=v[0] ? (v>>1)^32'hedb88320 : v>>1;crc_byte=v;end endfunction
 task reply;input[7:0]value;begin code<=value;ack<=1;state<=0;end endtask
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=0;ack<=0;code<=0;uploading<=0;loaded<=0;committed<=0;active_bank<=0;transfer_id<=0;active_crc<=0;
   uploaded<=0;total<=0;profile<=0;revision<=0;expected_crc<=0;expected_count<=0;expected_profile<=0;
   crc<=32'hffffffff;crc_before<=0;word_index<=0;block_count<=0;block_offset<=0;block_data<=0;word_q<=0;byte_index<=0;duplicate<=0;
   readback_index<=0;readback_word<=0;readback_revision<=0;
  end else begin
   ack<=0;committed<=0;
   if(command && state==0)begin
    case(kind)
     69:if(length!=11 || payload[39:32]>2 || payload[55:40]==0 || payload[55:40]>2048)reply(2);
        else if(uploading && payload[31:0]==transfer_id)begin
         if(payload[55:40]!=expected_count || payload[87:56]!=expected_crc || payload[33:32]!=expected_profile)reply(2);else reply(0);
        end else begin
         transfer_id<=payload[31:0];expected_profile<=payload[33:32];expected_count<=payload[51:40];expected_crc<=payload[87:56];
         uploaded<=0;crc<=32'hffffffff;uploading<=1;reply(0);
        end
     70:if(!uploading || payload[31:0]!=transfer_id || length<11 || payload[55:48]==0 || payload[55:48]>12 ||
            {1'b0,length}!=8'd7+({4'b0,payload[51:48]}<<2) || payload[47:32]>=2048 ||
            {1'b0,payload[47:32]}+{9'b0,payload[55:48]}>{5'b0,expected_count})reply(2);
        else if(payload[47:32]>uploaded || (payload[47:32]<uploaded && payload[47:32]+payload[55:48]>uploaded))reply(2);
        else begin
         block_data<=payload[439:56];word_q<=payload[87:56];block_count<=payload[51:48];block_offset<=payload[42:32];
         word_index<=0;byte_index<=0;duplicate<=payload[47:32]<uploaded;crc_before<=crc;state<=1;
        end
     71:if(length!=4 || !uploading || payload[31:0]!=transfer_id || uploaded!=expected_count || ~crc!=expected_crc)reply(2);
        else begin active_bank<=!active_bank;loaded<=1;active_crc<=expected_crc;total<=expected_count;profile<=expected_profile;
         uploading<=0;revision<=revision+1'b1;committed<=1;reply(0);end
     72:begin uploading<=0;reply(0);end
     73:if(playing)reply(3);else if(length!=2 || !loaded || payload[15:0]>=total)reply(2);
        else begin readback_index<=payload[10:0];state<=6;end
     74:if(length!=0)reply(2);else reply(0);
     default:reply(2);
    endcase
   end
   case(state)
    1:if(!word_valid)begin crc<=crc_before;reply(2);end
      else if(duplicate)state<=3;else begin byte_index<=0;state<=2;end
    2:begin
     crc<=crc_byte(crc,word_q[byte_index*8+:8]);
     if(byte_index==3)begin
      if(word_index+1==block_count)begin uploaded<=uploaded+{8'b0,block_count};reply(0);end
      else begin word_index<=word_index+1'b1;word_q<=block_data[(word_index+1)*32+:32];state<=1;end
     end else byte_index<=byte_index+1'b1;
    end
    3:state<=4;
    4:if((active_bank ? q0 : q1)!==word_q)reply(2);
      else if(word_index+1==block_count)reply(0);
      else begin word_index<=word_index+1'b1;word_q<=block_data[(word_index+1)*32+:32];state<=1;end
    6:state<=7;
    7:begin readback_word<=read_word;readback_revision<=readback_revision+1'b1;reply(0);end
   endcase
   if(abort)begin uploading<=0;if(state!=0)reply(3);end
  end
 end
endmodule
