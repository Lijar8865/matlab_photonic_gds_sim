clc;
clear;
close all;
scriptPath = '';
if usejava('desktop')
    scriptPath = matlab.desktop.editor.getActiveFilename();
end
if isempty(scriptPath)
    scriptPath = mfilename('fullpath');    % 如果没有打开 Desktop，使用 mfilename 获取当前脚本路径
end
[scriptFolder, ~, ~] = fileparts(scriptPath);
cd(scriptFolder);
workspaceRoot = fileparts(fileparts(scriptFolder));
libFolder = fullfile(workspaceRoot, 'lib');
addpath(libFolder);
run_date = datestr(now, 'yyyymmdd');
format long g

%% ==================== 参数配置 ====================
% Crossing 基本参数
supple_wid = 0.12;%波导线宽补偿
W_wg = 1.34+supple_wid;      % 单模波导宽度
W_slab = 4.2;
etch_angle = 70;
h_wg = 0.25;
cross_para_default = struct(...
    'Wid_inout', W_wg, ...      % 输入输出波导宽度 (μm)
    'input_length', 13, ...    % 输入直波导长度 (μm)
    'cross_length', 21.6, ...  % 交叉区域长度 (μm)
    'cross_width', 2.9, ...    % 交叉区域宽度 (μm)
    'taper_length', 6.2, ...     % 锥形过渡长度 (μm)
    'm_wid', 1, ...            % 锥形参数
    'etch_angle', etch_angle, ...      % 刻蚀角度
    'h_wg', h_wg ...          % 波导高度 (μm)
    );

%% 布局参数
N_cascade = 10;    % 级联数量
%%
% 获取当前参数
Cross_para = cross_para_default;
[cross_wg1, para_out] = Wcli_wg.cross_wg_gen(...
    'Wid_inout', Cross_para.Wid_inout, ...
    'input_length', Cross_para.input_length, ...
    'cross_length', Cross_para.cross_length, ...
    'cross_width', Cross_para.cross_width, ...
    'taper_length', Cross_para.taper_length, ...
    'm_wid', Cross_para.m_wid, ...
    'etch_angle', Cross_para.etch_angle, ...
    'h_wg', Cross_para.h_wg);

cross_wg1.transform_shape(pi/4);
cross_wg2=cross_wg1.copy;
cross_wg2.transform_shape(pi/2);
cross_cells = cell(N_cascade,2);
cross_cells_ext = cell(N_cascade,2);  % 添加延拓层 cell
spac_cross = abs(cross_wg1.get_port_dx);
cross_cas_dx = spac_cross*N_cascade;
for i_c = 1:N_cascade
    temp_wg1 = cross_wg1.copy;
    temp_wg1.align_port_out([spac_cross*(i_c-0.5),spac_cross*(i_c-0.5)]);
    cross_cells{i_c,1} = temp_wg1;
    
    temp_wg2 = cross_wg2.copy;
    temp_wg2.move_to("cen",temp_wg1.get_align_point("cen"));
    cross_cells{i_c,2} = temp_wg2;
    
    % 生成延拓层
    temp_wg1_ext = temp_wg1.copy;
    temp_wg1_ext.set_width_list(temp_wg1_ext.width_list + W_slab*2);
    cross_cells_ext{i_c,1} = temp_wg1_ext;
    
    temp_wg2_ext = temp_wg2.copy;
    temp_wg2_ext.set_width_list(temp_wg2_ext.width_list + W_slab*2);
    cross_cells_ext{i_c,2} = temp_wg2_ext;
end
cross_cells = cross_cells';
cross_cells = cross_cells(:);
cross_cells_ext = cross_cells_ext';
cross_cells_ext = cross_cells_ext(:);
in_bend = Wcli_wg.Euler_Arc_bend_gen( ...
    2000, ... % 最大弯曲半径
    100, ... % 计算得到的圆弧半径
    pi/4, ... % 总弯曲角度
    pi/8, ... % 欧拉段角度
    201, ... % 每段的生成点数
    W_wg, ... % 输入波导宽度
    W_wg, ... % 输出波导宽度
    70, ... % 刻蚀角度
    0.25, ... % 波导高度
    0 ... % 初始角度
    );
