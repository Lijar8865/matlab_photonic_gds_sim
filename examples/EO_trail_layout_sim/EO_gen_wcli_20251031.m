clc;
clear;
close all;
addpath("C:\Program Files\Lumerical\v252\api\matlab");
scriptPath = '';
if usejava('desktop')
    scriptPath = matlab.desktop.editor.getActiveFilename();
end
if isempty(scriptPath)
    scriptPath = mfilename('fullpath');
end
% open(scriptPath);
[scriptFolder, ~, ~] = fileparts(scriptPath);
cd(scriptFolder); % %切换到当前路径

% 可手动指定库路径；留空时自动从当前脚本位置向上查找
customLibFolder = '';

if ~isempty(customLibFolder)
    libFolder = customLibFolder;
else
    candidateRoots = {
        fileparts(fileparts(scriptFolder)), ...
        fileparts(scriptFolder), ...
        scriptFolder ...
        };
    libFolder = '';
    for i_root = 1:numel(candidateRoots)
        candidateLib = fullfile(candidateRoots{i_root}, 'lib');
        if exist(candidateLib, 'dir')
            libFolder = candidateLib;
            break;
        end
    end
    if isempty(libFolder)
        error('未找到 lib 目录。请设置 customLibFolder，或将脚本放在包含 lib 的工作区附近。');
    end
end
addpath(libFolder);%库函数路径

requiredHfssFiles = {
    'T_rail_bend.py', ...
    'T_rail_TWE_GSG_base.aedt', ...
    'hfss_utils.py', ...
    'Export_data.py' ...
    };
for i_file = 1:numel(requiredHfssFiles)
    requiredPath = fullfile(scriptFolder, requiredHfssFiles{i_file});
    if ~exist(requiredPath, 'file')
        error('缺少当前工程的 HFSS 资源文件: %s', requiredPath);
    end
end
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
% run_date = '20251102';
format long g
%% ==================== 参数扫描配置 ====================
% 定义默认参数（不扫描的参数）
E_para_default = struct( ...
    'Gap', 8, ...
    'W_rail', 4.2, ...
    'W_T', 2.8, ...
    'L_rail', 8, ...
    'period', 54, ...
    'L_T', 32, ...
    'W_S', 82, ...
    'W_G', 132, ...
    'N_ele', 8, ...
    'W_bend', 12, ...
    'gap_bend', 7, ...
    'Euler_angle', 90, ...
    'T_flag', 0 ...
);

% 定义要扫描的参数（覆盖默认值）
sweep_params = struct();
sweep_params.W_bend = 12;  % 弯曲波导宽度扫描范围
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

