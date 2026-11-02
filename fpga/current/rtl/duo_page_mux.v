// Both renderers use the same pixel clock/reset/raster and atomic snapshot.
// The visibility bit updates with their UI registers in vertical blank only.
module duo_page_mux(input clk,rst_n,input[1023:0]status,input status_update,
 output[7:0]red,green,blue,output hsync,vsync,de,output frame_request,output menu_visible);
 wire[7:0]pr,pg,pb,mr,mg,mb;wire ph,pv,pd,mh,mv,md,pframe,mframe;
 duo_panel performance(.clk(clk),.rst_n(rst_n),.status(status[799:0]),.status_update(status_update),
  .red(pr),.green(pg),.blue(pb),.hsync(ph),.vsync(pv),.de(pd),.frame_request(pframe));
 duo_menu_panel menu(.clk(clk),.rst_n(rst_n),.status(status[927:800]),.status_update(status_update),
  .red(mr),.green(mg),.blue(mb),.hsync(mh),.vsync(mv),.de(md),.frame_request(mframe));
 reg show_menu;
 always @(posedge clk)begin if(!rst_n)show_menu<=0;else if(status_update)show_menu<=status[860];end
 assign menu_visible=show_menu;assign frame_request=pframe;
 assign red=show_menu ? mr : pr;assign green=show_menu ? mg : pg;assign blue=show_menu ? mb : pb;
 assign hsync=ph;assign vsync=pv;assign de=pd;
endmodule