in_bend.flip_shape;
out_bend = in_bend.copy;
out_bend.transform_shape(pi);

heater_gap = 3;
win_exclude = 5;
heater_wg = Wcli_wg.Straight_wg_gen(cross_cas_dx*sqrt(2),0,13);
heater_wg_win = Wcli_wg.Straight_wg_gen(cross_cas_dx*sqrt(2)+win_exclude*2,0,13+win_exclude*2);
heater_wg.transform_shape(pi/4);
heater_wg_win.transform_shape(pi/4);

% 添加 heater slab 层
heater_slab = Wcli_wg.Straight_wg_gen(cross_cas_dx*sqrt(2), 0, W_wg + 2*heater_gap + 2*13);
heater_slab.transform_shape(pi/4);


mmi1x2 = Wcli_wg.mmi_1x2_half_gen("fanout_spac",spac_cross*2,"Win",W_wg,"Wout",W_wg);%mmi引用
mmi_dx = abs(mmi1x2.get_port_dx);
mod_arm1=mmi1x2.copy;
mmi_in2=mmi1x2.copy;
mmi_in1=mmi1x2.copy;
mmi_out1 = mmi1x2.copy;
mmi_out1.mirror_translate_shape('y');
mod_arm2 = mmi_out1.copy;
mod_arm2.mirror_translate_shape('x');


mod_arm2.merge_and_translate(0,0,1,out_bend.flip_shape);
move_dxy = -mod_arm2.get_port_outxy+(N_cascade-0.5)*spac_cross;
mod_arm2.transform_shape(0,move_dxy(1),move_dxy(2));
mod_arm2.merge_and_translate(-cross_cas_dx,-cross_cas_dx,1,in_bend);
mod_arm2.merge_and_translate(0,0,1,mmi_in2.mirror_translate_shape("x"));


mod_arm1.mirror_translate_shape("y");
mod_arm1.flip_shape;
mod_arm1.merge_and_translate(0,0,1,out_bend);
heater_wg.align_port_out(mod_arm1.get_port_outxy);
mod_arm1.merge_and_translate(-cross_cas_dx,-cross_cas_dx,1,in_bend);
mod_arm1.merge_and_translate(0,0,1,mmi_in1.flip_shape);
mod_arm1.transform_shape(0,move_dxy(1),move_dxy(2));
heater_wg.transform_shape(0,move_dxy(1),move_dxy(2));
heater_wg.transform_shape(0,-(heater_gap+13/2+W_wg/2)/sqrt(2),(heater_gap+13/2+W_wg/2)/sqrt(2));
heater_wg.align_wg(heater_wg_win,"cen");
heater_wg.align_obj(heater_slab,"cen");
heater_wg_down = heater_wg.copy;
heater_wg_down.transform_shape(0,(heater_gap*2+13+W_wg)/sqrt(2),-(heater_gap*2+13+W_wg)/sqrt(2));
heater_wg_win_down = heater_wg_win.copy;
heater_wg_win_down.transform_shape(0,(heater_gap*2+13+W_wg)/sqrt(2),-(heater_gap*2+13+W_wg)/sqrt(2));

heater_cell = Wcli_circuit({heater_wg_down,heater_wg, heater_wg_win_down,heater_wg_win}, ...
                                    "laycells", [4,4, 3,3], "name", 'fold_heater_with_window');
heater_cell.align_obj(heater_slab,"cen");
heater_cell.add_cell(heater_slab,1);

% 波导层单独处理-slab延拓
W_slab = 5;  % slab 延拓宽度
mod_arm1_ext = mod_arm1.copy;
mod_arm1_ext.set_width_list(mod_arm1_ext.width_list + W_slab*2);
mod_arm2_ext = mod_arm2.copy;
mod_arm2_ext.set_width_list(mod_arm2_ext.width_list + W_slab*2);