% for i_d = 1:total_combinations
for i_d = 1

    %% basic parameter
    N_point = 201;
    
    % 从参数组合中获取当前参数
    E_para = param_combine(i_d);

    E_tap_len = 50;
    W_bend = E_para.W_bend;      % 从扫描参数中获取
    gap_bend = E_para.gap_bend;  % 从扫描参数中获取
    
    fprintf('Progress: %d/%d - ', i_d, total_combinations);
    for i = 1:length(sweep_names)
        fprintf('%s=%.1f ', sweep_names{i}, E_para.(sweep_names{i}));
    end
    fprintf('\n');
    
    
    %% 画结构
    Disp_G = (2*E_para.Gap+4*E_para.W_rail+4*E_para.W_T+E_para.W_G+E_para.W_S)*2; % 目标侧向位移 (dy)
    Disp_S = 2*E_para.Gap+4*E_para.W_rail+4*E_para.W_T+E_para.W_G+E_para.W_S; % 目标侧向位移 (dy)
    W_gap =E_para.Gap+2*E_para.W_rail+2*E_para.W_T;
    tap_ofst = (E_para.W_S-W_bend)/2+W_gap-gap_bend;
    Disp_IN = E_para.W_G+W_gap;
    Disp_OUT = E_para.W_G+W_gap*3+2*E_para.W_S;
    Bend_IN_Sele= Wcli_wg.Arc_wg_gen( ...
                Disp_S/2, ... % 圆弧半径
                pi, ... % 圆弧角度
                0, ... % 初始角度
                N_point, ... % 生成点数
                W_bend, ... % 输入宽度
                W_bend ... % 输出宽度;
                );
    Bend_OUT_Gele= Wcli_wg.Arc_wg_gen( ...
                Disp_G/2-tap_ofst/2, ... % 圆弧半径
                pi, ... % 圆弧角度
                0, ... % 初始角度
                N_point, ... % 生成点数
                E_para.W_G+tap_ofst, ... % 输入宽度
                E_para.W_G+tap_ofst ... % 输出宽度;
                );
    L_T_rail = E_para.N_ele*E_para.period*E_para.T_flag;%flag为1的时候才带上T电极
    Bend_IN_Sele.transform_shape(pi/2,Disp_S/2,L_T_rail+E_tap_len);
    Bend_OUT_Gele.transform_shape(pi/2,Disp_G/2-tap_ofst/2,L_T_rail+E_tap_len);

    T_rail_S_ele_R = Wcli_poly.create_T_rail_S(E_para.N_ele, E_para.period, E_para.W_S, E_para.W_rail, E_para.L_rail, E_para.W_T, E_para.L_T);
    T_rail_S_ele_L = T_rail_S_ele_R.copy;
    T_rail_S_ele_R.transform_shape(pi/2,Disp_S/2,0);
    T_rail_S_ele_L.transform_shape(pi/2,-Disp_S/2,0);
    T_rail_S_ele_R_xy = T_rail_S_ele_R.postohfss2d;
    T_rail_S_ele_L_xy = T_rail_S_ele_L.postohfss2d;

    T_rail_G_center = Wcli_poly.create_T_rail_S(E_para.N_ele, E_para.period, E_para.W_G, E_para.W_rail, E_para.L_rail, E_para.W_T, E_para.L_T);
    T_rail_G_center.transform_shape(pi/2,0,0);
    T_rail_G_center_xy = T_rail_G_center.postohfss2d;

    T_rail_G_ele_R = Wcli_poly.create_T_rail_G(E_para.N_ele, E_para.period, E_para.W_G, E_para.W_rail, E_para.L_rail, E_para.W_T, E_para.L_T);
    T_rail_G_ele_L = T_rail_G_ele_R.copy;
    T_rail_G_ele_R.transform_shape(pi/2,Disp_G/2,0);
    T_rail_G_ele_L.mirror_translate_shape('x');
    T_rail_G_ele_L.transform_shape(pi/2,-Disp_G/2,0);
    T_rail_G_ele_R_xy = T_rail_G_ele_R.postohfss2d;
    T_rail_G_ele_L_xy = T_rail_G_ele_L.postohfss2d;

    Center_G_ele = Wcli_poly.create_semicircle(E_para.W_G/2+tap_ofst,N_point);
    Center_G_ele.transform_shape(pi/2,0,L_T_rail+E_tap_len);
    Center_G_ele_xy = Center_G_ele.postohfss2d;

    S_taper = Wcli_wg.taper_waveguide_gen(E_tap_len,0,E_para.W_S,W_bend,1,3);
    S_taper.transform_shape(pi/2,Disp_S/2,L_T_rail);
    S_taper_out = S_taper.copy();%输出的taper
    S_taper.merge_and_translate(0,0,1,Bend_IN_Sele,S_taper_out.flip_shape());
    Bend_IN_Sele_tap = S_taper.copy();

    G_taper_in_xy = [Disp_G/2+E_para.W_G/2,L_T_rail;Disp_G/2+E_para.W_G/2,L_T_rail+E_tap_len;...
        Disp_G/2-E_para.W_G/2-tap_ofst,L_T_rail+E_tap_len;Disp_G/2-E_para.W_G/2,L_T_rail;...
        Disp_G/2+E_para.W_G/2,L_T_rail];
    G_taper_out_xy = [-G_taper_in_xy(:,1),G_taper_in_xy(:,2)];
    G_taper_in_xy = round(G_taper_in_xy*1e3);
    G_taper_out_xy = round(G_taper_out_xy*1e3);

    G_taper_center = Wcli_wg.taper_waveguide_gen(E_tap_len,0,E_para.W_G,E_para.W_G+tap_ofst*2,1,3);
    G_taper_center.transform_shape(pi/2,0,L_T_rail);
