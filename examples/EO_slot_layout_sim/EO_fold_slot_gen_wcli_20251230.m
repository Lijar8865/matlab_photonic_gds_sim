clc;
clear;
close all;
scriptPath = '';
if usejava('desktop')
    scriptPath = matlab.desktop.editor.getActiveFilename(); % 尝试从编辑器获取当前活动文件路径（需要 MATLAB Desktop）
end
if isempty(scriptPath)
    scriptPath = mfilename('fullpath'); % 如果没有打开 Desktop，使用 mfilename 获取当前脚本路径
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
    'Slot_fold.py', ...
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
GHz = 1e9; kHz = 1e3; ns = 1e-9; us = 1e-6; MHz = 1e6;
nm = 1e-9; um = 1e-6; ms = 1e-3; cm = 1e-2; mm = 1e-3;
fobj = gobjects(50, 1);
run_date = datestr(now, 'yyyymmdd');
format long g

%% ==================== 参数扫描配置 ====================
% 定义默认参数（不扫描的参数）
E_para_default = struct(...
    'Gap', 7, ...
    'W_T', 4.5, ...
    'period', 52, ...
    'FF', 0.36, ...
    'W_S', 62, ...
    'W_G', 168, ...
    'N_ele', 9, ...
    'W_bend', 11, ...
    'gap_bend', 7, ...
    'L_D', 96, ...
    'Euler_angle', 90, ...
    'T_flag', 0 ...
    );
W_not_G = 100-4;
% 定义要扫描的参数（覆盖默认值）
sweep_params = struct();
sweep_params.L_D = 96;  % 延迟线扫描
% sweep_params.FF = 0.1:0.1:0.5;
% sweep_params.period = 52:8:76;
% sweep_params.W_T = 3.5:1:6.5;

% 自动生成参数组合
param_combine = Wcli_wg.generate_param_combinations(E_para_default, sweep_params);
sweep_names = fieldnames(sweep_params);
total_combinations = numel(param_combine);

fprintf('总扫描组合数: %d\n', total_combinations);
for i = 1:length(sweep_names)
    fprintf('  %s: %d 个值\n', sweep_names{i}, length(sweep_params.(sweep_names{i})));
end