main_circuit1 = Wcli_circuit(cross_cells(:),"laycells",10);  % 交叉波导 Layer 10
temp_cir=Wcli_circuit(cross_cells_ext(:),"laycells",1);  % 交叉波导 Layer 10;
main_circuit1.merge_cell(temp_cir);
% for i_ext = 1:length(cross_cells_ext)
%     main_circuit1.add_cell(cross_cells_ext{i_ext}, 1);  % 延拓层 Layer 1
% end
main_circuit1.add_cell(mod_arm2, 10);     % 原波导 Layer 10
main_circuit1.add_cell(mod_arm1, 10);     % 原波导 Layer 10
main_circuit1.add_cell(mod_arm2_ext, 1);  % 延拓波导 Layer 1
main_circuit1.add_cell(mod_arm1_ext, 1);  % 延拓波导 Layer 1
main_circuit1.merge_cell(heater_cell);  % 添加 heater 相关结构
main_circuit1.move_to("botleft",[0,0]);

all_circuit = main_circuit1.copy;
rev_index=1:10;
main_circuit1.remove_cell(rev_index);
main_circuit1.remove_cell(rev_index+20-10);
all_circuit.merge_cell(main_circuit1.copy,"self_pos","botleft","target_pos","botleft","Txy",[0,200]);
rev_index=1:4;
main_circuit1.remove_cell(rev_index);
main_circuit1.remove_cell(rev_index+20-10-4);
all_circuit.merge_cell(main_circuit1.copy,"self_pos","botleft","target_pos","botleft","Txy",[0,400]);
rev_index=1:6;
main_circuit1.remove_cell(rev_index);
main_circuit1.remove_cell(rev_index+20-10-4-6);
all_circuit.merge_cell(main_circuit1.copy,"self_pos","botleft","target_pos","botleft","Txy",[0,600]);
%% single test1
in_wg = Wcli_wg.Straight_wg_gen(15,0,W_wg,etch_angle,h_wg);
out_wg = in_wg.copy;
test_cross1 = in_wg.copy;
test_cross1.merge_and_translate(mmi_dx-150,0,0,in_bend.flip_shape);
test_cross1.align_port_in([0,700]);
cross_cells = cell(N_cascade,2);
cross_cells_ext = cell(N_cascade,2);
cross_cas_dx = N_cascade*spac_cross;
for i_c = 1:N_cascade
    temp_wg1 = cross_wg1.copy;
    temp_wg1.align_port_out([spac_cross*(i_c),spac_cross*(i_c)]+test_cross1.get_port_outxy);
    cross_cells{i_c,1} = temp_wg1;
    
    temp_wg2 = cross_wg2.copy;
    temp_wg2.move_to("cen",temp_wg1.get_align_point("cen"));
    cross_cells{i_c,2} = temp_wg2;
    
    % 生成延拓层
    temp_wg1_ext = temp_wg1.copy;
    temp_wg1_ext.set_width_list(temp_wg1_ext.width_list + W_slab*2);
    cross_cells_ext{i_c,1} = temp_wg1_ext;
    
    temp_wg2_ext = temp_wg2.copy;
    temp_wg2_ext.set_width_list(temp_wg2_ext.width_list + W_slab*2);
    cross_cells_ext{i_c,2} = temp_wg2_ext;
end
cross_cells = cross_cells';
cross_cells = cross_cells(:);
cross_cells_ext = cross_cells_ext';
cross_cells_ext = cross_cells_ext(:);
test_cross1.merge_and_translate(cross_cas_dx+20,cross_cas_dx+20,1,out_bend.flip_shape);
dx_cal = main_circuit1.get_boundary_dx-test_cross1.get_port_out_x;
test_cross1.merge_and_translate(dx_cal-15,0,1,out_wg);

% 波导层单独处理-slab延拓 (test1)
test_cross1_ext = test_cross1.copy;
test_cross1_ext.set_width_list(test_cross1_ext.width_list + W_slab*2);

cross_1_circuit = Wcli_circuit(cross_cells(:), "laycells", 10);
for i_ext = 1:length(cross_cells_ext)
    cross_1_circuit.add_cell(cross_cells_ext{i_ext}, 1);
