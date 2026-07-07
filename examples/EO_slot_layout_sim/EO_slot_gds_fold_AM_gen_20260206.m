clc;
clear;
close all;
scriptPath = '';
if usejava('desktop')
    scriptPath = matlab.desktop.editor.getActiveFilename();    % 尝试从编辑器获取当前活动文件路径（需要 MATLAB Desktop）
end
if isempty(scriptPath)
    scriptPath = mfilename('fullpath');    % 如果没有打开 Desktop，使用 mfilename 获取当前脚本路径
end
[scriptFolder, ~, ~] = fileparts(scriptPath);
cd(scriptFolder); % %切换到当前路径
workspaceRoot = fileparts(fileparts(scriptFolder));
libFolder = fullfile(workspaceRoot, 'lib');
addpath(libFolder);
c_const = 299792458;
GHz = 1e9;
kHz = 1e3;

ns = 1e-9;
us = 1e-6;
MHz = 1e6;
nm = 1e-9;
um = 1e-6;
ms = 1e-3;
cm = 1e-2;
mm = 1e-3;
fobj = gobjects(50, 1);
run_date = datestr(now, 'yyyymmdd');
format long g

%% ==================== 参数扫描配置 ====================
% 定义默认参数（不扫描的参数）- Slot 结构参数
E_para_default = struct(...
    'Gap', 7, ...
    'W_T', 4.5, ...          % Slot 宽度
    'period', 52, ...
    'FF', 0.36, ...         % 填充因子
    'W_S', 62, ...
    'W_G', 168, ...
    'N_ele', 74, ...
    'W_bend', 11, ...
    'gap_bend', 7, ...
    'Euler_angle', 90 ...
);

% Pad 参数
W_G_pad = 84;
L_pad = 180;
tap_len_pad = 420;
W_S_pad = 62;
W_slab = 5;%slab层扩展
W_not_G = 100-4+80-20;
GSG_gap = 20 + W_G_pad/2 + W_S_pad/2;
E_tap_len = 50;  % 电极转弯渐变长度
L_D = 120;       % 微波延迟线

% 定义要扫描的参数（覆盖默认值）
sweep_params = struct();
sweep_params.W_bend = 11;    % 弯曲波导宽度扫描范围
sweep_params.gap_bend = 7;   % 弯曲间隙扫描范围

% 自动生成参数组合
param_combine = Wcli_wg.generate_param_combinations(E_para_default, sweep_params);
sweep_names = fieldnames(sweep_params);

% 获取总的参数组合数
total_combinations = numel(param_combine);
fprintf('总扫描组合数: %d\n', total_combinations);
for i = 1:length(sweep_names)
    param_values = sweep_params.(sweep_names{i});
    fprintf('  %s: %d 个值 [', sweep_names{i}, length(param_values));
    fprintf('%.1f ', param_values);
    fprintf(']\n');
end
fprintf('\n');

