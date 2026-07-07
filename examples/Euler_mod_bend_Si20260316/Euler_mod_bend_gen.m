%%LN 1x2 MMI - 使用Wcli_wg类的新版本
%author:wcli
%modified Euler bend
% ref Jiang, X., Wu, H. & Dai, D. Opt. Express 26, 17680 (2018).
%2024-5-2更新：增加部分arc弯曲、增加宽度渐变、Euler改成poly函数
%2024-10-17更新：sagnac-loop
%2025-11-08更新：使用Wcli_wg类重构
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

device_name = 'eu_mod_bend';

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

% 可手动指定 FDTD 结果保存根目录；留空时默认保存到当前脚本目录
customFdtdOutputRoot = '';
if ~isempty(customFdtdOutputRoot)
    fdtdOutputRoot = customFdtdOutputRoot;
else
    fdtdOutputRoot = scriptFolder;
end

% 物理常量和单位定义
c_const = 299792458;
GHz = 1e9; kHz = 1e3; ns = 1e-9; us = 1e-6; MHz = 1e6;
nm = 1e-9; um = 1e-6; ms = 1e-3; cm = 1e-2; mm = 1e-3;
fobj = gobjects(50, 1);
run_date = datestr(now, 'yyyymmdd');
format long g

%% 参数扫描配置 ====================
% 定义默认参数（不扫描的参数）
para_default = struct(...
    'etch_angle', 81, ...           % 刻蚀角度 (degrees)
    'h_wg', 0.24, ...               % LN波导高度 (um)
    'W_inout',1.36,...
    'W_mid',0.62,...
    'R_arc', 6.4, ...                % 圆弧半径 (um)
    'mw', 1.2, ...%宽度渐变
    'arc_angle',31,...%圆弧角度
    'mk', 1.7 ...%弯曲渐变
);

% 定义要扫描的参数
sweep_params = struct();
% sweep_params.mk = 1:0.1:2;           
% sweep_params.arc_angle = 25:1:90;         
sweep_params.mk = 1.7;           
sweep_params.arc_angle = 31;         
sweep_names = fieldnames(sweep_params);

% 自动生成参数组合
param_combinations = Wcli_wg.generate_param_combinations(para_default, sweep_params);

%% 参数扫描循环 ====================
% for i_d = 1:numel(param_combinations)
for i_d = 1
% for i_d = 100
    % 获取当前参数组合
    para = param_combinations(i_d);
    str_wg = Wcli_wg.st_wg_gen("len",15,"Wid",para.W_inout);
    str_wg.flip_shape;
    full_bend = Wcli_wg.euler_arc_sym_bend_gen("R_arc",para.R_arc,"mk",para.mk,"arc_angle",deg2rad(para.arc_angle),...
        "W_inout",para.W_inout,"W_mid",para.W_mid,"total_angle",pi,'mw',para.mw,'etch_angle',para.etch_angle,'h_wg',0.22,'N_point',201);
    full_bend.move_to("cleft");
    full_bend.calc_trace_length;
    full_bend.merge_wg(str_wg); 
    full_bend.flip_shape;
    full_bend.merge_wg(str_wg); 
    %% 仿真边界和端口设置 ====================
    % 获取结构边界
    sim_edge_xy = full_bend.get_boundary_points+[5,-5;+5,5];
    % 设置端口位置
    port_in1 = full_bend.get_port_in + [8, 0, 0];
    port_out1 = full_bend.get_port_out + [8, 0, 0];
    
    port_xy_list = [port_in1; port_out1;];
    port_xy_dir = ['X', 'X'];
    
    %% 生成保存名称 ====================
    para_name = Wcli_wg.generate_save_name(para, device_name);
    
    %% FDTD仿真 ====================
    for fdtd_run = [1]
        close all;
        % FDTD单元格列表
        fdtd_pos_list = {
            full_bend.posdata2fdtd * nm, ...
        };
        % 准备FDTD数据
        fdtd_data.sim_file_name = 'bend_sim_basic.fsp';
        fdtd_data.para_name = para_name;
        fdtd_data.device_name = device_name;
        fdtd_data.run_date = run_date;
        fdtd_data.output_root = fdtdOutputRoot;
        fdtd_data.fdtd_pos_list = fdtd_pos_list;
        fdtd_data.port_xy_list = port_xy_list * um;
        fdtd_data.port_xy_dir = port_xy_dir;
        fdtd_data.sim_edge_xy = sim_edge_xy * um;
        fdtd_data.para = para;
        fdtd_data.h_slab = para.h_wg * um;
        
        Wcli_wg.run_fdtd_sim(fdtd_data,"flag_run",0,"gui_flag",1,"lsf_script",'FDTD_lsf.lsf');
        clear fdtd_data;
    end
    %% 画成环
    full_bend_ring = full_bend.copy;
    Str_length = 100;% 直波导长度
    full_bend.transform_shape(pi);
    full_bend_ring.merge_wg(full_bend,"ofs_xy",-[Str_length-30,0]);
    full_bend_ring=full_bend_ring.close_to_ring;
    %% GDS输出 ====================
    for outgds = []
        gds_folder = fullfile(scriptFolder, ['gds_gen_', run_date]);
        FileDc = fullfile(gds_folder, [para_name, '.gds']);
        Wcli_wg.generate_multi_flatten_gds(...
            {full_bend_ring}, FileDc, 8, ...
            para_name, para_name);
        fprintf('GDS生成完成!\n');
        FileDc_gds2 = fullfile(gds_folder, ['ii_', para_name, '.gds']);
        Wcli_wg.gds2gdsii(FileDc, FileDc_gds2);
        fprintf('GDSII输出完成!\n');
    end
    