end
cross_1_circuit.add_cell(test_cross1, 10);
cross_1_circuit.add_cell(test_cross1_ext, 1);
all_circuit.merge_cell(cross_1_circuit);
%% single test2
test_cross1 = in_wg.copy;
test_cross1.merge_and_translate(mmi_dx-230,0,0,in_bend);
test_cross1.align_port_in([0,730]);
N_test2 = 5;
cross_cells = cell(N_test2,2);
cross_cells_ext = cell(N_test2,2);
for i_c = 1:N_test2
    temp_wg1 = cross_wg1.copy;
    temp_wg1.align_port_out([spac_cross*(i_c),spac_cross*(i_c)]+test_cross1.get_port_outxy);
    cross_cells{i_c,1} = temp_wg1;
    
    temp_wg2 = cross_wg2.copy;
    temp_wg2.move_to("cen",temp_wg1.get_align_point("cen"));
    cross_cells{i_c,2} = temp_wg2;
    
    % 生成延拓层
    temp_wg1_ext = temp_wg1.copy;
    temp_wg1_ext.set_width_list(temp_wg1_ext.width_list + W_slab*2);
    cross_cells_ext{i_c,1} = temp_wg1_ext;
    
    temp_wg2_ext = temp_wg2.copy;
    temp_wg2_ext.set_width_list(temp_wg2_ext.width_list + W_slab*2);
    cross_cells_ext{i_c,2} = temp_wg2_ext;
end
cross_cells = cross_cells';
cross_cells = cross_cells(:);
cross_cells_ext = cross_cells_ext';
cross_cells_ext = cross_cells_ext(:);
test_cross1.merge_and_translate(cross_cas_dx+20,cross_cas_dx+20,1,out_bend);
dx_cal = main_circuit1.get_boundary_dx-test_cross1.get_port_out_x;
test_cross1.merge_and_translate(dx_cal-15,0,1,out_wg);

% 波导层单独处理-slab延拓 (test2)
test_cross1_ext = test_cross1.copy;
test_cross1_ext.set_width_list(test_cross1_ext.width_list + W_slab*2);

cross_1_circuit = Wcli_circuit(cross_cells(:), "laycells", 10);
for i_ext = 1:length(cross_cells_ext)
    cross_1_circuit.add_cell(cross_cells_ext{i_ext}, 1);
end
cross_1_circuit.add_cell(test_cross1, 10);
cross_1_circuit.add_cell(test_cross1_ext, 1);
all_circuit.merge_cell(cross_1_circuit);
%% single test3
test_cross1 = in_wg.copy;
test_cross1.merge_and_translate(mmi_dx-270,0,0,in_bend);
test_cross1.align_port_in([0,760]);
N_test2 = 0;
cross_cells = cell(N_test2,2);
cross_cells_ext = cell(N_test2,2);
for i_c = 1:N_test2
    temp_wg1 = cross_wg1.copy;
    temp_wg1.align_port_out([spac_cross*(i_c),spac_cross*(i_c)]+test_cross1.get_port_outxy);
    cross_cells{i_c,1} = temp_wg1;
    
    temp_wg2 = cross_wg2.copy;
    temp_wg2.move_to("cen",temp_wg1.get_align_point("cen"));
    cross_cells{i_c,2} = temp_wg2;
    
    % 生成延拓层 (虽然 N_test2=0, 但保持代码结构一致)
    temp_wg1_ext = temp_wg1.copy;
    temp_wg1_ext.set_width_list(temp_wg1_ext.width_list + W_slab*2);
    cross_cells_ext{i_c,1} = temp_wg1_ext;
    
    temp_wg2_ext = temp_wg2.copy;
    temp_wg2_ext.set_width_list(temp_wg2_ext.width_list + W_slab*2);
    cross_cells_ext{i_c,2} = temp_wg2_ext;
end
cross_cells = cross_cells';
cross_cells = cross_cells(:);
cross_cells_ext = cross_cells_ext';
cross_cells_ext = cross_cells_ext(:);
test_cross1.merge_and_translate(cross_cas_dx+20,cross_cas_dx+20,1,out_bend);
dx_cal = main_circuit1.get_boundary_dx-test_cross1.get_port_out_x;
test_cross1.merge_and_translate(dx_cal-15,0,1,out_wg);

