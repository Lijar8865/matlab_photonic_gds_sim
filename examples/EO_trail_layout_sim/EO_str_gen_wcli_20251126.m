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
    'T_rail_str.py', ...
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
format long g
%% ==================== 参数扫描配置 ====================
% 定义默认参数（不扫描的参数）
E_para_default = struct(...
    'Gap', 8, ...
    'W_rail', 4.2, ...
    'W_T', 2.8, ...
    'L_rail', 8, ...
    'period', 54, ...
    'FF', 0.44, ...
    'W_S', 82, ...
    'W_G', 132, ...
    'N_ele', 8 ...
);

% 定义要扫描的参数（覆盖默认值）
sweep_params = struct();
% sweep_params.Gap = 8:2:12;   % 可按需扫描 Gap
sweep_params.L_rail = 8;
sweep_params.period = 54;
% sweep_params.FF = 0.9:-0.1:0.5;
% sweep_params.W_bend = 12:2:18;  % 如果要扫描其他参数，取消注释
% sweep_params.gap_bend = 7:11;

% 自动生成参数组合
param_combine = Wcli_wg.generate_param_combinations(E_para_default, sweep_params);
sweep_names = fieldnames(sweep_params);
%%
% for i_d = 1:numel(param_combine)
for i_d = 1
    %扫描
    E_para = param_combine(i_d);%获取参数
    E_para.L_T = E_para.period*E_para.FF;
    % 打印当前扫描进度
    fprintf('Progress: %d/%d - ', i_d, numel(param_combine));
    for i = 1:length(sweep_names)
        fprintf('%s=%.1f ', sweep_names{i}, E_para.(sweep_names{i}));
    end
    fprintf('\n');
    %% 画结构
    Disp_G = (2*E_para.Gap+4*E_para.W_rail+4*E_para.W_T+E_para.W_G+E_para.W_S)*2; % 目标侧向位移 (dy)
    Disp_S = 2*E_para.Gap+4*E_para.W_rail+4*E_para.W_T+E_para.W_G+E_para.W_S; % 目标侧向位移 (dy)
    W_gap =E_para.Gap+2*E_para.W_rail+2*E_para.W_T;
    L_T_rail = E_para.N_ele*E_para.period;%flag为1的时候才带上T电极

    T_rail_S_ele_xy = Wcli_poly.create_T_rail_S(E_para.N_ele, E_para.period, E_para.W_S, E_para.W_rail, E_para.L_rail, E_para.W_T, E_para.L_T);
    T_rail_S_ele_xy.transform_shape(pi/2,0,0);

    T_rail_G_ele_R_xy = Wcli_poly.create_T_rail_G(E_para.N_ele, E_para.period, E_para.W_G, E_para.W_rail, E_para.L_rail, E_para.W_T, E_para.L_T);
    T_rail_G_ele_L_xy = T_rail_G_ele_R_xy.copy;
    T_rail_G_ele_R_xy.transform_shape(pi/2,Disp_G/4,0);
    T_rail_G_ele_L_xy.mirror_translate_shape('x');
    T_rail_G_ele_L_xy.transform_shape(pi/2,-Disp_G/4,0);
    L_all = L_T_rail;%总长度
    %% put HFSS
    HFSS_save_folder = ['F:\HFSS_data\T_railstr',run_date];
    para_name = Wcli_wg.generate_save_name(E_para, 'sw');
    json_struct.save_folder = fullfile(HFSS_save_folder,para_name);
    json_struct.scriptFolder = scriptFolder;
    json_struct.Disp_S = Disp_S;
    json_struct.Disp_G = Disp_G;
    json_struct.T_rail_S = T_rail_S_ele_xy.postohfss2d;
    json_struct.T_rail_G_R = T_rail_G_ele_R_xy.postohfss2d;
    json_struct.T_rail_G_L = T_rail_G_ele_L_xy.postohfss2d;
    json_struct.Freq_step = 0.1;%步进0.1GHz
    json_struct.Freq_end = 100;%结束频率100GHz

    json_struct.L = L_all;
    json_struct = Wcli_wg.merge_two_structs(json_struct,E_para);
    json_struct.open_py = 'T_rail_str.py';
    json_struct.extract_py = 'Export_data.py';

    json_struct.L_lump = 5;

%     machine_select = 'digital:-1:8:90%:1';
%     machine_select = 'blueold2:-1:9:90%:1';
    % machine_select = 'noblue:-1:9:90%:1';
    machine_select = 'localhost:-1:9:90%:1';
%     machine_select = 'wcli:-1:9:90%:1';
    Wcli_wg.put_HFSS(json_struct, 'run_flag',0,'machine_select',machine_select);
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
