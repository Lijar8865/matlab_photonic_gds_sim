% Wcli_circuit - 多个多边形/波导对象的电路组合类
%
% 功能：
%   - 管理多个 Wcli_poly/Wcli_wg/Wcli_circuit 对象的集合（支持嵌套）
%   - 提供整体几何变换（旋转、平移、镜像）
%   - 支持相对位置管理和图层分配
%   - 整体边界计算
%   - 批量 GDS 输出（扁平化和层级化）
%
% 创建日期: 2025-12-07
% 作者: Wcli

classdef Wcli_circuit < handle

    properties
        pcells (1,:) cell = {}           % 电路单元数组 {Wcli_poly, Wcli_wg, Wcli_circuit, ...}
        laycells (1,:) double = []       % 图层编号数组
        pos_cells (:,2) double = []      % 相对位置矩阵 N×2 [x, y] (μm)
        name (1,:) char = 'circuit_obj'  % 电路名称
    end

    methods (Access = public)
        %% 构造函数
        function obj = Wcli_circuit(pcells, options)
            % 构造函数
            % 输入:
            %   pcells - cell 数组，包含多个 Wcli_poly/Wcli_wg/Wcli_circuit 对象
            %
            % 名称-值参数:
            %   laycells - 图层编号数组（默认全为1）
            %   pos_cells - 相对位置矩阵 N×2（默认全为0）
            %   name - 电路名称（默认 'circuit_obj'）
            %
            % 示例:
            %   circuit = Wcli_circuit({poly1, poly2}, 'laycells', [1, 2], 'name', 'MyCircuit');
            %   circuit = Wcli_circuit({poly1, poly2}, 'laycells', 5);  % 所有单元使用图层5

            arguments
                pcells (1,:) cell
                options.laycells (1,:) double = []
                options.pos_cells (:,2) double = []
                options.name (1,:) char = 'circuit_obj'
            end

            n_cells = length(pcells);

            % 验证 pcells 中的对象类型（支持嵌套 Wcli_circuit）
            for i = 1:n_cells
                if ~isa(pcells{i}, 'Wcli_poly') && ...
                        ~isa(pcells{i}, 'Wcli_wg') && ...
                        ~isa(pcells{i}, 'Wcli_circuit')
                    error('pcells{%d} 必须是 Wcli_poly、Wcli_wg 或 Wcli_circuit 对象', i);
                end
                pcells{i} = pcells{i}.copy;
            end

            obj.pcells = pcells;
            obj.name = options.name;

            % 处理图层编号
            if isempty(options.laycells)
                obj.laycells = ones(1, n_cells);
            else
                if length(options.laycells) == 1
                    obj.laycells = repmat(options.laycells, 1, n_cells);
                elseif length(options.laycells) == n_cells
                    obj.laycells = options.laycells;
                else
                    error('laycells 长度必须为 1 或与 pcells 长度相同 (%d)', n_cells);
                end
            end

            % 处理相对位置
            if isempty(options.pos_cells)
                obj.pos_cells = zeros(n_cells, 2);
            else
                if size(options.pos_cells, 1) == 1
                    obj.pos_cells = repmat(options.pos_cells, n_cells, 1);
                elseif size(options.pos_cells, 1) == n_cells
                    obj.pos_cells = options.pos_cells;
                else
                    error('pos_cells 行数必须为 1 或与 pcells 长度相同 (%d)', n_cells);
                end
            end

            fprintf('circuit created: "%s" (%d cells)\n', obj.name, n_cells);
        end
%% 深度复制方法
function new_obj = copy(obj)
    % 深度复制电路对象
    % 递归复制所有嵌套的 handle 对象（Wcli_poly, Wcli_wg, Wcli_circuit）
    %
    % 输出:
    %   new_obj - 复制的新电路对象
    %
    % 示例:
    %   circuit_copy = circuit.copy();
    %   circuit_copy.transform_shape(0, 100, 0);  % 不影响原对象
    
    % 创建新的空电路对象
    new_obj = Wcli_circuit({}, 'name', obj.name);
    
    % 复制基本属性
    new_obj.laycells = obj.laycells;
    new_obj.pos_cells = obj.pos_cells;
    
    % 深度复制所有 pcells（递归复制嵌套结构）
    new_obj.pcells = cell(size(obj.pcells));
    for i = 1:length(obj.pcells)
        cell_obj = obj.pcells{i};
        
        if isa(cell_obj, 'Wcli_circuit')
            % 递归复制子电路
            new_obj.pcells{i} = cell_obj.copy();
            
        elseif isa(cell_obj, 'Wcli_wg')
            % 复制波导对象
            new_obj.pcells{i} = cell_obj.copy();
            
        elseif isa(cell_obj, 'Wcli_poly')
            % 复制多边形对象
            new_obj.pcells{i} = cell_obj.copy();
            
        else
            warning('未知对象类型，直接引用（可能不安全）');
            new_obj.pcells{i} = cell_obj;
        end
    end
    
    fprintf('已复制电路 "%s" (共 %d 个单元)\n', obj.name, length(obj.pcells));