% 波导层单独处理-slab延拓 (test3)
test_cross1_ext = test_cross1.copy;
test_cross1_ext.set_width_list(test_cross1_ext.width_list + W_slab*2);

cross_1_circuit = Wcli_circuit(cross_cells(:), "laycells", 10);
for i_ext = 1:length(cross_cells_ext)
    cross_1_circuit.add_cell(cross_cells_ext{i_ext}, 1);
end
cross_1_circuit.add_cell(test_cross1, 10);
cross_1_circuit.add_cell(test_cross1_ext, 1);
all_circuit.merge_cell(cross_1_circuit);
%% rint test 1
ring_para = struct(...
    'etch_angle', 70, ...       % 单位：degrees
    'h_wg', 0.25, ...           % 单位：um
    'h_slab', 0.25, ...         % 单位：um
    'Wid_bus', W_wg, ...         % 总线波导宽度
    'Wid_ring', W_wg, ...        % 微环波导宽度
    'R_ring', 100, ...           % 微环半径
    'gap', 0.8-supple_wid, ...             % 耦合间隙
    'cou_ang',10,...            % 耦合角度（°）
    'input_length', 15, ...     % 输入输出延长段
    'ring_str_length',80 ...   % 微环直跑道长度
    );

[ring_wg, bus_all_wg, para_name] = LT_pully_ring_gen(ring_para);

test_crossring = in_wg.copy;
test_crossring.merge_and_translate(mmi_dx-270,0,0,in_bend);
test_crossring.align_port_in([0,820]);
len_bus = abs(bus_all_wg.get_port_dy);
xwid_ring = abs(ring_wg.get_boundary_dx);
ywid_ring = abs(ring_wg.get_boundary_dy);
bus_all_wg.transform_shape(-pi/4);
bus_all_wg.flip_shape

ring_wg.transform_shape(-pi/4);
move_dx = bus_all_wg.get_port_in_x-test_crossring.get_port_out_x-100;
move_dy = bus_all_wg.get_port_in_y-test_crossring.get_port_out_y-100;
bus_all_wg.transform_shape(0,-move_dx,-move_dy);
ring_wg.transform_shape(0,-move_dx,-move_dy);
test_crossring.merge_and_translate(100,100,0,bus_all_wg);


bend_90 = Wcli_wg.Euler_Arc_bend_gen( ...
    2000, ... % 最大弯曲半径
    100, ... % 计算得到的圆弧半径
    pi/2, ... % 总弯曲角度
    pi/4, ... % 欧拉段角度
    201, ... % 每段的生成点数
    W_wg, ... % 输入波导宽度
    W_wg, ... % 输出波导宽度
    70, ... % 刻蚀角度
    0.25, ... % 波导高度
    0 ... % 初始角度
    );
bend_270 = Wcli_wg.Euler_Arc_bend_gen( ...
    2000, ... % 最大弯曲半径
    100, ... % 计算得到的圆弧半径
    pi/4*3, ... % 总弯曲角度
    pi/4, ... % 欧拉段角度
    201, ... % 每段的生成点数
    W_wg, ... % 输入波导宽度
    W_wg, ... % 输出波导宽度
    70, ... % 刻蚀角度
    0.25, ... % 波导高度
    0 ... % 初始角度
    );
bend_90.transform_shape(pi/4);
bend_270.transform_shape(pi);
test_crossring.merge_and_translate(0,0,1,bend_90);
test_crossring.merge_and_translate(-250,250-0.633,1,bend_270.flip_shape);
last_xy = cross_1_circuit.get_align_point("topright");
move_dx = last_xy(1)-test_crossring.get_port_out_x-15;
test_crossring.merge_and_translate(move_dx,0,0,in_wg);

test_crossring_ext = test_crossring.copy;
test_crossring_ext.set_width_list(test_crossring_ext.width_list+2*W_slab);
ring_wg_ext = ring_wg.copy;
ring_wg_ext.set_width_list(ring_wg_ext.width_list+2*W_slab);

cross_ring_circuit = Wcli_circuit({test_crossring,test_crossring_ext,ring_wg,ring_wg_ext},"laycells",[10,1,10,1]);
all_circuit.merge_cell(cross_ring_circuit);

