clc;
clear;
close all;
scriptPath = '';
if usejava('desktop')
    scriptPath = matlab.desktop.editor.getActiveFilename();
end
if isempty(scriptPath)
    scriptPath = mfilename('fullpath');
end
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
    'Slot_str.py', ...
    'Slot_TWE_GSG_base.aedt', ...
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
    'Gap', 7, ...
    'W_T', 3.5, ...
    'period', 72, ...
    'FF', 0.58, ...
    'W_S', 64, ...
    'W_G', 136, ...
    'N_ele', 8 ...
    );

% 定义要扫描的参数（覆盖默认值）
sweep_params = struct();
% sweep_params.Gap = 7:2:11;   % 可按需扫描 Gap
sweep_params.FF = 0.58;
sweep_params.period = 72;
sweep_params.W_T = 3.5;
% sweep_params.FF = 0.9:-0.1:0.5;
% sweep_params.W_bend = 11:2:17;  % 如果要扫描其他参数，取消注释
sweep_params.gap_bend = 7;

% 自动生成参数组合
param_combine = Wcli_wg.generate_param_combinations(E_para_default, sweep_params);
sweep_names = fieldnames(sweep_params);
%%
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
    Disp_S = 2*E_para.Gap+4*E_para.W_T + E_para.W_G + E_para.W_S;
    Disp_G = Disp_S * 2;
    L_T_rail = E_para.N_ele*E_para.period;

    T_rail_S_ele_xy = Wcli_poly.create_slot_S(E_para.N_ele, E_para.period, E_para.W_S, E_para.FF, E_para.W_T);
    T_rail_S_ele_xy.transform_shape(pi/2,0,0);

    T_rail_G_ele_R_xy = Wcli_poly.create_slot_G(E_para.N_ele, E_para.period, E_para.W_G, E_para.FF, E_para.W_T);
    T_rail_G_ele_L_xy = T_rail_G_ele_R_xy.copy;
    T_rail_G_ele_R_xy.transform_shape(pi/2,Disp_G/4,0);
    T_rail_G_ele_L_xy.mirror_translate_shape('x');
    T_rail_G_ele_L_xy.transform_shape(pi/2,-Disp_G/4,0);
    L_all = L_T_rail;%总长度
    %% put HFSS
    HFSS_save_folder = ['F:\HFSS_data\Slotstr',run_date];
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
    json_struct.open_py = 'Slot_str.py';
    json_struct.extract_py = 'Export_data.py';

    json_struct.L_lump = 5;

    %     machine_select = 'digital:-1:8:90%:1';
    %     machine_select = 'blueold:-1:9:90%:1';
    %     machine_select = 'noblue:-1:9:90%:1';
    machine_select = 'wcli:-1:9:90%:1';
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
%% data visual
for load_data=[]
    %%文件夹
    HFSS_save_folder = 'F:\HFSS_data\Slotstr20251127';
    data_list = {'Nm', 'S11', 'S21', 'Zc_check'};
    
    sweep_folders = dir(fullfile(HFSS_save_folder, 'sw_*W_S_50*N_ele_10_*/Nm.csv'));%确定存在数据
    param_list = {'Gap','W_T','FF','period','W_S','N_ele'};
    numFolders = numel(sweep_folders);
    %% ==================== 数据读取 ====================
    % 'Nm', 'S11', 'S21', 'Zc_check' 等

    all_data = cell(numFolders, 1);
    param_vals = nan(numFolders, numel(param_list));

    % 预先创建参数名到索引的映射
    param_map = containers.Map(param_list, 1:numel(param_list));

    for i = 1:numFolders
        % 读取数据
        for i_csv = 1:length(data_list)
        files_path = fullfile(sweep_folders(i).folder, [data_list{i_csv},'.csv']);
        T = readtable(files_path, 'NumHeaderLines', 1);
        
        all_data{i}.(data_list{i_csv}) = T{:,2};
        end
        all_data{i}.Freq = T{:,1};%频率读取一次就行了

        % 读取mat参数
        mat_path = fullfile(sweep_folders(i).folder, 'para_save.mat');
        S = load(mat_path);
        for j = 1:numel(param_list)
            if isfield(S, param_list{j})
                param_vals(i,j) = S.(param_list{j});
            end
        end   
    end

    valid_rows = all(~isnan(param_vals), 2);
    fprintf('有效数据: %d/%d\n', sum(valid_rows), numFolders);
    valid_idx = find(valid_rows);
    freq = all_data{1}.Freq;%%获取频率list

    %% 画线图-横轴是文件编号
    for plot_3 = [3]
        data_to_plot = 'Zc_check';
        all_data_select = cellfun(@(x) (x.(data_to_plot)), all_data, 'UniformOutput', false);
        data_matrix = cell2mat(all_data_select');
        figure(1);
        all_data_select_single = data_matrix(500,:);
        plot(all_data_select_single)
        Wcli_wg.set_fig
    end
    %% 某个文件的具体数据
    for plot_3 = [3]
        % 参数设置
        i_file =139;
        % 绘图
        fig=figure(2);
        fig.Position=[871,486,721,433];
        tiledlayout(2,2);

        nexttile
        data_to_plot = 'Nm';% 'Nm', 'S11', 'S21', 'Zc_check' 等
        plot(all_data{i_file}.Freq, all_data{i_file}.(data_to_plot));
        xlabel('Frequency (GHz)');
        ylabel(data_to_plot, 'Interpreter', 'none');
        title(data_to_plot, 'Interpreter', 'none');

        nexttile
        data_to_plot = 'S21';% 'Nm', 'S11', 'S11', 'Zc_check' 等
        plot(all_data{i_file}.Freq, all_data{i_file}.(data_to_plot)*15);
        xlabel('Frequency (GHz)');
        ylabel(data_to_plot, 'Interpreter', 'none');
        ylim([-8,0]);
        title(data_to_plot, 'Interpreter', 'none');

        nexttile
        data_to_plot = 'S11';% 'Nm', 'S11', 'S21', 'Zc_check' 等
        plot(all_data{i_file}.Freq, all_data{i_file}.(data_to_plot));
        xlabel('Frequency (GHz)');
        ylabel(data_to_plot, 'Interpreter', 'none');
        title(data_to_plot, 'Interpreter', 'none');
        
        nexttile
        data_to_plot = 'Zc_check';% 'Nm', 'S11', 'S21', 'Zc_check' 等
        plot(all_data{i_file}.Freq, all_data{i_file}.(data_to_plot));
        xlabel('Frequency (GHz)');
        ylabel(data_to_plot, 'Interpreter', 'none');
        title(data_to_plot, 'Interpreter', 'none');
        fprintf("best result\n")
        for j = 1:numel(param_list)
            fprintf('  %s = %.3f\n', param_list{j}, param_vals(i_file, j));
        end
        Wcli_wg.set_fig
    end
end