end
        %% 递归展开方法
        function [flat_polys, flat_layers] = flatten_to_polys(obj)
            % 递归展开所有嵌套结构，返回扁平化的 Wcli_poly 对象列表
            % 输出:
            %   flat_polys - Wcli_poly 对象的 cell 数组
            %   flat_layers - 对应的图层编号数组

            flat_polys = {};
            flat_layers = [];

            for i = 1:length(obj.pcells)
                cell_obj = obj.pcells{i};
                layer = obj.laycells(i);

                if isa(cell_obj, 'Wcli_circuit')
                    % 递归展开子电路
                    [sub_polys, sub_layers] = cell_obj.flatten_to_polys();
                    flat_polys = [flat_polys, sub_polys];
                    flat_layers = [flat_layers, sub_layers];

                elseif isa(cell_obj, 'Wcli_wg')
                    % 转换波导为多边形
                    flat_polys{end+1} = cell_obj.to_poly();
                    flat_layers(end+1) = layer;

                elseif isa(cell_obj, 'Wcli_poly')
                    % 直接添加多边形
                    flat_polys{end+1} = cell_obj;
                    flat_layers(end+1) = layer;
                end
            end
        end

        function depth = get_hierarchy_depth(obj)
            % 获取层级深度（用于调试）

            depth = 1;
            for i = 1:length(obj.pcells)
                if isa(obj.pcells{i}, 'Wcli_circuit')
                    sub_depth = obj.pcells{i}.get_hierarchy_depth() + 1;
                    depth = max(depth, sub_depth);
                end
            end
        end

        %% 添加/删除单元
        function obj = add_cell(obj, cell_obj, layer, pos_x, pos_y)
            % 添加一个新单元（支持 Wcli_circuit）

            arguments
                obj Wcli_circuit
                cell_obj
                layer (1,1) double {mustBeInteger, mustBePositive} = 1
                pos_x (1,1) double = 0
                pos_y (1,1) double = 0
            end

            if ~isa(cell_obj, 'Wcli_poly') && ...
                    ~isa(cell_obj, 'Wcli_wg') && ...
                    ~isa(cell_obj, 'Wcli_circuit')
                error('cell_obj 必须是 Wcli_poly、Wcli_wg 或 Wcli_circuit 对象');
            end

            obj.pcells{end+1} = cell_obj.copy;
            obj.laycells(end+1) = layer;
            obj.pos_cells(end+1, :) = [pos_x, pos_y];

            if isa(cell_obj, 'Wcli_circuit')
                fprintf('已添加子电路 "%s" (图层 %d, 位置 [%.2f, %.2f])\n', ...
                    cell_obj.name, layer, pos_x, pos_y);
            else
                fprintf('已添加单元 (图层 %d, 位置 [%.2f, %.2f])\n', layer, pos_x, pos_y);
            end
        end

        function obj = remove_cell(obj, indices)
            % 删除指定索引的单元（支持删除单个或多个）
            %
            % 输入参数:
            %   indices - 要删除的单元索引（标量或向量）
            %
            % 示例:
            %   circuit.remove_cell(3);           % 删除第3个单元
            %   circuit.remove_cell([1, 3, 5]);   % 删除第1、3、5个单元
            %   circuit.remove_cell(2:4);         % 删除第2到第4个单元
            
            arguments
                obj Wcli_circuit
                indices (1,:) double {mustBeInteger, mustBePositive}
            end
            
            % 检查索引是否有效
            max_index = length(obj.pcells);
            if any(indices > max_index)
                error('索引超出范围 (1-%d)', max_index);
            end
            
            % 去重并排序（从大到小删除，避免索引变化）
            indices = unique(indices);
            indices = sort(indices, 'descend');
            
            % 删除单元
            obj.pcells(indices) = [];
            obj.laycells(indices) = [];
            obj.pos_cells(indices, :) = [];
        end

        %% 几何变换方法（递归应用）
        function obj = transform_shape(obj, theta, T_x, T_y)
            % 整体旋转和平移变换（递归应用到所有子单元）

            arguments
                obj Wcli_circuit
                theta (1,1) double = 0
                T_x (1,1) double = 0
                T_y (1,1) double = 0
            end

            n_cells = length(obj.pcells);

            % 先旋转相对位置
            if theta ~= 0
                obj.pos_cells = Wcli_poly.rotate_translate_xy(obj.pos_cells, theta, 0, 0);
            end

            % 对每个单元递归应用变换
            for i = 1:n_cells
                if theta ~= 0
                    obj.pcells{i}.transform_shape(theta, 0, 0);
                end
                obj.pcells{i}.transform_shape(0, T_x, T_y);
            end

            % 更新相对位置
            if T_x ~= 0 || T_y ~= 0
                obj.pos_cells = obj.pos_cells + [T_x, T_y];
            end

            fprintf('电路整体变换: 旋转 %.2f°, 平移 [%.2f, %.2f] μm\n', ...
                theta*180/pi, T_x, T_y);
        end

        function obj = mirror_translate_shape(obj, axis, T_x, T_y)
            % 整体镜像和平移变换（递归应用）

            arguments
                obj Wcli_circuit
                axis (1,:) char {mustBeMember(axis, {'x', 'y', 'xy'})} = 'x'
                T_x (1,1) double = 0
                T_y (1,1) double = 0
            end

            n_cells = length(obj.pcells);

            % 镜像相对位置
            obj.pos_cells = Wcli_poly.mirror_translate_xy(obj.pos_cells, axis, 0, 0);

            % 递归镜像每个单元
            for i = 1:n_cells
                obj.pcells{i}.mirror_translate_shape(axis, 0, 0);
            end

            % 应用平移
            if T_x ~= 0 || T_y ~= 0
                obj.pos_cells = obj.pos_cells + [T_x, T_y];
                for i = 1:n_cells
                    obj.pcells{i}.transform_shape(0, T_x, T_y);
                end
            end

            fprintf('电路整体镜像: 轴=%s, 平移 [%.2f, %.2f] μm\n', axis, T_x, T_y);
        end

        function obj = center_to_position(obj, center_x, center_y)
            % 将电路整体居中到指定位置

            arguments
                obj Wcli_circuit
                center_x (1,1) double = 0
                center_y (1,1) double = 0
            end

            boundary = obj.get_boundary_points();
            current_center_x = (boundary(1,1) + boundary(2,1)) / 2;
            current_center_y = (boundary(1,2) + boundary(2,2)) / 2;

            T_x = center_x - current_center_x;
            T_y = center_y - current_center_y;

            obj.transform_shape(0, T_x, T_y);

            fprintf('电路已居中:\n');
            fprintf('  原中心: (%.3f, %.3f) μm\n', current_center_x, current_center_y);
            fprintf('  新中心: (%.3f, %.3f) μm\n', center_x, center_y);
        end

        function obj = align_edge(obj, target_x, target_y, edge_side)
            % 将电路整体边界对齐到目标坐标

            arguments
                obj Wcli_circuit
                target_x (1,1) double = 0
                target_y (1,1) double = 0
                edge_side (1,:) char {mustBeMember(edge_side, {'left', 'right', 'top', 'bottom'})} = 'left'
            end

            boundary = obj.get_boundary_points();
            x_min = boundary(1, 1);
            y_min = boundary(1, 2);
            x_max = boundary(2, 1);
            y_max = boundary(2, 2);

            center_x = (x_min + x_max) / 2;
            center_y = (y_min + y_max) / 2;

            switch edge_side
                case 'left'
                    T_x = target_x - x_min;
                    T_y = target_y - center_y;
                case 'right'
                    T_x = target_x - x_max;
                    T_y = target_y - center_y;
                case 'top'
                    T_x = target_x - center_x;
                    T_y = target_y - y_max;
                case 'bottom'
                    T_x = target_x - center_x;
                    T_y = target_y - y_min;
            end

            obj.transform_shape(0, T_x, T_y);

            fprintf('电路边缘已对齐: %s 边 -> (%.3f, %.3f) μm\n', ...
                edge_side, target_x, target_y);
        end
                function obj = move_to(obj,align_mode, targetxy )
            % 将波导对象的指定对齐点移动到目标坐标
            % 
            % 边界示意图：
            %          ctop (顶边中心)
            %      +----------------------+
            %      |  topleft     topright|
            % cleft|                      |cright
            %      |         cen          |
            %      |botleft      botright |
            %      +----------------------+
            %        cbot (底边中心)
            %
            % 输入参数:
            %   target_x - 目标x坐标 (μm)
            %   target_y - 目标y坐标 (μm)
            %   align_mode - 对齐模式:
            %       'cleft'    - 左边中心
            %       'cright'   - 右边中心
            %       'ctop'     - 顶边中心
            %       'cbot'     - 底边中心
            %       'topleft'  - 左上角
            %       'topright' - 右上角
            %       'botleft'  - 左下角
            %       'botright' - 右下角
            %       'cen'      - 中心点
            %
            % 示例:
            %   wg.align_edge(0, 0, 'cleft');      % 左边中心对齐到原点
            %   wg.align_edge(100, 50, 'topright'); % 右上角对齐到(100,50)
            %   wg.align_edge(0, 0, 'cen');        % 中心对齐到原点
            
            arguments
                obj Wcli_circuit
                align_mode (1,:) char {mustBeMember(align_mode, ...
                    {'cleft', 'cright', 'ctop', 'cbot', ...
                     'topleft', 'topright', 'botleft', 'botright', 'cen'})} = 'cleft'
                     targetxy (1,2) double = [0,0]
            end
            
            % 获取当前边界
            x_min = obj.get_boundary_xmin();
            x_max = obj.get_boundary_xmax();
            y_min = obj.get_boundary_ymin();
            y_max = obj.get_boundary_ymax();
            
            % 计算边界中心
            x_center = (x_min + x_max) / 2;
            y_center = (y_min + y_max) / 2;
            
            % 根据对齐模式计算当前对齐点坐标
            switch align_mode
                case 'cleft'
                    % 左边中心: (x_min, y_center)
                    current_x = x_min;
                    current_y = y_center;
                    
                case 'cright'
                    % 右边中心: (x_max, y_center)
                    current_x = x_max;
                    current_y = y_center;
                    
                case 'ctop'
                    % 顶边中心: (x_center, y_max)
                    current_x = x_center;
                    current_y = y_max;
                    
                case 'cbot'
                    % 底边中心: (x_center, y_min)
                    current_x = x_center;
                    current_y = y_min;
                    
                case 'topleft'
                    % 左上角: (x_min, y_max)
                    current_x = x_min;
                    current_y = y_max;
                    
                case 'topright'
                    % 右上角: (x_max, y_max)
                    current_x = x_max;
                    current_y = y_max;
                    
                case 'botleft'
                    % 左下角: (x_min, y_min)
                    current_x = x_min;
                    current_y = y_min;
                    
                case 'botright'
                    % 右下角: (x_max, y_min)
                    current_x = x_max;
                    current_y = y_min;
                    
                case 'cen'
                    % 中心点: (x_center, y_center)
                    current_x = x_center;
                    current_y = y_center;
            end
            
            % 计算所需的平移量
            T_x = targetxy(1) - current_x;
            T_y = targetxy(2) - current_y;
            
            % 应用平移（不旋转，只平移）
            obj.transform_shape(0, T_x, T_y);
            
            % 可选：显示对齐信息
            % fprintf('波导已对齐: %s -> (%.3f, %.3f) μm\n', align_mode, target_x, target_y);
        end

        function next_obj = align_obj(obj, next_obj, align_mode, targetxy)
            % 将另一个多边形对象对齐到当前对象的指定位置
            % 当前对象保持不变，移动 next_obj 使其与 obj 的对齐点重合
            %
            % 边界示意图：
            %          ctop (顶边中心)
            %      +----------------------+
            %      |  topleft     topright|
            % cleft|                      |cright
            %      |         cen          |
            %      |botleft      botright |
            %      +----------------------+
            %        cbot (底边中心)
            %
            % 输入参数:
            %   obj - 当前 Wcli_poly 对象（参考对象，保持不变）
            %   next_obj - 要对齐的 Wcli_poly 对象（将被移动）
            %   align_mode - 对齐模式（两个对象使用相同的对齐点）:
            %       'cleft'    - 对齐到左边中心
            %       'cright'   - 对齐到右边中心
            %       'ctop'     - 对齐到顶边中心
            %       'cbot'     - 对齐到底边中心
            %       'topleft'  - 对齐到左上角
            %       'topright' - 对齐到右上角
            %       'botleft'  - 对齐到左下角
            %       'botright' - 对齐到右下角
            %       'cen'      - 对齐到中心点
            %   targetxy - 可选的额外偏移量 [dx, dy] (μm)，默认 [0, 0]
            %
            % 输出:
            %   next_obj - 对齐后的对象（已修改）
            %
            % 示例:
            %   obj1.align_poly(obj2, 'cright');          % 将 obj2 的右边中心对齐到 obj1 的右边中心
            %   obj1.align_poly(obj2, 'cen', [5, 0]);     % 中心对齐后再向右偏移 5μm
            %   obj1.align_poly(obj2, 'topleft', [0, 2]); % 左上角对齐后向上偏移 2μm
            
            arguments
                obj Wcli_circuit
                next_obj 
                align_mode (1, :) char {mustBeMember(align_mode, ...
                    {'cleft', 'cright', 'ctop', 'cbot', ...
                    'topleft', 'topright', 'botleft', 'botright', 'cen'})} = 'cright'
                targetxy (1, 2) double = [0, 0]
            end
            
            % 获取当前对象的对齐点坐标
            obj_align_xy = obj.get_align_point(align_mode);
            
            % 添加额外偏移
            target_pos = obj_align_xy + targetxy;
            
            % 将 next_obj 的相同对齐点移动到目标位置
            next_obj.move_to(align_mode, target_pos);
            
            % 可选：显示对齐信息
            % fprintf('已将对象对齐: obj.%s (%.3f, %.3f) -> next_obj.%s (%.3f, %.3f) μm\n', ...
            %     align_mode, obj_align_xy(1), obj_align_xy(2), ...
            %     align_mode, target_pos(1), target_pos(2));
        end

        %% 边界计算方法（递归）
        function boundary = get_boundary_points(obj)
            % 获取整体边界（递归考虑所有嵌套单元）

            if isempty(obj.pcells)
                boundary = [0, 0; 0, 0];
                return;
            end

            all_x_min = zeros(length(obj.pcells), 1);
            all_x_max = zeros(length(obj.pcells), 1);
            all_y_min = zeros(length(obj.pcells), 1);
            all_y_max = zeros(length(obj.pcells), 1);

            for i = 1:length(obj.pcells)
                cell_boundary = obj.pcells{i}.get_boundary_points();
                all_x_min(i) = cell_boundary(1, 1);
                all_y_min(i) = cell_boundary(1, 2);
                all_x_max(i) = cell_boundary(2, 1);
                all_y_max(i) = cell_boundary(2, 2);
            end

            x_min = min(all_x_min);
            x_max = max(all_x_max);
            y_min = min(all_y_min);
            y_max = max(all_y_max);

            boundary = [x_min, y_min; x_max, y_max];
        end

        function dx = get_boundary_dx(obj)
            boundary = obj.get_boundary_points();
            dx = boundary(2,1) - boundary(1,1);
        end

        function dy = get_boundary_dy(obj)
            boundary = obj.get_boundary_points();
            dy = boundary(2,2) - boundary(1,2);
        end

        function x_min = get_boundary_xmin(obj)
            boundary = obj.get_boundary_points();
            x_min = boundary(1,1);
        end

        function x_max = get_boundary_xmax(obj)
            boundary = obj.get_boundary_points();
            x_max = boundary(2,1);
        end

        function y_min = get_boundary_ymin(obj)
            boundary = obj.get_boundary_points();
            y_min = boundary(1,2);
        end

        function y_max = get_boundary_ymax(obj)
            boundary = obj.get_boundary_points();
            y_max = boundary(2,2);
        end
        
        %% 对齐点获取方法
        function alignxy = get_align_point(obj, align_mode)
            % 获取电路的对齐点坐标，调用get_boundary_points计算边界
            % 输入参数:
            %   align_mode - 对齐模式
            %       'cleft' - 左边中心
            %       'cright' - 右边中心
            %       'ctop' - 顶边中心
            %       'cbottom' - 底边中心
            %       'topleft' - 左上角
            %       'topright' - 右上角
            %       'bottomleft' - 左下角
            %       'bottomright' - 右下角
            %       'center' - 中心点
            %
            % 输出:
            %   align_x, align_y - 对齐点的 X, Y 坐标 (μm)
            %
            % 示例:
            %   [x, y] = circuit.get_align_point('cleft');
            %   [x, y] = circuit.get_align_point('center');
            %     边界示意图：
            %          ctop (顶边中心)
            %      +----------------------+
            %      |  topleft     topright|
            % cleft|                      |cright
            %      |         center       |
            %      |bottomleft bottomright|
            %      +----------------------+
            %        cbottom (底边中心)

            arguments
                obj Wcli_circuit
                align_mode (1,:) char {mustBeMember(align_mode, ...
                    {'cleft', 'cright', 'ctop', 'cbot', ...
                    'topleft', 'topright', 'botleft', 'botright', 'cen'})}='cen'
            end

            % 获取边界
            boundary = obj.get_boundary_points();
            x_min = boundary(1, 1);
            y_min = boundary(1, 2);
            x_max = boundary(2, 1);
            y_max = boundary(2, 2);

            % 计算中心坐标
            x_center = (x_min + x_max) / 2;
            y_center = (y_min + y_max) / 2;

            % 根据对齐模式返回坐标
            switch align_mode
                case 'cleft'
                    align_x = x_min;
                    align_y = y_center;
                case 'cright'
                    align_x = x_max;
                    align_y = y_center;
                case 'ctop'
                    align_x = x_center;
                    align_y = y_max;
                case 'cbot'
                    align_x = x_center;
                    align_y = y_min;
                case 'topleft'
                    align_x = x_min;
                    align_y = y_max;
                case 'topright'
                    align_x = x_max;
                    align_y = y_max;
                case 'botleft'
                    align_x = x_min;
                    align_y = y_min;
                case 'botright'
                    align_x = x_max;
                    align_y = y_min;
                case 'cen'
                    align_x = x_center;
                    align_y = y_center;
            end
            alignxy = [align_x, align_y];
        end

        %% 合并单元方法
        function obj = merge_cell(obj, new_circuit0, options)
            % 合并新电路到当前电路（扁平化合并）
            % 支持对齐选项：将新电路的某个边/角与当前电路的某个边/角对齐

            arguments
                obj Wcli_circuit
                new_circuit0 Wcli_circuit  % 必须是 Wcli_circuit 对象
                options.self_pos (1,:) char {mustBeMember(options.self_pos, ...
                    {'none', 'cleft', 'cright', 'ctop', 'cbot', ...
                    'topleft', 'topright', 'botleft', 'botright', 'cen'})} = 'none'
                options.target_pos (1,:) char {mustBeMember(options.target_pos, ...
                    {'', 'cleft', 'cright', 'ctop', 'cbot', ...
                    'topleft', 'topright', 'botleft', 'botright', 'cen'})} = 'cen'
                options.Txy (1,:) double = [0,0]
            end

            % 如果未指定 target_mode，默认与 align_mode 相同
            if isempty(options.target_pos)
                options.target_pos = options.self_pos;
            end

            % 展开新电路为扁平化的多边形列表
            new_circuit = new_circuit0.copy;
            [merge_polys, merge_layers] = new_circuit.flatten_to_polys();

            if isempty(merge_polys)
                warning('新电路为空，无法合并');
                return;
            end

            % 计算对齐偏移量
            if ~strcmp(options.self_pos, 'none')
                % 使用实例方法获取新电路的对齐点
                alignxy = new_circuit.get_align_point(options.self_pos);
                new_align_x = alignxy(1);
                new_align_y = alignxy(2);
                % 使用实例方法获取当前电路的目标对齐点
                
                targetxy = obj.get_align_point(options.target_pos);
                target_x = targetxy(1);
                target_y = targetxy(2);
                % 计算偏移量
                align_offset_x = target_x - new_align_x + options.Txy(1);
                align_offset_y = target_y - new_align_y + options.Txy(2);

                % 对所有新单元应用偏移
                for i = 1:length(merge_polys)
                    merge_polys{i}.transform_shape(0, align_offset_x, align_offset_y);
                end

                fprintf('对齐合并: "%s".%s -> "%s".%s, 偏移 [%.2f, %.2f] μm\n', ...
                    new_circuit.name, options.self_pos, ...
                    obj.name, options.target_pos, ...
                    align_offset_x, align_offset_y);
            else
                fprintf('直接合并: "%s" -> "%s" (无对齐)\n', new_circuit.name, obj.name);
            end

            % 合并到当前电路（扁平化）
            obj.pcells = [obj.pcells, merge_polys];
            obj.laycells = [obj.laycells, merge_layers];

            % 更新相对位置（扁平化后使用绝对坐标）
            new_pos = zeros(length(merge_polys), 2);
            obj.pos_cells = [obj.pos_cells; new_pos];

            fprintf('已合并 %d 个单元（扁平化）\n', length(merge_polys));
        end
        %% GDS 生成方法
        function generate_gds(obj, FileDc, cell_name, lib_name)
            % 生成 GDS 文件（扁平化输出）

            arguments
                obj Wcli_circuit
                FileDc (1,:) char = [obj.name,'.gds']
                cell_name (1,:) char = ''
                lib_name (1,:) char = 'CircuitLib'
            end

            if isempty(cell_name)
                cell_name = obj.name;
            end

            % 递归展开所有单元
            [flat_polys, flat_layers] = obj.flatten_to_polys();

            % 调用批量 GDS 生成函数
            Wcli_poly.generate_multi_flatten_gds(flat_polys, FileDc, ...
                flat_layers, cell_name, lib_name);

            fprintf('circuit GDS gened（Flatten）: %s\n', FileDc);
            fprintf('  num of cells: %d\n', length(flat_polys));
        end

        function generate_multi_cell_gds(obj, FileDc, top_cell_name, lib_name)
            % 生成层级结构的 GDS 文件
            % 每个 Wcli_circuit 子对象和 Wcli_poly/Wcli_wg 对象单独成为一个 cell
            % 创建层级结构：顶层 cell 引用所有子 cell
            %
            % 输入参数:
            %   FileDc - GDS 文件路径
            %   top_cell_name - 顶层 cell 名称（可选，默认使用 obj.name）
            %   lib_name - 库名称（可选，默认 'CircuitLib'）

            arguments
                obj Wcli_circuit
                FileDc (1,:) char
                top_cell_name (1,:) char = ''
                lib_name (1,:) char = 'CircuitLib'
            end

            if isempty(top_cell_name)
                top_cell_name = obj.name;
            end

            % 确保顶层 cell 名称长度为偶数
            if mod(length(top_cell_name), 2) ~= 0
                top_cell_name = [top_cell_name, 'E'];
            end

            % 创建文件夹
            [folder_path, ~, ~] = fileparts(FileDc);
            if ~isempty(folder_path) && ~exist(folder_path, 'dir')
                mkdir(folder_path);
            end

            % 打开文件
            fid = fopen(FileDc, 'w');
            if fid == -1
                error('无法创建文件: %s', FileDc);
            end

            try
                % 写入 GDS 文件头部
                fprintf(fid, 'HEADER 600\r\n');
                fprintf(fid, 'BGNLIB 4/20/2021 12:33:18 4/20/2021 12:33:18 \r\n');
                fprintf(fid, 'LIBNAME %s\r\n', lib_name);
                fprintf(fid, 'UNITS 0.005 1e-009 \r\n');

                % 递归写入所有子 cell
                cell_counter = struct('count', 0);
                obj.write_hierarchy_cells(fid, cell_counter);

                % 写入顶层 cell
                fprintf(fid, 'BGNSTR 4/20/2021 12:33:18 4/20/2021 12:33:18  \r\n');
                fprintf(fid, 'STRNAME %s\r\n', top_cell_name);

                % 在顶层 cell 中引用所有直接子 cell
                for i = 1:length(obj.pcells)
                    cell_obj = obj.pcells{i};

                    if isa(cell_obj, 'Wcli_circuit')
                        % 引用子电路 cell
                        sub_cell_name = cell_obj.name;
                        if mod(length(sub_cell_name), 2) ~= 0
                            sub_cell_name = [sub_cell_name, 'E'];
                        end

                        fprintf(fid, 'SREF \r\n');
                        fprintf(fid, 'SNAME %s\r\n', sub_cell_name);
                        fprintf(fid, 'XY 0:0\r\n');
                        fprintf(fid, 'ENDEL \r\n');

                    elseif isa(cell_obj, 'Wcli_wg') || isa(cell_obj, 'Wcli_poly')
                        % 直接写入几何（或创建子cell）
                        poly_obj = cell_obj;
                        if isa(cell_obj, 'Wcli_wg')
                            poly_obj = cell_obj.to_poly();
                        end

                        % 获取坐标并写入边界
                        if poly_obj.width_mode
                            poly_xy_nm = round(poly_obj.XY_top * 1e3);
                        else
                            poly_xy_nm = round(poly_obj.XY * 1e3);
                        end

                        if ~isequal(poly_xy_nm(1,:), poly_xy_nm(end,:))
                            poly_xy_nm(end+1,:) = poly_xy_nm(1,:);
                        end

                        Wcli_poly.write_boundary(fid, poly_xy_nm, obj.laycells(i));
                    end
                end

                % 写入顶层 cell 结束标记
                fprintf(fid, 'ENDSTR \r\n');

                % 写入库结束标记
                fprintf(fid, 'ENDLIB \r\n');

            catch ME
                fclose(fid);
                rethrow(ME);
            end

            fclose(fid);

            % 显示信息
            fprintf('hierarchy GDS: %s\n', FileDc);
            fprintf('libname: %s\n', lib_name);
            fprintf('top cell: %s\n', top_cell_name);
            fprintf('hier depth: %d\n', obj.get_hierarchy_depth());
        end

        function write_hierarchy_cells(obj, fid, cell_counter)
            % 递归写入层级结构的所有 cell
            % 私有辅助方法

            for i = 1:length(obj.pcells)
                cell_obj = obj.pcells{i};

                if isa(cell_obj, 'Wcli_circuit')
                    % 递归写入子电路的所有 cell
                    cell_obj.write_hierarchy_cells(fid, cell_counter);

                    % 写入子电路自身的 cell
                    sub_cell_name = cell_obj.name;
                    if mod(length(sub_cell_name), 2) ~= 0
                        sub_cell_name = [sub_cell_name, 'E'];
                    end

                    fprintf(fid, 'BGNSTR 4/20/2021 12:33:18 4/20/2021 12:33:18  \r\n');
                    fprintf(fid, 'STRNAME %s\r\n', sub_cell_name);

                    % 引用子电路的所有直接子 cell
                    for j = 1:length(cell_obj.pcells)
                        sub_sub_obj = cell_obj.pcells{j};

                        if isa(sub_sub_obj, 'Wcli_circuit')
                            ref_name = sub_sub_obj.name;
                            if mod(length(ref_name), 2) ~= 0
                                ref_name = [ref_name, 'E'];
                            end

                            fprintf(fid, 'SREF \r\n');
                            fprintf(fid, 'SNAME %s\r\n', ref_name);
                            fprintf(fid, 'XY 0:0\r\n');
                            fprintf(fid, 'ENDEL \r\n');

                        else
                            % 写入几何
                            poly_obj = sub_sub_obj;
                            if isa(sub_sub_obj, 'Wcli_wg')
                                poly_obj = sub_sub_obj.to_poly();
                            end

                            if poly_obj.width_mode
                                poly_xy_nm = round(poly_obj.XY_top * 1e3);
                            else
                                poly_xy_nm = round(poly_obj.XY * 1e3);
                            end

                            if ~isequal(poly_xy_nm(1,:), poly_xy_nm(end,:))
                                poly_xy_nm(end+1,:) = poly_xy_nm(1,:);
                            end

                            Wcli_poly.write_boundary(fid, poly_xy_nm, cell_obj.laycells(j));
                        end
                    end

                    fprintf(fid, 'ENDSTR \r\n');
                    cell_counter.count = cell_counter.count + 1;
                end
            end
        end

        function generate_gdsii(obj, FileDc, gdsII_FileDc, cell_name, lib_name)
            % 生成 GDS 文件并转换为 GDSII 二进制格式

            arguments
                obj Wcli_circuit
                FileDc (1,:) char
                gdsII_FileDc (1,:) char = ''
                cell_name (1,:) char = ''
                lib_name (1,:) char = 'CircuitLib'
            end

            % 生成文本格式 GDS
            obj.generate_gds(FileDc, cell_name, lib_name);

            % 转换为二进制格式
            if isempty(gdsII_FileDc)
                [folder, filename, ~] = fileparts(FileDc);
                gdsII_FileDc = fullfile(folder, ['ii_', filename, '.gds']);
            end

            Wcli_poly.klayout_gds2gdsii(FileDc, gdsII_FileDc);
        end

        %% 绘图方法
        function plot_circuit(obj, fig_handle)
            % 绘制整个电路（递归绘制所有嵌套单元）

            if nargin < 2
                fig_handle = figure;
            else
                figure(fig_handle);
            end

            hold on;

            for i = 1:length(obj.pcells)
                if isa(obj.pcells{i}, 'Wcli_circuit')
                    % 递归绘制子电路
                    obj.pcells{i}.plot_circuit(fig_handle);
                elseif isa(obj.pcells{i}, 'Wcli_wg')
                    obj.pcells{i}.plot_wg_pos();
                else
                    obj.pcells{i}.plot_polygon();
                end
            end

            hold off;
            axis equal;
            title(sprintf('电路: %s (共 %d 个单元, 层级深度 %d)', ...
                obj.name, length(obj.pcells), obj.get_hierarchy_depth()));
            xlabel('X (μm)');
            ylabel('Y (μm)');
            legend('Location', 'best');
        end

        function display_info(obj, indent)
            % 显示电路信息（递归显示层级结构）

            if nargin < 2
                indent = '';
            end

            fprintf('\n%s=== 电路信息: %s ===\n', indent, obj.name);
            fprintf('%s单元数量: %d\n', indent, length(obj.pcells));

            boundary = obj.get_boundary_points();
            fprintf('%s边界范围:\n', indent);
            fprintf('%s  X: [%.3f, %.3f] μm (宽度 %.3f μm)\n', indent, ...
                boundary(1,1), boundary(2,1), obj.get_boundary_dx());
            fprintf('%s  Y: [%.3f, %.3f] μm (高度 %.3f μm)\n', indent, ...
                boundary(1,2), boundary(2,2), obj.get_boundary_dy());

            fprintf('\n%s单元列表:\n', indent);
            fprintf('%s索引\t类型\t\t\t图层\t相对位置 (μm)\n', indent);
            fprintf('%s------------------------------------------------------------\n', indent);

            for i = 1:length(obj.pcells)
                cell_obj = obj.pcells{i};

                if isa(cell_obj, 'Wcli_circuit')
                    type_str = sprintf('Wcli_circuit (%s)', cell_obj.name);
                elseif isa(cell_obj, 'Wcli_wg')
                    type_str = 'Wcli_wg';
                else
                    type_str = 'Wcli_poly';
                end

                fprintf('%s%d\t%-20s\t%d\t(%.2f, %.2f)\n', indent, ...
                    i, type_str, obj.laycells(i), ...
                    obj.pos_cells(i,1), obj.pos_cells(i,2));

                % 递归显示子电路信息
                if isa(cell_obj, 'Wcli_circuit')
                    cell_obj.display_info([indent, '  ']);
                end
            end

            fprintf('%s====================================\n\n', indent);
        end
    end

    %% 静态方法
    methods (Static)
        function circuit = from_arrays(fold_cells, single_cells, fold_layers, single_layers, offset_y)
            % 从 Fold 和 Single 结构数组创建电路

            arguments
                fold_cells (1,:) cell
                single_cells (1,:) cell
                fold_layers (1,:) double
                single_layers (1,:) double
                offset_y (1,1) double = 500
            end

            % 计算 Fold 结构的最大 Y 坐标
            fold_max_y = 0;
            for i = 1:length(fold_cells)
                boundary = fold_cells{i}.get_boundary_points();
                fold_max_y = max(fold_max_y, boundary(2,2));
            end

            % 合并单元和图层
            all_cells = [fold_cells, single_cells];
            all_layers = [fold_layers, single_layers];

            % 计算相对位置
            n_fold = length(fold_cells);
            n_single = length(single_cells);
            pos_cells = zeros(n_fold + n_single, 2);

            % Single 结构向上偏移
            single_offset_y = fold_max_y + offset_y;
            pos_cells(n_fold+1:end, 2) = single_offset_y;

            % 创建电路对象
            circuit = Wcli_circuit(all_cells, all_layers, pos_cells, 'Fold_Single_Circuit');

            fprintf('已创建组合电路: %d 个 Fold 单元 + %d 个 Single 单元\n', n_fold, n_single);
        end
        function klayout_gds2gdsii(input_gds_file, output_gds_file, klayout_exe_path)
            % 使用 KLayout 的 strm2gds.exe 将 GDS 文本格式转换为 GDSII 二进制格式
            %
            % 输入参数:
            %   input_gds_file - 输入 GDS 文件路径（文本格式）
            %   output_gds_file - 输出 GDSII 文件路径（二进制格式）
            %   klayout_exe_path - 可选，KLayout strm2gds.exe 的路径。
            %                      留空时自动从 PATH、APPDATA 和 Program Files 查找。
            %
            % 示例:
            %   % 使用默认 KLayout 路径
            %   Wcli_poly.klayout_gds2gdsii('input.gds', 'output.gds');
            %
            %   % 指定 KLayout 路径
            %   Wcli_poly.klayout_gds2gdsii('input.gds', 'output.gds', ...
            %       'D:\KLayout\strm2gds.exe');

            arguments
                input_gds_file (1,:) char
                output_gds_file (1,:) char
                klayout_exe_path (1,:) char = ''
            end

            % 检查输入文件是否存在
            if ~exist(input_gds_file, 'file')
                error('输入文件不存在: %s', input_gds_file);
            end

            if isempty(klayout_exe_path)
                klayout_exe_path = Wcli_poly.find_klayout_exe('strm2gds');
            end

            % 检查 KLayout 可执行文件是否存在
            if ~exist(klayout_exe_path, 'file')
                error('KLayout strm2gds.exe 不存在: %s\n请检查路径或安装 KLayout', klayout_exe_path);
            end

            % 构建命令
            exe = sprintf('"%s"', klayout_exe_path);
            infile = sprintf('"%s"', input_gds_file);
            outfile = sprintf('"%s"', output_gds_file);
            cmd = sprintf('%s %s %s', exe, infile, outfile);

            [status, result] = system(cmd);

            if status == 0
                fprintf('output gdsii finish!!!\n');
                % 显示文件大小信息
                input_info = dir(input_gds_file);
                output_info = dir(output_gds_file);
                fprintf('Input txt: %.2f KB\n', input_info.bytes / 1024);
                fprintf('Output gdsii: %.2f KB\n', output_info.bytes / 1024);
            else
                fprintf('? 转换失败!\n');
                fprintf('错误信息:\n%s\n', result);
                error('KLayout 转换失败，请检查输入文件格式');
            end
        end
    end
end