%%  rint test 2
ring_para = struct(...
    'etch_angle', 70, ...       % 单位：degrees
    'h_wg', 0.25, ...           % 单位：um
    'h_slab', 0.25, ...         % 单位：um
    'Wid_bus', W_wg, ...         % 总线波导宽度
    'Wid_ring', W_wg, ...        % 微环波导宽度
    'R_ring', 100, ...           % 微环半径
    'gap', 0.8, ...             % 耦合间隙
    'cou_ang',10,...            % 耦合角度（°）
    'input_length', 15, ...     % 输入输出延长段
    'ring_str_length',80 ...   % 微环直跑道长度
    );

[ring_wg, bus_all_wg, para_name] = LT_pully_ring_gen(ring_para);

test_crossring = in_wg.copy;
test_crossring.merge_and_translate(mmi_dx-270,0,0,in_bend);
test_crossring.align_port_in([0,790]);
len_bus = abs(bus_all_wg.get_port_dy);
xwid_ring = abs(ring_wg.get_boundary_dx);
ywid_ring = abs(ring_wg.get_boundary_dy);
bus_all_wg.transform_shape(-pi/4);
bus_all_wg.flip_shape

ring_wg.transform_shape(-pi/4+pi);
move_dx = bus_all_wg.get_port_in_x-test_crossring.get_port_out_x-400;
move_dy = bus_all_wg.get_port_in_y-test_crossring.get_port_out_y-400;
bus_all_wg.transform_shape(0,-move_dx,-move_dy);
ring_wg.transform_shape(0,-move_dx,-move_dy);
test_crossring.merge_and_translate(400,400,0,bus_all_wg);

last_xy = cross_1_circuit.get_align_point("topright");
move_dy = test_cross1.get_port_out_y-test_crossring.get_port_out_y-out_bend.get_port_dy+30;
test_crossring.merge_and_translate(move_dy,move_dy,0,out_bend);
move_dx = test_cross1.get_port_out_x-test_crossring.get_port_out_x-15;
test_crossring.merge_and_translate(move_dx,0,0,in_wg);

ring_cross_out1 = cross_wg1.copy;
ring_cross_out2 = cross_wg2.copy;
ring_cross_out1.move_to("cen",ring_wg.get_align_point("cen")+ywid_ring/2/sqrt(2)-W_wg/2/sqrt(2));
ring_cross_out2.move_to("cen",ring_wg.get_align_point("cen")+ywid_ring/2/sqrt(2)-W_wg/2/sqrt(2));
move_dy=cross_ring_circuit.get_boundary_ymax-W_wg/2-ring_cross_out1.get_port_out_y-out_bend.get_port_dy-30;
ring_cross_out1.merge_and_translate(move_dy,move_dy,0,out_bend);
move_dx = cross_ring_circuit.get_boundary_xmax-ring_cross_out1.get_boundary_xmax-15;
ring_cross_out1.merge_and_translate(move_dx,0,0,in_wg);
% 波导层单独处理-slab延拓 (ring test 2)
test_crossring_ext = test_crossring.copy;
test_crossring_ext.set_width_list(test_crossring_ext.width_list + W_slab*2);
ring_wg_ext = ring_wg.copy;
ring_wg_ext.set_width_list(ring_wg_ext.width_list + W_slab*2);
ring_cross_out1_ext = ring_cross_out1.copy;
ring_cross_out1_ext.set_width_list(ring_cross_out1_ext.width_list + W_slab*2);
ring_cross_out2_ext = ring_cross_out2.copy;
ring_cross_out2_ext.set_width_list(ring_cross_out2_ext.width_list + W_slab*2);

cross_ring_circuit = Wcli_circuit({test_crossring, ring_wg, ring_cross_out1, ring_cross_out2, ...
                                   test_crossring_ext, ring_wg_ext, ring_cross_out1_ext, ring_cross_out2_ext}, ...
                                  "laycells", [10, 10, 10, 10, 1, 1, 1, 1]);
all_circuit.merge_cell(cross_ring_circuit);