% G_taper_center.plot_wg_pos
%计算总长度
    L_all = L_T_rail+E_tap_len+max(Bend_OUT_Gele.get_boundary_ymax)+50;%加50余量
    %% put HFSS
    HFSS_save_folder = ['F:\HFSS_data\T_rail_sw',run_date];
    para_name = Wcli_wg.generate_save_name(E_para, 'sw');
    json_struct.save_folder = fullfile(HFSS_save_folder,para_name);
    json_struct.scriptFolder = scriptFolder;
    json_struct.Disp_S = Disp_S;
    json_struct.Disp_G = Disp_G;
    json_struct.T_rail_S_R = T_rail_S_ele_R_xy;
    json_struct.T_rail_S_L = T_rail_S_ele_L_xy;
    json_struct.T_rail_G_center = T_rail_G_center_xy;
    json_struct.T_rail_G_R = T_rail_G_ele_R_xy;
    json_struct.T_rail_G_L = T_rail_G_ele_L_xy;

    json_struct.Bend_G_ele = Bend_OUT_Gele.postohfss2d;
    json_struct.Bend_S_ele = Bend_IN_Sele_tap.postohfss2d;
    json_struct.Center_G_ele = Center_G_ele_xy;

    json_struct.G_taper_in = G_taper_in_xy;
    json_struct.G_taper_out = G_taper_out_xy;
    json_struct.G_taper_center = G_taper_center.postohfss2d;
    json_struct.L = L_all;
    json_struct = Wcli_wg.merge_two_structs(json_struct,E_para);
    json_struct.open_py = 'T_rail_bend.py';
    json_struct.extract_py = 'Export_data.py';

%     machine_select = 'digital:-1:8:90%:1';
    machine_select = 'blueold2:-1:9:90%:1';
%     machine_select = 'noblue:-1:9:90%:1';
    Wcli_wg.put_HFSS(json_struct, 'run_flag',0,'machine_select',machine_select);
%     Wcli_wg.save_para_file(json_struct);
%     Wcli_wg.ext_only_HFSS(json_struct);
    clear json_struct;%这里要清除掉，否则会因为merge_two_structs函数导致变量不更新，这样很糟糕
end
% Euler_G_ele.plot_wg_pos
%% gds

for outgds = []
    gds_folder = ['gds_gen', run_date]; % %定义变量
    FileDc = strcat(scriptFolder, '\', gds_folder, '\', para_name, '.gds');
    %     Spiral_1_connect.generate_gds(FileDc, 2, save_name);
    %     Waveguide_Str.generate_multi_gds({Spiral_1_connect, bus_input_str,Edge_taper_1,Edge_taper_2}, FileDc, 174, ...
    %         {'ring_spiral', 'bus_wg','Edge_taper_1','Edge_taper_2'}, save_name);
    Wcli_wg.generate_multi_flatten_gds({Spiral_1_connect}, FileDc, 8, ...
        'ajmd_spiral', 'ajmd_spiral');
    fprintf('gds finish!\n');
    gdsII_FileDc = strcat(scriptFolder, '\', gds_folder, '\ii_', para_name, '.gds');
    Wcli_wg.gds2gdsii(FileDc, gdsII_FileDc)
    fprintf('Output gdsII finish!\n')
end

for port_print = []
    Spiral_1_connect.get_port_out
    Spiral_1_connect.get_port_in
end