end % deltaL_sw循环结束

%% 仿真 结果可视化 ====================
for fig_plot = []  % 设置为 [1] 进行数据可视化
    
    %% 配置绘图参数（可随时修改）
    clc;clear;close all;
    param_x = 'spac';         % X轴参数名
%     param_y = 'len_mmi';      % Y轴参数名
    param_y = 'Tin_len';      % Y轴参数名
    
    %% 加载数据
    date_list = {'20251124', '20251125'};
    files = [];
    for date = date_list
        sw_folder = fullfile(fdtdOutputRoot, ['FDTD_data_', device_name, '_', date{1}]);
        if exist(sw_folder, 'dir')
            current_files = dir(fullfile(sw_folder, [device_name, '*'], 'basic.mat'));
            files = [files; current_files]; %#ok<AGROW>
            fprintf('加载 %s: %d 个文件\n', date{1}, length(current_files));
        end
    end
    n_files = length(files);
    
    % 动态存储所有参数
    para_list = cell(n_files, 1);
    T_in_list = cell(n_files, 1);
    T_out1_list = cell(n_files, 1);
    T_out2_list = cell(n_files, 1);
    
    %% 从文件加载数据
    for i = 1:n_files
        % 加载仿真数据
        sim_data = load(fullfile(files(i).folder, 'basic.mat'));
        
        % 保存 para 结构体
        if isfield(sim_data, 'para')
            para_list{i} = sim_data.para;
        else
            warning('文件 %s 中没有 para 结构体', filename);
            para_list{i} = struct();  % 空结构体占位
        end
        
        % 导入波长数据（只需一次）
        if ~exist('lambda_all', 'var')
            lambda_all = sim_data.T_list{1}.lambda * 1e9; % 转换为 nm
        end
        
        % 提取传输数据
        T_in_list{i} = squeeze(sim_data.T_list{1}.T_net);      % 输入端口
        T_out1_list{i} = squeeze(sim_data.T_list{2}.T_net);    % 输出端口1
        T_out2_list{i} = squeeze(sim_data.T_list{3}.T_net);    % 输出端口2
    end
    
    % 提取选定的参数值
    param_x_values = cellfun(@(p) p.(param_x), para_list);
    param_y_values = cellfun(@(p) p.(param_y), para_list);
    
    % 计算关键指标（在中心波长处）
    lambda_idx = round(length(lambda_all) / 2);  % 中心波长索引
    
    IL_out1_vector = cellfun(@(x) 10*log10(abs(x(lambda_idx, 1))), T_out1_list);
    IL_out2_vector = cellfun(@(x) 10*log10(abs(x(lambda_idx, 1))), T_out2_list);
    T_out1_vector = cellfun(@(x) (abs(x(lambda_idx, 1))), T_out1_list);
    T_out2_vector = cellfun(@(x) (abs(x(lambda_idx, 1))), T_out2_list);
    splitting_vector = cellfun(@(x1, x2) abs(x1(lambda_idx, 1)) ./ abs(x2(lambda_idx, 1)), ...
        T_out1_list, T_out2_list);
    
    % 计算综合指标（插损均值 + 分光比偏差）
    IL_avg_vector = (IL_out1_vector + IL_out2_vector) / 2;
    T_avg_vector = (T_out1_vector + T_out2_vector) / 2;
    splitting_error = abs(splitting_vector - 1);
     
    % 查找最优点
    [min_score, index_best] = max(T_avg_vector);
    
    best_param_x = param_x_values(index_best);
    best_param_y = param_y_values(index_best);
    
    fprintf('\n========== 最优参数（综合评分） ==========\n');
    fprintf('编号: %d/%d (score=%.4f)\n', index_best, n_files, min_score);
    fprintf('%s = %.3f, %s = %.3f\n', param_x, best_param_x, param_y, best_param_y);
    fprintf('Out1 插损: %.3f dB\n', IL_out1_vector(index_best));
    fprintf('Out2 插损: %.3f dB\n', IL_out2_vector(index_best));
    fprintf('分光比: %.4f (偏差: %.4f%%)\n', ...
        splitting_vector(index_best), splitting_error(index_best)*100);
    fprintf('==========================================\n\n');
    
    %% 1D 曲线图
    for plot_1D = [1]
        figure(1);
        clf;
        
        % 子图1: 插入损耗
        subplot(2,1,1);
        plot(1:n_files, IL_out1_vector, '-o', 'DisplayName', 'Output 1');
        hold on;
        plot(1:n_files, IL_out2_vector, '-s', 'DisplayName', 'Output 2');
        plot(index_best, IL_out1_vector(index_best), 'rp', ...
            'MarkerSize', 15, 'MarkerFaceColor', 'r', 'DisplayName', 'Best');
        plot(index_best, IL_out2_vector(index_best), 'rp', ...
            'MarkerSize', 15, 'MarkerFaceColor', 'r', 'HandleVisibility', 'off');
        hold off;
        xlabel('Num');
        ylabel('IL (dB)');
        legend('Location', 'eastoutside');
        Wcli_wg.set_fig();
        
        % 子图2: 分光比
        subplot(2,1,2);
        plot(1:n_files, splitting_vector, '-^', 'DisplayName', 'Out1/Out2');
        hold on;
        yline(1, '--k', 'DisplayName', 'Ideal (50:50)');
        plot(index_best, splitting_vector(index_best), 'rp', ...
            'MarkerSize', 15, 'MarkerFaceColor', 'r', 'DisplayName', 'Best');
        hold off;
        xlabel('Num');
        ylabel('SR');
        legend('Location', 'eastoutside');
        Wcli_wg.set_fig();
        
    end
    
    %% 2D 色图 - 参数空间映射
    for plot_2D = [1]
        % 获取唯一参数值
        unique_x = unique(param_x_values);
        unique_y = unique(param_y_values);
        min_x = min(unique_x);
        max_x = max(unique_x);
        min_y = min(unique_y);
        max_y = max(unique_y);
        
        if isempty(unique_x) || isempty(unique_y)
            warning('参数数据不完整，无法绘制2D图！');
            continue;
        end
        
        % 创建网格
        [X, Y] = meshgrid(unique_x, unique_y);
        
        % 初始化数据网格（NaN填充）
        IL_out1_grid = nan(length(unique_y), length(unique_x));
        IL_out2_grid = nan(length(unique_y), length(unique_x));
        splitting_grid = nan(length(unique_y), length(unique_x));
        
        % 填充网格数据
        for i = 1:n_files
            x_val = param_x_values(i);
            y_val = param_y_values(i);
            
            x_idx = find(abs(unique_x - x_val) < 1e-10);
            y_idx = find(abs(unique_y - y_val) < 1e-10);
            
            if ~isempty(x_idx) && ~isempty(y_idx)
                % 检查重复数据
                if ~isnan(IL_out1_grid(y_idx, x_idx))
                    warning('参数组合 (%s=%.3f, %s=%.3f) 有多个仿真结果！', ...
                        param_x, x_val, param_y, y_val);
                end      
                IL_out1_grid(y_idx, x_idx) = IL_out1_vector(i);
                IL_out2_grid(y_idx, x_idx) = IL_out2_vector(i);
                splitting_grid(y_idx, x_idx) = splitting_vector(i);
            end
        end
        
        % 绘制 2D 色图（surf）
        fig = figure(2);
        fig.Position = [52.2,463.4,1913.6,374.4];
        
        subplot(1,3,1);
        surf(X, Y, IL_out1_grid);
        hold on;
        plot3(best_param_x, best_param_y, IL_out1_vector(index_best)*0.9, ...
            'rp', 'MarkerSize', 20, 'MarkerFaceColor', 'r');
        hold off;
        colorbar;
        colormap(slanCM(9));
        xlabel(strrep(param_x, '_', ' '));
        ylabel(strrep(param_y, '_', ' '));
        xlim([min_x,max_x]);
        ylim([min_y,max_y]);
        title('Out1 IL (dB)');
        view(2);
        Wcli_wg.set_fig();
        
        subplot(1,3,2);
        surf(X, Y, IL_out2_grid);
        hold on;
        plot3(best_param_x, best_param_y, IL_out2_vector(index_best)*0.9, ...
            'rp', 'MarkerSize', 20, 'MarkerFaceColor', 'r');
        hold off;
        colorbar;
        colormap(slanCM(9));
        xlabel(strrep(param_x, '_', ' '));
        ylabel(strrep(param_y, '_', ' '));
        xlim([min_x,max_x]);
        ylim([min_y,max_y]);
        title('Out2 IL (dB)');
        view(2);
        Wcli_wg.set_fig();
        
        subplot(1,3,3);
        surf(X, Y, abs(splitting_grid - 1) * 100);
        hold on;
        plot3(best_param_x, best_param_y, splitting_error(index_best)*100*100, ...
            'rp', 'MarkerSize', 20, 'MarkerFaceColor', 'r');
        hold off;
        colorbar;
        colormap(slanCM(9));
        xlabel(strrep(param_x, '_', ' '));
        ylabel(strrep(param_y, '_', ' '));
        xlim([min_x,max_x]);
        ylim([min_y,max_y]);
        title('SR Error (%)');
        view(2);
        Wcli_wg.set_fig();
        
        % 绘制等高线图
        figure(3);
        clf;
        [C, h_cont] = contourf(X, Y, IL_out1_grid, 10, 'LineColor', 'auto');
        hold on;
        clabel(C, h_cont, 'FontSize', 10);
        plot(best_param_x, best_param_y, 'rp', ...
            'MarkerSize', 20, 'MarkerFaceColor', 'r');
        hold off;
        colorbar;
        colormap(slanCM(9));
        xlabel(strrep(param_x, '_', ' '));
        ylabel(strrep(param_y, '_', ' '));
        title('IL(dB)');
        Wcli_wg.set_fig();
    end
    
    %% 波长依赖性分析
    for plot_spectrum = [1]
        % 选择最优参数点和几个代表性参数组合
        figure(4);
        clf;
        % 子图1: Out1 波长响应
        subplot(2,1,1);
        T_out1_spectrum = abs(T_out1_list{index_best}(:, 1:3));
        hold on;
        plot(lambda_all, pow2db(T_out1_spectrum));
        hold off;
        xlabel('λ (nm)');
        ylabel('IL (dB)');
        title('Out1');
        box on;
        Wcli_wg.set_fig();
        
        % 子图2: Out2 波长响应
        subplot(2,1,2);
        T_out2_spectrum = abs(T_out2_list{index_best}(:, 1:3));
        plot(lambda_all, pow2db(T_out2_spectrum));
        xlabel('λ (nm)');
        ylabel('IL (dB)');
        title('Out2');
        box on
        Wcli_wg.set_fig();
    end

    for plot_spectrum = [1]
        % 选择最优参数点和几个代表性参数组合
        figure(5);
        clf;
        % 子图1: Out1 波长响应
        T_out1_spectrum = abs(T_out1_list{index_best}(:, 1));
        hold on;
        plot(lambda_all, (T_out1_spectrum),'DisplayName','out1');
        T_out2_spectrum = abs(T_out2_list{index_best}(:, 1));
        plot(lambda_all, (T_out2_spectrum),'DisplayName','out2');
        xlabel('λ (nm)');
        ylabel('T');
        title('Out2');
        box on
        hold off;
        legend('Location','east')
        Wcli_wg.set_fig();
    end
    
end