%%
for i_d = 1

    %% basic parameter
    N_point = 201;
    
    % 从参数组合中获取当前参数
    E_para = param_combine(i_d);
    
    % 打印当前扫描进度
    fprintf('Progress: %d/%d - ', i_d, total_combinations);
    for i = 1:length(sweep_names)
        fprintf('%s=%.1f ', sweep_names{i}, E_para.(sweep_names{i}));
    end
    fprintf('\n');
    
    % 其他
    supple_wid = 0.12;%波导线宽补偿
    W_wg = 1.2+supple_wid;      % 单模波导宽度
    etch_angle = 70;
    h_wg = 0.25;     % 厚度
    
    %% 画结构 - Slot 电极（公共计算）
    % 计算衍生参数
    W_gap = E_para.Gap+2*E_para.W_T;
    Disp_S = 2*E_para.Gap+4*E_para.W_T + E_para.W_G + E_para.W_S;
    Disp_G = Disp_S * 2;
    Disp_G_to_S = Disp_S / 2;
    tap_ofst = (E_para.W_S - E_para.W_bend)/2 + W_gap - E_para.gap_bend;
    R_inner_G = Disp_G/2 - tap_ofst - E_para.W_G/2;
    L_T_rail = E_para.N_ele * E_para.period;
    
    %% ==================== Fold AM 部分 ====================
    % 波导对象
    Bend_IN_Sele = Wcli_wg.Arc_wg_gen( ...
        Disp_S/2, pi, 0, N_point, E_para.W_bend, E_para.W_bend);
    
    Bend_OUT_Gele = Wcli_poly.create_rect_not("radius", R_inner_G, ...
        "width", W_not_G, "height", E_para.W_G + tap_ofst);

    Bend_IN_Sele.transform_shape(pi/2, Disp_S/2, L_T_rail + E_tap_len);
    Bend_OUT_Gele.transform_shape(pi/2, Disp_G/2 - tap_ofst/2, L_T_rail + E_tap_len);

    % S taper
    S_taper = Wcli_wg.taper_waveguide_gen(E_tap_len, 0, E_para.W_S, E_para.W_bend, 1, 3);
    S_taper.transform_shape(pi/2, Disp_S/2, L_T_rail);
    S_taper_out = S_taper.copy();
    S_taper.merge_and_translate(0, [L_D, -L_D], 0, Bend_IN_Sele, S_taper_out.flip_shape());
    Bend_IN_Sele_tap = S_taper.copy();

    % G taper
    G_taper_in_xy = [Disp_G/2 + E_para.W_G/2, L_T_rail; 
                     Disp_G/2 + E_para.W_G/2, L_T_rail + E_tap_len;
                     Disp_G/2 - E_para.W_G/2 - tap_ofst, L_T_rail + E_tap_len;
                     Disp_G/2 - E_para.W_G/2, L_T_rail];
    G_taper_in = Wcli_poly(G_taper_in_xy);
    G_taper_out = G_taper_in.copy;
    G_taper_out.mirror_translate_shape("x");
    
    %% S 连接 - 使用 Slot_S 结构 (Fold)
    Slot_S_fold = Wcli_poly.create_slot_S(E_para.N_ele, E_para.period, E_para.W_S, E_para.FF, E_para.W_T);
    temp_poly = Slot_S_fold.copy;
    Slot_S_fold.merge_polys(Bend_IN_Sele_tap.to_poly());
    Slot_S_fold.merge_polys(temp_poly);
    Slot_S_fold.align_edge;
    Slot_S_fold.merge_polys(Bend_IN_Sele_tap.to_poly(), 0, 0, 1, 2, 2);
    Slot_S_fold.merge_polys(temp_poly);

    %% G 连接 - 使用 Slot_G 结构 (Fold)
    % G上围输出
    Slot_G_up_fold = Wcli_poly.create_slot_S(E_para.N_ele, E_para.period, E_para.W_G, E_para.FF, E_para.W_T);
    Slot_G_str_in_fold = Slot_G_up_fold.copy;
    Center_cir_G_fold = Wcli_poly.create_semicircle(E_para.W_G/2 + tap_ofst, N_point);
    G_taper_center = Wcli_wg.taper_waveguide_gen(E_tap_len, 0, E_para.W_G, E_para.W_G + tap_ofst*2, 1, 3);
    
    Slot_G_up_fold.merge_polys(G_taper_center.to_poly);
    Slot_G_up_fold.merge_polys_nv(Center_cir_G_fold, "ofs_xy", [L_D, 0], "rm_pts", false);
    Slot_G_up_fold.merge_polys(G_taper_out, 0, 0, 1, 1, 1);
    Slot_G_up_fold.merge_polys_nv(Bend_OUT_Gele, "p1", 2, "p2", 2, "ofs_xy", [-L_D, 0], "rm_pts", false);
    
    % G下围
    Slot_G_down_fold = Wcli_poly.create_slot_G(E_para.N_ele, E_para.period, E_para.W_G, E_para.FF, E_para.W_T);
    Slot_G_str_out_fold = Slot_G_down_fold.copy;
    Slot_G_down_fold.merge_polys(G_taper_in);
    Slot_G_down_fold.merge_polys_nv(Bend_OUT_Gele, "ofs_xy", [L_D, 0], "rm_pts", false);
    Slot_G_down_fold.merge_polys_nv(G_taper_out, "p1", 2, "p2", 2, "ofs_xy", [-L_D, 0], "rm_pts", false);
    Slot_G_down_fold.align_edge;
    Slot_G_down_fold.merge_polys(Slot_G_str_in_fold, 0, 0, 1, 2, 1);
    Slot_G_down_fold.merge_polys(G_taper_center.to_poly);
    Slot_G_down_fold.merge_polys_nv(Center_cir_G_fold, "ofs_xy", [-L_D, 0], "rm_pts", false);

    Slot_G_up_fold.merge_polys_nv(G_taper_in, "p1", 2, "p2", 2, "ofs_xy", [L_D, 0], "rm_pts", false);
    Slot_G_up_fold.merge_polys(Slot_G_str_out_fold, 0, 0, 1, 2, 2);

    %% 画结构-调制和交叉波导（Fold）
    cross_ch1 = Wcli_wg.cross_wg_gen("Wid_inout", W_wg);
    cross_ch1.transform_shape(pi/4);
    R_max = 2000;
    re_dispy_in = (E_para.W_G + W_gap - cross_ch1.get_port_dy)/2;
    
    [in1_wg_bend, ~] = Wcli_wg.Euler_arc_bend_Rmid_dy( ...
        R_max, re_dispy_in, pi/4, pi/8, N_point, W_wg, W_wg, etch_angle, h_wg, 0);
    in1_wg_bend.flip_shape();
    cross_ch1.flip_shape();
    cross_ch1.merge_and_translate(0, 0, 1, in1_wg_bend);
    
    re_dispy_out = Disp_S - abs(cross_ch1.get_port_dy);
    [out1_wg_bend, ~] = Wcli_wg.Euler_arc_bend_Rmid_dy( ...
        R_max, re_dispy_out, pi/4*3, pi/8*3, N_point, W_wg, W_wg, etch_angle, h_wg, pi/4);
    cross_ch1.flip_shape();
    cross_ch1.merge_and_translate(0, 0, 1, out1_wg_bend);
    cross_horiz_bend = cross_ch1.copy;
    cross_temp = cross_ch1.copy;
    cross_horiz_bend.mirror_translate_shape("y");
    bend_portdx = abs(cross_horiz_bend.get_port_dx);

    cross_ch1.align_port_in([L_T_rail, -W_gap/2 - E_para.W_G/2]);
    cross_ch1.merge_and_translate(-L_T_rail - bend_portdx, 0, 1, cross_horiz_bend.flip_shape);
    
  
    cross_ch2 = cross_ch1.copy;
    cross_ch2.mirror_translate_shape("x");
    cross_ch2.mirror_translate_shape("y");

    % 前后连接MMI (Fold)
    heater_length = 900;
    heater_wid = 13;
    heater_gap = 3;
    spac_ht_ele = 100 + E_tap_len + L_D + R_inner_G + W_not_G;
    mmi1x2 = Wcli_wg.mmi_1x2_half_gen("fanout_spac", W_gap + E_para.W_S, "Win", W_wg, "Wout", W_wg);
    mmi_out1 = mmi1x2.copy;
    mmi_out1.mirror_translate_shape('y');
    cross_ch1.merge_and_translate(heater_length + bend_portdx + spac_ht_ele + L_T_rail, 0, 1, mmi_out1);
    mmi_out2 = mmi1x2.copy;
    mmi_out2.transform_shape(pi);
    cross_ch2.flip_shape;
    cross_ch2.merge_and_translate(heater_length + L_T_rail + spac_ht_ele, 0, 1, mmi_out2.flip_shape);

    cross_ch2.flip_shape;
    mmi_in2 = mmi1x2.copy;
    mmi_in2.mirror_translate_shape('x');
    cross_ch2.merge_and_translate(-L_T_rail - bend_portdx, 0, 1, mmi_in2);
    mmi_in1 = mmi1x2.copy;
    cross_ch1.flip_shape;
    cross_ch1.merge_and_translate(-L_T_rail, 0, 1, mmi_in1.flip_shape);
    cross_ch2.align_port_in(cross_ch1.get_port_inxy);
    
    % heater (Fold)
    mmi_dx = mmi_in1.get_boundary_dx;
    fold_heater_down = Wcli_wg.Straight_wg_gen(heater_length, 0, heater_wid);
    fold_heater_down.move_to("topright", cross_ch1.get_align_point("topright") + [-mmi_dx, -W_wg - heater_gap]);
    fold_heater_down.transform_shape(0,0,-W_gap-E_para.W_S);

    % 添加开窗层 (Single heater) - Layer 3
    window_extend = 5;  % 延展量 (μm)
    fold_heater_win_down = Wcli_wg.Straight_wg_gen(heater_length + 2*window_extend, 0, heater_wid + 2*window_extend);
    fold_heater_down.align_poly(fold_heater_win_down, 'cen');
    %上面的heater
    fold_heater_up = fold_heater_down.copy;
    fold_heater_up.transform_shape(0,0,2*heater_gap+W_wg+heater_wid);
    fold_heater_win_up = fold_heater_win_down.copy;
    fold_heater_up.align_poly(fold_heater_win_up, 'cen');
    %增加slab延展，提高热接触
    heater_slab = Wcli_wg.Straight_wg_gen(heater_length,0,W_wg+2*heater_gap+2*heater_wid);
    fold_heater_cell = Wcli_circuit({fold_heater_down,fold_heater_up, fold_heater_win_down,fold_heater_win_up}, ...
                                        "laycells", [4,4, 3,3], "name", 'fold_heater_with_window');
    fold_heater_cell.align_obj(heater_slab,"cen");
    fold_heater_cell.add_cell(heater_slab,1);
    % 接GSG pad (Fold)

    str_len_pad = E_tap_len + L_D + R_inner_G + W_not_G;
    S_tap_pad_fold = Wcli_poly.create_quad(start_pos = [0, 0], end_pos = [tap_len_pad, 0], ...
        start_width = W_S_pad, end_width = E_para.W_S);
    G_pad_fold = Wcli_poly.create_rect("len", L_pad, "height", W_G_pad);
    S_pad_fold = Wcli_poly.create_rect("len", L_pad, "height", W_S_pad);
    Slot_S_fold.merge_polys_nv(S_tap_pad_fold, "ofs_xy", [-str_len_pad, 0], "p1", 1, "p2", 2);
    Slot_S_fold.merge_polys_nv(S_pad_fold, "p1", 2, "p2", 2);

    y_ofs = Disp_G_to_S - GSG_gap;
    G_tap_pad_down_fold = Wcli_poly.create_quad(start_pos = [0, 0], end_pos = [tap_len_pad, -y_ofs], ...
        start_width = W_G_pad, end_width = E_para.W_G);
    Slot_G_down_fold.merge_polys_nv(G_tap_pad_down_fold, "ofs_xy", [-str_len_pad, 0], "p1", 1, "p2", 2);
    Slot_G_down_fold.merge_polys_nv(G_pad_fold, "p1", 2, "p2", 2);

    y_ofs = Disp_G_to_S + Disp_G/2 - GSG_gap;
    G_tap_pad_up_fold = Wcli_poly.create_quad(start_pos = [0, 0], end_pos = [tap_len_pad, -y_ofs], ...
        start_width = W_G_pad, end_width = E_para.W_G + Disp_G);
    G_tap_pad_up_fold.mirror_translate_shape("x");
    G_tap_pad_up_fold.merge_polys_nv(G_pad_fold, "p1", 1, "p2", 2);
    G_tap_pad_up_fold.align_port("port_idx", 2, "tar_xy", Slot_S_fold.get_port_xy(2) + [0, GSG_gap]);

    % 接终端电阻 (Fold)
    E_para_supp = E_para;
    E_para_supp.N_ele = 12;
    GSG_supple = Wcli_poly.create_slot_AM_electrode("E_para", E_para_supp);
    GSG_supple.move_to("cleft", Slot_S_fold.get_port_xy(1));
    res_cell = Wcli_poly.create_termination_resistor();
    res_cell.move_to("cleft", GSG_supple.get_align_point("cright"));

    %波导层单独处理-slab延拓
    cross_ch1_ext = cross_ch1.copy;
    cross_ch1_ext.set_width_list(cross_ch1_ext.width_list+W_slab*2);
    cross_ch2_ext = cross_ch2.copy;
    cross_ch2_ext.set_width_list(cross_ch2_ext.width_list+W_slab*2);
    
    % 建立 circuit (Fold)
    gdscell = {Slot_S_fold, Slot_G_up_fold, Slot_G_down_fold, ...
               cross_ch1, cross_ch2,cross_ch1_ext,cross_ch2_ext, G_tap_pad_up_fold};
    slot_fold_gdscell = Wcli_circuit(gdscell, "laycells", [5, 5, 5, 10, 10,1,1, 5], "name", 'slot_fold');
    slot_fold_gdscell.merge_cell(GSG_supple);
    slot_fold_gdscell.merge_cell(res_cell);
    slot_fold_gdscell.merge_cell(fold_heater_cell);
    
    %% ==================== Single AM 部分 ====================
    % S 电极 (Single)
    Slot_S_single = Wcli_poly.create_slot_S(E_para.N_ele, E_para.period, E_para.W_S, E_para.FF, E_para.W_T);
    Slot_S_single.move_to("cleft");

    % G 电极 (Single)
    Slot_G_down_single = Wcli_poly.create_slot_G(E_para.N_ele, E_para.period, E_para.W_G, E_para.FF, E_para.W_T);
    Slot_G_down_single.transform_shape(0, 0, -Disp_S/2);
    
    Slot_G_up_single = Wcli_poly.create_slot_G(E_para.N_ele, E_para.period, E_para.W_G, E_para.FF, E_para.W_T);
    Slot_G_up_single.mirror_translate_shape('x');
    Slot_G_up_single.transform_shape(0, 0, Disp_S/2);
    
    % 调制臂 (Single)
    in_wg_single = Wcli_wg.Straight_wg_gen(15, 0, W_wg, etch_angle, h_wg);
    mmi1x2_single = Wcli_wg.mmi_1x2_half_gen("fanout_spac", W_gap + E_para.W_S, "Win", W_wg, "Wout", W_wg);
    
    mmi_out_single = mmi1x2_single.copy;
    mmi_out_single.mirror_translate_shape('y');

    % 上调制臂
    mod_arm_up = mmi1x2_single.copy;
    mod_arm_up.align_port_in([-mod_arm_up.get_boundary_dx, 0]);
    mod_arm_up.merge_and_translate(Slot_G_down_single.get_boundary_dx + heater_length + spac_ht_ele, 0, 1, mmi_out_single);

    % 下调制臂
    mod_arm_down = mod_arm_up.copy;
    mod_arm_down.mirror_translate_shape("x");
    
    % heater (Single)
    single_heater = fold_heater_down.copy;
    single_heater.move_to("topright", mod_arm_up.get_align_point("topright") + [-mmi_dx, -W_wg - heater_gap]);
    single_heater.transform_shape(0,0,-W_gap-E_para.W_S);

    single_heater_cell = fold_heater_cell.copy;
    single_heater_cell.move_to("cright", mod_arm_up.get_port_outxy + [-mmi_dx+window_extend, 0]);
    single_heater_cell.transform_shape(0,0,-W_gap/2-E_para.W_S/2);

    % 接GSG pad (Single)
    S_tap_pad = Wcli_poly.create_quad(start_pos = [0, 0], end_pos = [tap_len_pad, 0], ...
        start_width = W_S_pad, end_width = E_para.W_S);
    G_pad = Wcli_poly.create_rect("len", L_pad, "height", W_G_pad);
    S_pad = Wcli_poly.create_rect("len", L_pad, "height", W_S_pad);
    Slot_S_single.merge_polys_nv(S_tap_pad, "ofs_xy", [-str_len_pad, 0], "p1", 1, "p2", 2);
    Slot_S_single.merge_polys_nv(S_pad, "p1", 2, "p2", 2);

    y_ofs = Disp_G_to_S - GSG_gap;
    G_tap_pad_down = Wcli_poly.create_quad(start_pos = [0, 0], end_pos = [tap_len_pad, -y_ofs], ...
        start_width = W_G_pad, end_width = E_para.W_G);
    Slot_G_down_single.merge_polys_nv(G_tap_pad_down, "ofs_xy", [-str_len_pad, 0], "p1", 1, "p2", 2);
    Slot_G_down_single.merge_polys_nv(G_pad, "p1", 2, "p2", 2);

    G_tap_pad_up = G_tap_pad_down.copy;
    G_tap_pad_up.mirror_translate_shape("x");
    Slot_G_up_single.merge_polys_nv(G_tap_pad_up, "ofs_xy", [-str_len_pad, 0], "p1", 1, "p2", 2);
    Slot_G_up_single.merge_polys_nv(G_pad, "p1", 2, "p2", 2);
    
    % 接终端电阻 (Single)
    GSG_supple.move_to("cleft", Slot_S_single.get_port_xy(1));
    res_cell.move_to("cleft", GSG_supple.get_align_point("cright"));
    % 建立 gdscell (Single)
    % 波导层单独处理-slab延拓
    mod_arm_up_ext = mod_arm_up.copy;
    mod_arm_up_ext.set_width_list(mod_arm_up_ext.width_list + W_slab*2);
    mod_arm_down_ext = mod_arm_down.copy;
    mod_arm_down_ext.set_width_list(mod_arm_down_ext.width_list + W_slab*2);
    
    gdscell = {Slot_S_single, Slot_G_up_single, Slot_G_down_single, ...
                mod_arm_up.to_poly, mod_arm_down.to_poly, mod_arm_up_ext.to_poly, mod_arm_down_ext.to_poly};
    slot_single_gdscell = Wcli_circuit(gdscell, "laycells", [5, 5, 5, 10, 10, 1, 1], "name", 'slot_single');
    slot_single_gdscell.merge_cell(GSG_supple);
    slot_single_gdscell.merge_cell(single_heater_cell);
    slot_single_gdscell.merge_cell(res_cell);
    
    %% PM Fold 部分 ====================
    % 修改 PM 专用参数 - 增加 25 个周期
    E_para_PM = E_para;
    add_N_period=25;
    E_para_PM.N_ele = E_para.N_ele + add_N_period;  % 增加 25 个周期
    L_T_rail_PM = E_para_PM.N_ele * E_para_PM.period;  % 重新计算电极长度
    
    % 重新生成 PM 专用的电极结构（不复用 Fold AM）
    % S 电极 (PM Fold)
    Slot_S_PM = Wcli_poly.create_slot_S(E_para_PM.N_ele, E_para_PM.period, ...
        E_para_PM.W_S, E_para_PM.FF, E_para_PM.W_T);
    Bend_IN_Sele_tap_PM = S_taper.copy();  % 复用弯曲 taper（因为几何形状相同）
    temp_poly_PM = Slot_S_PM.copy;
    Slot_S_PM.merge_polys(Bend_IN_Sele_tap_PM.to_poly());
    Slot_S_PM.merge_polys(temp_poly_PM);
    Slot_S_PM.align_edge;
    Slot_S_PM.merge_polys(Bend_IN_Sele_tap_PM.to_poly(), 0, 0, 1, 2, 2);
    Slot_S_PM.merge_polys(temp_poly_PM);
    
    % G 上围电极 (PM Fold)
    Slot_G_up_PM = Wcli_poly.create_slot_S(E_para_PM.N_ele, E_para_PM.period, ...
        E_para_PM.W_G, E_para_PM.FF, E_para_PM.W_T);
    Slot_G_str_in_PM = Slot_G_up_PM.copy;
    Center_cir_G_PM = Wcli_poly.create_semicircle(E_para_PM.W_G/2 + tap_ofst, N_point);
    G_taper_center_PM = Wcli_wg.taper_waveguide_gen(E_tap_len, 0, E_para_PM.W_G, ...
        E_para_PM.W_G + tap_ofst*2, 1, 3);
    
    Slot_G_up_PM.merge_polys(G_taper_center_PM.to_poly);
    Slot_G_up_PM.merge_polys_nv(Center_cir_G_PM, "ofs_xy", [L_D, 0], "rm_pts", false);
    Slot_G_up_PM.merge_polys(G_taper_out, 0, 0, 1, 1, 1);
    Slot_G_up_PM.merge_polys_nv(Bend_OUT_Gele, "p1", 2, "p2", 2, "ofs_xy", [-L_D, 0], "rm_pts", false);
    
    % G 下围电极 (PM Fold)
    Slot_G_down_PM = Wcli_poly.create_slot_G(E_para_PM.N_ele, E_para_PM.period, ...
        E_para_PM.W_G, E_para_PM.FF, E_para_PM.W_T);
    Slot_G_str_out_PM = Slot_G_down_PM.copy;
    Slot_G_down_PM.merge_polys(G_taper_in);
    Slot_G_down_PM.merge_polys_nv(Bend_OUT_Gele, "ofs_xy", [L_D, 0], "rm_pts", false);
    Slot_G_down_PM.merge_polys_nv(G_taper_out, "p1", 2, "p2", 2, "ofs_xy", [-L_D, 0], "rm_pts", false);
    Slot_G_down_PM.align_edge;
    Slot_G_down_PM.merge_polys(Slot_G_str_in_PM, 0, 0, 1, 2, 1);
    Slot_G_down_PM.merge_polys(G_taper_center_PM.to_poly);
    Slot_G_down_PM.merge_polys_nv(Center_cir_G_PM, "ofs_xy", [-L_D, 0], "rm_pts", false);
    
    Slot_G_up_PM.merge_polys_nv(G_taper_in, "p1", 2, "p2", 2, "ofs_xy", [L_D, 0], "rm_pts", false);
    Slot_G_up_PM.merge_polys(Slot_G_str_out_PM, 0, 0, 1, 2, 2);
    
    % 重新创建交叉波导 (PM Fold) - 使用新的电极长度
    cross_ch1_PM = cross_temp.copy;
    
    % 计算 MMI 等效长度 (保持相同的光程)
    mmi_equiv_length_PM = mmi_in1.get_boundary_dx;
    
    % 创建直波导替代 MMI (根据新的电极长度调整)
    % 输入直波导 (替代 mmi_in1 和 mmi_in2)
    straight_in1_PM = Wcli_wg.Straight_wg_gen(mmi_equiv_length_PM, 0, W_wg, etch_angle, h_wg);
    straight_in1_PM.transform_shape(0, 0, (W_gap + E_para_PM.W_S)/2);
    
    straight_in2_PM = Wcli_wg.Straight_wg_gen(mmi_equiv_length_PM, 0, W_wg, etch_angle, h_wg);
    straight_in2_PM.transform_shape(0, 0, -(W_gap + E_para_PM.W_S)/2);
    
    % 输出直波导 (替代 mmi_out1 和 mmi_out2)
    straight_out1_PM = Wcli_wg.Straight_wg_gen(mmi_equiv_length_PM, 0, W_wg, etch_angle, h_wg);
    straight_out1_PM.transform_shape(0, 0, (W_gap + E_para_PM.W_S)/2);
    
    straight_out2_PM = Wcli_wg.Straight_wg_gen(mmi_equiv_length_PM, 0, W_wg, etch_angle, h_wg);
    straight_out2_PM.transform_shape(0, 0, -(W_gap + E_para_PM.W_S)/2);
    
    % 连接直波导到交叉波导 (PM Fold) - 使用新的电极长度
    % 上臂 (cross_ch1_PM)
    cross_ch1_PM.align_port_in([L_T_rail_PM,-W_gap/2-E_para_PM.W_G/2]);
    cross_ch1_PM.merge_and_translate(-L_T_rail_PM - bend_portdx, 0, 1, cross_horiz_bend);
    cross_ch1_PM.merge_and_translate(bend_portdx + L_T_rail_PM, 0, 1, straight_out1_PM);  % 使用 L_T_rail_PM
    cross_ch1_PM.flip_shape;
    cross_ch1_PM.merge_and_translate(-L_T_rail_PM, 0, 1, straight_in1_PM.flip_shape);  % 使用 L_T_rail_PM
    
    % 下臂 (cross_ch2_PM)
    cross_ch2_PM = cross_ch1_PM.copy;
    cross_ch2_PM.mirror_translate_shape("x");
    cross_ch2_PM.mirror_translate_shape("y");
    cross_ch2_PM.align_port_in(cross_ch1_PM.get_port_outxy - [0, W_gap + E_para_PM.W_S]);
    
    % 前后各补一段 - 使用 PM 专用的电极参数
    E_para_supp_PM = E_para_PM;
    E_para_supp_PM.N_ele = 10;
    GSG_supple_PM_end = Wcli_poly.create_slot_AM_electrode("E_para", E_para_supp_PM);
    GSG_supple_PM_begin = GSG_supple_PM_end.copy;
    GSG_supple_PM_end.move_to("cleft", Slot_S_PM.get_port_xy(2));
    GSG_supple_PM_begin.move_to("cright", Slot_S_PM.get_port_xy(1));
    
    % 接GSG pad (PM Fold)-左右两边都得有pad渐变
    % 接GSG pad (Fold)
    tap_len_pad = 1500;%右边长度变一下
    L_pad = 1000;
    G_pad_right = Wcli_poly.create_rect("len", L_pad, "height", W_G_pad);
    S_pad_right = Wcli_poly.create_rect("len", L_pad, "height", W_S_pad);
    S_tap_pad_fold_right = Wcli_poly.create_quad(start_pos = [0, 0], end_pos = [tap_len_pad, 0], ...
        start_width = W_S_pad, end_width = E_para.W_S);
    y_ofs = Disp_G_to_S - GSG_gap;
    G_tap_pad_up_right = Wcli_poly.create_quad(start_pos = [0, 0], end_pos = [tap_len_pad, -y_ofs], ...
        start_width = W_G_pad, end_width = E_para.W_G);