%%
for i_d = 1
    %% basic parameter
    N_point = 201;
    
    % 获取参数
    E_para = param_combine(i_d);
    E_para.L_T = E_para.period * E_para.FF;
    
    % 打印当前扫描进度
    fprintf('Progress: %d/%d - ', i_d, total_combinations);
    for i = 1:length(sweep_names)
        fprintf('%s=%.1f ', sweep_names{i}, E_para.(sweep_names{i}));
    end
    fprintf('\n');
    
    %% 画结构
    E_tap_len = 50;
    W_bend = E_para.W_bend;
    gap_bend = E_para.gap_bend;
    Disp_S = 2*E_para.Gap +4*E_para.W_T+ E_para.W_G + E_para.W_S;
    Disp_G = Disp_S*2;
    W_gap = E_para.Gap+2*E_para.W_T;
    tap_ofst = (E_para.W_S - W_bend) / 2 + W_gap - gap_bend;
    R_inner_G = Disp_G/2 - tap_ofst - E_para.W_G/2;
    L_T_rail = E_para.N_ele * E_para.period * E_para.T_flag;
    
    % 创建弯曲波导
    Bend_IN_Sele = Wcli_wg.Arc_wg_gen(Disp_S/2, pi, 0, N_point, W_bend, W_bend);
    Bend_OUT_Gele = Wcli_poly.create_rect_not("radius", R_inner_G, ...
        "width", W_not_G, "height", E_para.W_G + tap_ofst);
    
    Bend_IN_Sele.transform_shape(pi/2, Disp_S/2, L_T_rail + E_tap_len);
    Bend_OUT_Gele.transform_shape(pi/2, Disp_G/2 - tap_ofst/2, L_T_rail + E_tap_len);
    
    % 创建 Slot 电极结构
    T_rail_S_ele_R = Wcli_wg.create_slot_S(E_para.N_ele, E_para.period, E_para.W_S, E_para.FF, E_para.W_T);
    T_rail_S_ele_L = T_rail_S_ele_R.copy;
    T_rail_S_ele_R.transform_shape(pi/2,Disp_S/2,0);
    T_rail_S_ele_L.transform_shape(pi/2,-Disp_S/2,0);

    T_rail_G_center = Wcli_wg.create_slot_S(E_para.N_ele, E_para.period, E_para.W_G, E_para.FF, E_para.W_T);
    T_rail_G_center.transform_shape(pi/2);
    
    T_rail_G_ele_R = Wcli_wg.create_slot_G(E_para.N_ele, E_para.period, E_para.W_G, E_para.FF, E_para.W_T);
    T_rail_G_ele_L = T_rail_G_ele_R.copy;
    T_rail_G_ele_R.transform_shape(pi/2, Disp_G/2, 0);
    T_rail_G_ele_L.mirror_translate_shape('x');
    T_rail_G_ele_L.transform_shape(pi/2, -Disp_G/2, 0);
    
    % 创建 Taper
    S_taper = Wcli_wg.taper_waveguide_gen(E_tap_len, 0, E_para.W_S, W_bend, 1, 3);
    S_taper.transform_shape(pi/2, Disp_S/2, L_T_rail);
    S_taper_out = S_taper.copy();
    S_taper.merge_and_translate(0, [E_para.L_D, -E_para.L_D], 0, Bend_IN_Sele, S_taper_out.flip_shape());
    Bend_IN_Sele_tap = S_taper.copy();
    
    % G taper
    G_taper_in_xy = [Disp_G/2 + E_para.W_G/2, L_T_rail;
                     Disp_G/2 + E_para.W_G/2, L_T_rail + E_tap_len;
                     Disp_G/2 - E_para.W_G/2 - tap_ofst, L_T_rail + E_tap_len;
                     Disp_G/2 - E_para.W_G/2, L_T_rail;];
    G_taper_in = Wcli_poly(G_taper_in_xy);
    G_taper_out = G_taper_in.copy;
    G_taper_out.mirror_translate_shape("y");
    G_taper_in.merge_polys_nv(Bend_OUT_Gele, "p1", 2, "p2", 1, "ofs_xy", [0,E_para.L_D], "rm_pts", false);
    G_taper_in.merge_polys_nv(G_taper_out, "p1", 2, "p2", 2, "ofs_xy", [0,-E_para.L_D], "rm_pts", false);
    
    G_taper_center = Wcli_wg.taper_waveguide_gen(E_tap_len, 0, E_para.W_G, E_para.W_G + tap_ofst*2, 1, 3);
    G_taper_center.transform_shape(pi/2, 0, L_T_rail);
    
    Center_G_ele = Wcli_wg.create_semicircle(E_para.W_G/2 + tap_ofst,N_point);
    Center_G_ele.transform_shape(pi/2,0, L_T_rail + E_tap_len);
    G_taper_center = G_taper_center.to_poly();
    G_taper_center.merge_polys_nv(Center_G_ele, "ofs_xy", [0,E_para.L_D], "rm_pts", false);
    % 计算总长度
    L_all = L_T_rail + E_tap_len + E_para.L_D + R_inner_G + W_not_G+100;
    
    %% put HFSS
    HFSS_save_folder = ['G:\HFSS_data\Slotfold', run_date];
    para_name = Wcli_wg.generate_save_name(E_para, 'sw');
    json_struct.save_folder = fullfile(HFSS_save_folder, para_name);
    json_struct.scriptFolder = scriptFolder;
    json_struct.Disp_S = Disp_S;
    json_struct.Disp_G = Disp_G;
    
    json_struct.T_rail_S_R = T_rail_S_ele_R.postohfss2d;
    json_struct.T_rail_S_L = T_rail_S_ele_L.postohfss2d;
    json_struct.T_rail_G_center = T_rail_G_center.postohfss2d;
    json_struct.T_rail_G_R = T_rail_G_ele_R.postohfss2d;
    json_struct.T_rail_G_L = T_rail_G_ele_L.postohfss2d;
    
    json_struct.Bend_G_ele = G_taper_in.postohfss2d;
    json_struct.Bend_S_ele = S_taper.postohfss2d;
    json_struct.Center_G_ele = G_taper_center.postohfss2d;
    
    % json_struct.G_taper_in = G_taper_in.postohfss2d;
    % json_struct.G_taper_out = G_taper_out.postohfss2d;
    % json_struct.G_taper_center = G_taper_center.postohfss2d;
    
    json_struct.Freq_step = 0.1;
    json_struct.Freq_end = 100;
    json_struct.L = L_all;
    json_struct.W = Disp_G+E_para.W_G+100;
    
    json_struct = Wcli_wg.merge_two_structs(json_struct, E_para);
    json_struct.open_py = 'Slot_fold.py';
    json_struct.extract_py = 'Export_data.py';
    
    % machine_select = 'digital:-1:8:90%:1';
    machine_select = 'localhost:-1:8:90%:1';
    % machine_select = 'blueold2:-1:9:90%:1';
    
    Wcli_wg.put_HFSS(json_struct, 'run_flag',0, 'machine_select', machine_select);
    clear json_struct;