%% gds
for gds=[1]
    %% 生成 GDS
    gds_folder = ['gds_gen_cross_test', run_date];
    if ~exist(fullfile(scriptFolder, gds_folder), 'dir')
        mkdir(fullfile(scriptFolder, gds_folder));
    end

    para_name = Wcli_wg.generate_save_name(para_out,'crosstest');

    FileDc = fullfile(scriptFolder, gds_folder, [para_name, '.gds']);
    % 生成GDS文件
%     all_circuit.generate_gds(FileDc, para_name, 'CrossTestLib');
    all_circuit.generate_gds(FileDc, 'wcli_cross_test', 'CrossTestLib');
    gdsII_FileDc = fullfile(scriptFolder, gds_folder, ['ii_', para_name, '.gds']);
    Wcli_poly.klayout_gds2gdsii(FileDc, gdsII_FileDc);
    Wcli_poly.klayout_gds_subtract(gdsII_FileDc, 'output_gds',gdsII_FileDc);
end

function [ring_wg, bus_all_wg, para_name] = LT_pully_ring_gen(para, options)
    % 生成跑道型微环谐振器及滑轮型耦合总线波导
    %
    % 输入参数:
    %   para - 参数结构体，包含以下字段:
    %       etch_angle      - 刻蚀角度 (degrees)
    %       h_wg            - 波导高度 (μm)
    %       h_slab          - 平板层高度 (μm)
    %       Wid_bus         - 总线波导宽度 (μm)
    %       Wid_ring        - 微环波导宽度 (μm)
    %       R_ring          - 微环半径 (μm)
    %       gap             - 耦合间隙 (μm)
    %       cou_ang         - 耦合角度 (degrees)
    %       input_length    - 输入输出延长段 (μm)
    %       ring_str_length - 微环直跑道长度 (μm)
    %
    % 名称-值参数:
    %   N_point         - 生成点数 (默认 201)
    %   R_max           - 直波导半径 (默认 2000)
    %   R_min           - 通用最小半径 (默认 100)
    %   bus_cen_angle   - 总线中间切线角度 (degrees, 默认 80)
    %   bus_str_length  - 总线直段长度 (μm, 默认 50)
    %
    % 输出:
    %   ring_wg   - 微环波导对象
    %   bus_all_wg - 总线波导对象
    %   para_name - 自动生成的参数名称字符串
    %
    % 示例:
    %   para = struct('Wid_bus', 1.4, 'R_ring', 50, 'gap', 0.8, ...);
    %   [ring, bus, name] = LT_pully_ring_gen(para);
    %   ring.plot_kappa_wg();
    %   bus.plot_kappa_wg();
    
    arguments
        para struct
        options.N_point (1,1) double {mustBePositive, mustBeInteger} = 201
        options.R_max (1,1) double {mustBePositive} = 2000
        options.R_min (1,1) double {mustBePositive} = 100
        options.bus_cen_angle (1,1) double = 80  % degrees
        options.bus_str_length (1,1) double {mustBePositive} = 5
    end
    
    %% 验证必需的参数字段
    required_fields = {'etch_angle', 'h_wg', 'Wid_bus', 'Wid_ring', ...
                       'R_ring', 'gap', 'cou_ang'};
    for i = 1:length(required_fields)
        if ~isfield(para, required_fields{i})
            error('缺少必需参数: %s', required_fields{i});
        end
    end
    
    %% 设置默认值
    if ~isfield(para, 'h_slab')
        para.h_slab = 0.25;
    end
    if ~isfield(para, 'input_length')
        para.input_length = 15;
    end
    if ~isfield(para, 'ring_str_length')
        para.ring_str_length = 100;
    end
    
    N_point = options.N_point;
    R_max = options.R_max;
    R_min = options.R_min;
    
    %% ==================== 生成跑道型微环 ====================
    
    % 微环参数
    ring_arc_angle = deg2rad(para.cou_ang);  % 圆弧段角度
    ring_euler_angle = pi - ring_arc_angle;  % 欧拉段角度，总角度为180度
    
    % 微环 - 右侧半圆（欧拉+圆弧+欧拉，共180度）
    ring_right_semi = Wcli_wg.Euler_Arc_bend_gen(...
        R_max, ...                    % R_max: 从直线开始
        para.R_ring, ...             % R_arc: 圆弧段半径
        pi, ...                      % total_angle: 总共180度
        ring_euler_angle, ...        % Euler_angle: 欧拉段角度
        N_point, ...
        para.Wid_ring, ...
        para.Wid_ring, ...
        para.etch_angle, ...
        para.h_wg, ...
        0);                          % initial_angle: 从0度开始
    
    % 微环 - 左侧半圆（复制右侧并镜像）
    ring_left_semi = ring_right_semi.copy();
    ring_left_semi.mirror_translate_shape('y');
    
    % 拼接跑道型微环
    ring_wg = ring_left_semi.copy();
    ring_wg.merge_and_translate(para.ring_str_length, 0, 0, ring_right_semi);
    ring_wg = ring_wg.close_to_ring();  % 首尾连接形成环路
    ring_wg.center_to_position(0, 0);   % 居中处理
    
    %% ==================== 生成滑轮型耦合总线波导 ====================
    
    % 计算总线波导的弯曲半径（与微环耦合）
    R_bus_couple = para.R_ring + para.gap + para.Wid_bus/2 + para.Wid_ring/2;
    
    % 总线波导参数
    bus_arc_angle = ring_arc_angle;      % 圆弧段角度与微环相同
    bus_cen_angle = deg2rad(options.bus_cen_angle);  % 中间切线角度
    bus_bend_angle = pi - 2*bus_cen_angle;           % 总转过的角度
    bus_euler_angle = bus_bend_angle - bus_arc_angle; % 欧拉段角度
    
    % 总线波导 - 中心弯曲段（欧拉+圆弧+欧拉）
    bus_center_bend = Wcli_wg.Euler_Arc_bend_gen(...
        R_max, ...                   % R_max: 从直线开始
        R_bus_couple, ...            % R_arc: 圆弧段半径
        bus_bend_angle, ...          % total_angle: 总弯曲角度
        bus_euler_angle, ...         % Euler_angle: 欧拉段角度
        N_point, ...
        para.Wid_bus, ...
        para.Wid_bus, ...
        para.etch_angle, ...
        para.h_wg, ...
        bus_cen_angle);
    
    % 总线波导 - 下弯段（对称欧拉弯曲）
    bus_down_bend = Wcli_wg.Euler_sym_bend_gen(...
        R_max, ...
        R_min, ...
        pi/2 - bus_cen_angle, ...
        N_point, ...
        para.Wid_bus, ...
        para.Wid_bus, ...
        para.etch_angle, ...
        para.h_wg, ...
        0);
    bus_down_bend.transform_shape(pi/2);
    bus_down_bend.mirror_translate_shape('y');
    
    % 总线波导 - 上弯段（复制下弯段并镜像）
    bus_up_bend = bus_down_bend.copy();
    bus_up_bend.mirror_translate_shape('x');
    
    % 拼接完整总线波导
    bus_all_wg = bus_center_bend.copy();
    bus_all_wg.merge_and_translate(0, 0, 1, bus_up_bend.flip_shape());
    bus_all_wg.flip_shape();
    bus_all_wg.merge_and_translate(0, 0, 1, bus_down_bend);
    
    % 居中并对齐到微环
    bus_all_wg.center_to_position(0, 0);
    move_dx = ring_wg.get_boundary_xmax - bus_all_wg.get_boundary_xmax + ...
              para.gap + para.Wid_bus;
    bus_all_wg.transform_shape(0, move_dx, 0);
    
    % 添加直段延长
    bus_str_wg = Wcli_wg.Straight_wg_gen(options.bus_str_length, pi/2, ...
                                         para.Wid_bus, para.etch_angle, para.h_wg);
    bus_all_wg.flip_shape();
    bus_all_wg.merge_and_translate(0, 0, 1, bus_str_wg);
    bus_all_wg.flip_shape();
    bus_all_wg.merge_and_translate(0, 0, 1, bus_str_wg.flip_shape());
    
    %% ==================== 生成参数名称 ====================
    para_name = Wcli_wg.generate_save_name(para, 'pulley_rc_ring');
    
end