%     G_tap_pad_up_right.mirror_translate_shape("x");
    y_ofs = Disp_G_to_S + Disp_G/2 - GSG_gap;
    G_tap_pad_down_right = Wcli_poly.create_quad(start_pos = [0, 0], end_pos = [tap_len_pad, -y_ofs], ...
        start_width = W_G_pad, end_width = E_para.W_G + Disp_G);
    G_tap_pad_down_right.mirror_translate_shape("x");
    G_tap_pad_down_right.merge_polys_nv(G_pad_right, "p1", 1, "p2", 2);
    G_tap_pad_down_right.transform_shape(pi);

    G_tap_pad_up_left = G_tap_pad_up_fold.copy;
    G_tap_pad_down_left = G_tap_pad_down_fold.copy;
    S_tap_pad_fold_left = S_tap_pad_fold.copy;
    G_tap_pad_down_left.transform_shape(pi);
    Slot_S_PM.merge_polys_nv(S_tap_pad_fold_left, "ofs_xy", [-str_len_pad, 0], "p1", 1, "p2", 2);
    Slot_S_PM.merge_polys_nv(S_pad_fold, "p1", 2, "p2", 2);
    Slot_S_PM.merge_polys_nv(S_tap_pad_fold_right, "ofs_xy", [str_len_pad, 0], "p1", 1, "p2", 2);
    Slot_S_PM.merge_polys_nv(S_pad_right, "p1", 2, "p2", 2);
    
    Slot_G_up_PM.merge_polys_nv(G_tap_pad_up_right, "ofs_xy", [str_len_pad, 0], "p1", 2, "p2", 2);
    Slot_G_up_PM.merge_polys_nv(G_pad_right, "p1", 2, "p2", 2);
    Slot_G_down_PM.merge_polys_nv(G_tap_pad_down_left, "ofs_xy", [-str_len_pad, 0], "p1", 1, "p2", 2);
    Slot_G_down_PM.merge_polys_nv(G_pad_fold, "p1", 2, "p2", 2);
    Slot_G_up_PM.get_align_point("botright");
    G_tap_pad_down_right.move_to("botleft",Slot_G_down_PM.get_align_point("botright"));
    
        % 波导层单独处理-slab延拓 (PM Fold)
        cross_ch1_PM_ext = cross_ch1_PM.copy;
        cross_ch1_PM_ext.set_width_list(cross_ch1_PM_ext.width_list + W_slab*2);
        cross_ch2_PM_ext = cross_ch2_PM.copy;
        cross_ch2_PM_ext.set_width_list(cross_ch2_PM_ext.width_list + W_slab*2);
        
        % 建立 circuit (PM Fold)
        gdscell_PM = {Slot_S_PM, Slot_G_up_PM, Slot_G_down_PM, ...
                      cross_ch1_PM.to_poly, cross_ch2_PM.to_poly, ...
                      cross_ch1_PM_ext.to_poly, cross_ch2_PM_ext.to_poly, ...
                      G_tap_pad_up_left, G_tap_pad_down_right};
        slot_PM_fold_gdscell = Wcli_circuit(gdscell_PM, "laycells", [5, 5, 5, 10, 10, 1, 1, 5, 5], "name", 'slot_PM_fold');
        slot_PM_fold_gdscell.merge_cell(GSG_supple_PM_end);
        slot_PM_fold_gdscell.merge_cell(GSG_supple_PM_begin);