end
%% 
for load_data=[]
    %%文件夹
    clc;clear;close all;
    HFSS_save_folder = 'G:\HFSS_data\Slotfold20251230';
    data_list = {'GroupDelay', 'S11', 'S21', 'Zc_check'};
    
    sweep_folders = dir(fullfile(HFSS_save_folder, 'sw_*W_S_50*N_ele_10_*/Nm.csv'));%确定存在数据
    param_list = {'Gap','W_T','FF','period','W_S','N_ele','W_bend','gap_bend','L_D'};
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

    % 根据 L_D 参数重新排序
    L_D_idx = param_map('L_D');
    [~, sort_idx] = sort(param_vals(:, L_D_idx));

    % 重新排序所有相关变量
    all_data = all_data(sort_idx);
    param_vals = param_vals(sort_idx, :);
    sweep_folders = sweep_folders(sort_idx);

    fprintf('数据已按 L_D 重新排序\n');
    fprintf('L_D 范围: %.1f ~ %.1f\n', min(param_vals(:, L_D_idx)), max(param_vals(:, L_D_idx)));

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
    %% 画线图-横轴是某个参数
    for plot_3 = [4]
        data_to_plot = 'GroupDelay';
        all_data_select = cellfun(@(x) (x.(data_to_plot)), all_data, 'UniformOutput', false);
        all_para_select = param_vals(:,9);
        data_matrix = cell2mat(all_data_select');
        figure(1);
        all_data_select_single = data_matrix(400,:);
        plot(all_para_select,all_data_select_single*1e9)
        xlabel('LD(um)');
        ylabel('tau_e(ps)')
        Wcli_wg.set_fig
    end
    %% 画二维参数分布图
    para_x = 'W_bend';
    para_y = 'gap_bend';
    

    %% 某个文件的具体数据
    for plot_3 = [3]
        % 参数设置
        i_file =1;
        % 绘图
        fig=figure(2);
        fig.Position=[871,486,721,433];
        tiledlayout(2,2);

        nexttile
        data_to_plot = 'GroupDelay';% 'Nm', 'S11', 'S21', 'Zc_check' 等
        plot(all_data{i_file}.Freq, all_data{i_file}.(data_to_plot));
        xlabel('Frequency (GHz)');
        ylabel(data_to_plot, 'Interpreter', 'none');
        title(data_to_plot, 'Interpreter', 'none');

        nexttile
        data_to_plot = 'S11';% 'Nm', 'S11', 'S11', 'Zc_check' 等
        plot(all_data{i_file}.Freq, all_data{i_file}.(data_to_plot));
        xlabel('Frequency (GHz)');
        ylabel(data_to_plot, 'Interpreter', 'none');
        title(data_to_plot, 'Interpreter', 'none');

        nexttile
        data_to_plot = 'S21';% 'Nm', 'S11', 'S21', 'Zc_check' 等
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