end

%% 画图
for plot = []
    figure(1);
    clf;
    hold on;
    
    % 绘制 Fold AM、Single AM 和 PM Fold 电路
    slot_fold_gdscell.plot_circuit();
    slot_single_gdscell.plot_circuit();
    slot_PM_fold_gdscell.plot_circuit();
    
    axis equal;
    title('Slot Fold AM + Single AM + PM Fold Structures (v20251223)');
    legend('Fold AM', 'Single AM', 'PM Fold');
    hold off;
end

%% gds - 合并输出
para_name = Wcli_wg.generate_save_name(E_para, 'Slot_fold_single_PM');

for outgds = [1]
    gds_folder = ['gds_gen_slot', run_date];
    FileDc = strcat(scriptFolder, '\', gds_folder, '\', para_name, '.gds');
    
    % 合并三个电路 (垂直排列)
    % Fold AM 在底部 (y=0)
    % Single AM 在中间 (y=800)
    slot_fold_gdscell.merge_cell(slot_single_gdscell, "self_pos", "cleft", "target_pos", "cleft", "Txy", [0, 800]);
    % PM Fold 在顶部 (y=1600)
    slot_fold_gdscell.merge_cell(slot_PM_fold_gdscell, "self_pos", "cleft", "target_pos", "cleft", "Txy", [0, 1400]);
    
    % 生成 GDS
%     slot_fold_gdscell.generate_gds(FileDc, para_name);
    slot_fold_gdscell.generate_gds(FileDc, 'wcli_slot_mod');
    fprintf('gds finish! (包含 Fold AM + Single AM + PM Fold)\n'); 
    
    % 转换为 GDSII 二进制格式
    gdsII_FileDc = strcat(scriptFolder, '\', gds_folder, '\ii_', para_name, '.gds');
    Wcli_poly.klayout_gds2gdsii(FileDc, gdsII_FileDc);
    Wcli_poly.klayout_gds_subtract(gdsII_FileDc, 'output_gds',gdsII_FileDc);
end
