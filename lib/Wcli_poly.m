% Wcli_poly - 带顶底面的3D多边形类
%
% 功能：
%   - 管理带刻蚀角度的3D多边形（顶部和底部坐标）
%   - 提供通用的几何变换（旋转、平移、镜像）
%   - 支持GDS文件生成（单层和多层）
%   - FDTD/HFSS坐标转换
%   - 边界计算和绘图功能
%
% 创建日期: 2025-11-09
% 作者: Based on Wcli_wg architecture

classdef Wcli_poly < handle & matlab.mixin.Copyable

    properties
        XY % 底部坐标 N×2矩阵 [x, y] (μm)
        XY_top % 顶部坐标 N×2矩阵 [x, y] (μm)
        etch_angle % 刻蚀角度 (degrees)
        thickness % 厚度 (μm)
        delta_w % 顶底宽度差 (μm)

        % 开口处定义
        port_edges % 开口处边的索引 M×2矩阵 [index1, index2]
        port_list % 开口处坐标和角度 M×3矩阵 [x, y, angle(rad)]

        width_mode = 1 % 0: bottom width, 1: top width

        % Cell名称
        name (1, :) char = 'poly_obj' % 对象名称，用于 GDS cell 命名
    end

    methods (Access = public)
        %% 构造函数
        function obj = Wcli_poly(xy_input, etch_angle, thickness, port_edges, name)
            % 构造函数
            % 输入:
            %   xy_bottom - 底部坐标 N×2矩阵 [x, y] (μm)
            %   etch_angle - 刻蚀角度 (degrees)
            %   thickness - 厚度 (μm)
            %   port_edges - 开口处索引 M×2矩阵 [index1, index2]
            %                默认: [1, N; N/2+1, N/2+2] (假设N为偶数)

            arguments
                xy_input (:, 2) double = [0, 0; 10, 0; 10, 5; 0, 5; ]
                etch_angle (1, 1) double = 60
                thickness (1, 1) double {mustBePositive} = 0.25
                port_edges (:, 2) double {mustBeInteger, mustBePositive} = []
                name (1, :) char = 'poly_obj'
            end

            obj.etch_angle = etch_angle;
            obj.thickness = thickness;
            obj.delta_w = 2 * thickness * tan((90 - etch_angle) / 180 * pi);
            obj.name = name;

            if obj.width_mode
                obj.XY_top = xy_input;
                [~, obj.XY] = Wcli_poly.Top_bot_polygon_gen(xy_input, obj.delta_w / 2);
            else
                obj.XY = xy_input;
                obj.XY_top = Wcli_poly.Top_bot_polygon_gen(xy_input, obj.delta_w / 2);
            end

            % 初始化开口处
            n_points = size(obj.XY, 1);

            if isempty(port_edges)
                % 默认开口处配置
                if n_points < 4
                    warning('顶点数量少于4，无法创建默认对立开口处');
                    obj.port_edges = [];
                    obj.port_list = [];
                else
                    % 第一个开口: 第1个和最后一个顶点组成的边
                    port1 = [n_points, 1];

                    % 第二个开口: 对面的边（假设是对称多边形）
                    % 找到对面边的索引（大约在多边形的中间位置）
                    mid_idx = round(n_points / 2);

                    if mid_idx == n_points
                        mid_idx = n_points - 1;
                    end

                    port2 = [mid_idx, mid_idx + 1];

                    obj.port_edges = [port1; port2];
                    %                     fprintf('自动创建默认开口处:\n');
                    %                     fprintf('  开口1: 顶点 %d -> %d\n', port1(1), port1(2));
                    %                     fprintf('  开口2: 顶点 %d -> %d\n', port2(1), port2(2));
                end

            else
                % 使用用户指定的开口处
                % 验证索引有效性
                if any(port_edges(:) > n_points) || any(port_edges(:) < 1)
                    error('开口处索引超出范围 (1-%d)', n_points);
                end

                obj.port_edges = port_edges;
                fprintf('使用自定义开口处 (共%d个)\n', size(port_edges, 1));
            end

            % 计算开口处坐标和角度
            obj.update_port_list();
        end

        %% 坐标更新
        function obj = update_xy_top(obj)
            % 根据底部坐标和刻蚀角度更新顶部坐标
            obj.delta_w = 2 * obj.thickness * tan((90 - obj.etch_angle) / 180 * pi);
            obj.XY_top = Wcli_poly.Top_bot_polygon_gen(obj.XY, obj.delta_w / 2);
        end

        function obj = update_xy_bottom(obj)
            % 根据顶部坐标和刻蚀角度更新底部坐标
            obj.delta_w = 2 * obj.thickness * tan((90 - obj.etch_angle) / 180 * pi);
            [~, obj.XY] = Wcli_poly.Top_bot_polygon_gen(obj.XY_top, obj.delta_w / 2);
        end

        %% 开口处（Port）管理方法
        function obj = add_port(obj, index1, index2)
            % 添加开口处
            % 输入:
            %   index1, index2 - 边的两个顶点索引

            arguments
                obj Wcli_poly
                index1 (1, 1) double {mustBeInteger, mustBePositive}
                index2 (1, 1) double {mustBeInteger, mustBePositive}
            end

            % 验证索引有效性
            n_points = size(obj.XY, 1);

            if index1 > n_points || index2 > n_points
                error('顶点索引超出范围 (1-%d)', n_points);
            end

            % 添加到 port_edges
            if isempty(obj.port_edges)
                obj.port_edges = [index1, index2];
            else
                obj.port_edges(end + 1, :) = [index1, index2];
            end

            % 更新 port_list
            obj.update_port_list();

            fprintf('已添加开口处: 顶点 %d -> %d\n', index1, index2);
        end

        function obj = remove_port(obj, port_index)
            % 删除指定开口处
            % 输入:
            %   port_index - 要删除的开口处索引

            arguments
                obj Wcli_poly
                port_index (1, 1) double {mustBeInteger, mustBePositive}
            end

            if isempty(obj.port_edges) || port_index > size(obj.port_edges, 1)
                error('开口处索引无效');
            end

            obj.port_edges(port_index, :) = [];
            obj.update_port_list();

            fprintf('已删除开口处 %d\n', port_index);
        end

        function obj = clear_ports(obj)
            % 清空所有开口处
            obj.port_edges = [];
            obj.port_list = [];
            fprintf('已清空所有开口处\n');
        end

        function obj = update_port_list(obj)
            % 根据 port_edges 更新 port_list
            % 自动计算每个开口的中心坐标和角度方向

            if isempty(obj.port_edges)
                obj.port_list = [];
                return;
            end

            n_ports = size(obj.port_edges, 1);
            obj.port_list = zeros(n_ports, 3);

            for i = 1:n_ports
                idx1 = obj.port_edges(i, 1);
                idx2 = obj.port_edges(i, 2);

                % 获取两个顶点坐标
                if obj.width_mode
                    p1 = obj.XY_top(idx1, :);
                    p2 = obj.XY_top(idx2, :);
                else
                    p1 = obj.XY(idx1, :);
                    p2 = obj.XY(idx2, :);
                end

                % 计算中心点
                center_x = (p1(1) + p2(1)) / 2;
                center_y = (p1(2) + p2(2)) / 2;

                % 计算边的方向角度（从p1指向p2）
                dx = p2(1) - p1(1);
                dy = p2(2) - p1(2);
                angle = atan2(dy, dx); % 弧度制

                % 法向量方向（顺时针旋转90度）
                normal_angle = angle - pi / 2;

                obj.port_list(i, :) = [center_x, center_y, normal_angle];
            end

        end

        function [x, y, angle] = get_port(obj, port_index)
            % 获取指定开口处的坐标和角度
            % 输出:
            %   x, y - 开口中心坐标 (μm)
            %   angle - 法向角度 (rad)

            arguments
                obj Wcli_poly
                port_index (1, 1) double {mustBeInteger, mustBePositive}
            end

            if isempty(obj.port_list) || port_index > size(obj.port_list, 1)
                error('开口处索引无效');
            end

            x = obj.port_list(port_index, 1);
            y = obj.port_list(port_index, 2);
            angle = obj.port_list(port_index, 3);
        end
        function xy = get_port_xy(obj, port_index)
            % 获取指定开口处的坐标和角度
            % 输出:
            %   x, y - 开口中心坐标 (μm)
            %   angle - 法向角度 (rad)

            arguments
                obj Wcli_poly
                port_index (1, 1) double {mustBeInteger, mustBePositive}
            end

            if isempty(obj.port_list) || port_index > size(obj.port_list, 1)
                error('开口处索引无效');
            end

            x = obj.port_list(port_index, 1);
            y = obj.port_list(port_index, 2);
            xy = [x,y];
        end

        function display_ports(obj)
            % 显示所有开口处信息

            if isempty(obj.port_edges)
                fprintf('当前无开口处定义\n');
                return;
            end

            fprintf('\n=== 开口处列表 ===\n');
            fprintf('索引\t顶点对\t\t中心坐标 (μm)\t\t\t角度 (deg)\n');
            fprintf('------------------------------------------------------------\n');

            for i = 1:size(obj.port_edges, 1)
                idx1 = obj.port_edges(i, 1);
                idx2 = obj.port_edges(i, 2);
                x = obj.port_list(i, 1);
                y = obj.port_list(i, 2);
                angle_deg = obj.port_list(i, 3) * 180 / pi;

                fprintf('%d\t[%d, %d]\t\t(%.3f, %.3f)\t\t%.2f\n', ...
                    i, idx1, idx2, x, y, angle_deg);
            end

        end

        function plot_ports(obj, fig_handle)
            % 在多边形图上标注开口处
            obj.update_port_list;

            if nargin < 2
                fig_handle = gcf;
            end

            if isempty(obj.port_list)
                warning('无开口处可绘制');
                return;
            end

            figure(fig_handle);
            hold on;

            % 绘制开口处位置和方向
            for i = 1:size(obj.port_list, 1)
                x = obj.port_list(i, 1);
                y = obj.port_list(i, 2);
                angle = obj.port_list(i, 3);
                % 绘制法向箭头（指示方向）
                arrow_length = obj.get_boundary_dx() * 0.1; % 箭头长度为边界宽度的10 %
                dx = arrow_length * cos(angle);
                dy = arrow_length * sin(angle);
                quiver(x, y, dx, dy, 2, 'LineWidth', 2, 'DisplayName', sprintf('port%d', i));
            end

            legend

            hold off;
        end

        function obj = flip_ports(obj)
            % 翻转端口顺序（不改变顶点顺序）
            %
            % 功能:
            %   反转 port_edges 的行顺序（port 1 <-> port 2, port 3 <-> port 4, ...）
            %   自动更新 port_list
            %
            % 输出:
            %   obj - 翻转后的对象（支持链式调用）

            if isempty(obj.port_edges)
                warning('无端口可翻转');
                return;
            end

            % 反转 port_edges 的行顺序
            obj.port_edges = flipud(obj.port_edges);

            % 更新 port_list
            obj.update_port_list();

        end

        %% 几何变换方法
        function obj = transform_shape(obj, theta, T_x, T_y)
            % 旋转和平移变换（同时变换顶底面）
            % 输入:
            %   theta - 旋转角度 (弧度)
            %   T_x - X方向平移量 (μm)
            %   T_y - Y方向平移量 (μm)

            arguments
                obj Wcli_poly
                theta (1, 1) double = 0
                T_x (1, 1) double = 0
                T_y (1, 1) double = 0
            end

            obj.XY = Wcli_poly.rotate_translate_xy(obj.XY, theta, T_x, T_y);
            obj.XY_top = Wcli_poly.rotate_translate_xy(obj.XY_top, theta, T_x, T_y);
            % 更新开口处坐标
            if ~isempty(obj.port_edges)
                obj.update_port_list();
            end

        end

        function obj = mirror_translate_shape(obj, axis, T_x, T_y)
            % 镜像和平移变换（同时变换顶底面）
            % 输入:
            %   axis - 镜像轴 'x'/'y'/'xy'
            %   T_x - X方向平移量 (μm)
            %   T_y - Y方向平移量 (μm)

            arguments
                obj Wcli_poly
                axis (1, :) char {mustBeMember(axis, {'x', 'y', 'xy'})} = 'x'
                T_x (1, 1) double = 0
                T_y (1, 1) double = 0
            end

            obj.XY = Wcli_poly.mirror_translate_xy(obj.XY, axis, T_x, T_y);
            obj.XY_top = Wcli_poly.mirror_translate_xy(obj.XY_top, axis, T_x, T_y);

            if ispolycw(obj.XY(:, 1), obj.XY(:, 2))
                obj.XY = flipud(obj.XY);
                obj.XY_top = flipud(obj.XY_top);
                obj.port_edges = size(obj.XY, 1) - flip(obj.port_edges, 2) + 1;
            end

            % 更新开口处坐标
            if ~isempty(obj.port_edges)
                obj.update_port_list();
            end

        end

        function obj = center_to_position(obj, center_x, center_y)
            % 将多边形居中到指定位置
            % 输入:
            %   center_x - 目标中心x坐标 (μm)
            %   center_y - 目标中心y坐标 (μm)

            arguments
                obj Wcli_poly
                center_x (1, 1) double = 0
                center_y (1, 1) double = 0
            end

            % 计算当前中心
            [x_min, x_max, y_min, y_max] = obj.get_boundary();
            current_center_x = (x_min + x_max) / 2;
            current_center_y = (y_min + y_max) / 2;

            % 计算平移量
            T_x = center_x - current_center_x;
            T_y = center_y - current_center_y;

            % 应用平移
            obj.transform_shape(0, T_x, T_y);

            fprintf('多边形已居中:\n');
            fprintf('  原中心: (%.3f, %.3f) μm\n', current_center_x, current_center_y);
            fprintf('  新中心: (%.3f, %.3f) μm\n', center_x, center_y);
        end

        function obj = align_edge(obj, target_x, target_y, edge_side)
            % 将边界框指定边的中心对齐到目标坐标
            % 输入:
            %   target_x - 目标x坐标 (μm)
            %   target_y - 目标y坐标 (μm)
            %   edge_side - 边的位置 'left'/'right'/'top'/'bottom'

            arguments
                obj Wcli_poly
                target_x (1, 1) double = 0
                target_y (1, 1) double = 0
                edge_side (1, :) char {mustBeMember(edge_side, {'left', 'right', 'top', 'bottom'})} = 'left'
            end

            % 获取当前边界 [x_min, y_min; x_max, y_max]
            boundary = obj.get_boundary_points();
            x_min = boundary(1, 1);
            y_min = boundary(1, 2);
            x_max = boundary(2, 1);
            y_max = boundary(2, 2);

            % 计算边界中心
            center_x = (x_min + x_max) / 2;
            center_y = (y_min + y_max) / 2;

            % 根据边的位置计算当前边的中心坐标和需要的平移量
            switch edge_side
                case 'left'
                    % 左边中心: (x_min, center_y)
                    current_edge_x = x_min;
                    current_edge_y = center_y;
                    T_x = target_x - current_edge_x;
                    T_y = target_y - current_edge_y;

                case 'right'
                    % 右边中心: (x_max, center_y)
                    current_edge_x = x_max;
                    current_edge_y = center_y;
                    T_x = target_x - current_edge_x;
                    T_y = target_y - current_edge_y;

                case 'top'
                    % 上边中心: (center_x, y_max)
                    current_edge_x = center_x;
                    current_edge_y = y_max;
                    T_x = target_x - current_edge_x;
                    T_y = target_y - current_edge_y;

                case 'bottom'
                    % 下边中心: (center_x, y_min)
                    current_edge_x = center_x;
                    current_edge_y = y_min;
                    T_x = target_x - current_edge_x;
                    T_y = target_y - current_edge_y;
            end

            % 应用平移
            obj.transform_shape(0, T_x, T_y);
        end
        function obj = align_port(obj, options)
            % 将对象的指定端口对齐到目标坐标和角度
            %
            % 输入参数（名称-值对）:
            %   port_idx - 要对齐的端口索引，默认 1
            %   target_x - 目标x坐标 (μm)，默认 0
            %   target_y - 目标y坐标 (μm)，默认 0
            %   target_angle - 目标角度 (弧度)，默认 0
            %   align_angle - 是否对齐角度，默认 true
            %
            % 用法示例:
            %   obj.align_port('port_idx', 1, 'target_x', 100, 'target_y', 50);
            %   obj.align_port('port_idx', 2, 'target_x', 0, 'target_y', 0, 'target_angle', pi/2);
            %   obj.align_port('port_idx', 1, 'target_x', 100, 'target_y', 50, 'align_angle', false);

            arguments
                obj Wcli_poly
                options.port_idx (1, 1) double {mustBeInteger, mustBePositive} = 1
                options.tar_xy (1, 2) double = [0, 0]
                options.target_angle (1, 1) double = 0
                options.align_angle (1, 1) logical = false
            end

            % 验证端口索引
            if isempty(obj.port_list) || options.port_idx > size(obj.port_list, 1)
                error('端口索引 %d 无效，当前对象有 %d 个端口', ...
                    options.port_idx, size(obj.port_list, 1));
            end

            % 获取当前端口的坐标和角度
            current_x = obj.port_list(options.port_idx, 1);
            current_y = obj.port_list(options.port_idx, 2);
            current_angle = obj.port_list(options.port_idx, 3);

            % 如果需要对齐角度，先旋转
            if options.align_angle
                % 计算需要的旋转角度
                rotation_angle = options.target_angle - current_angle;

                % 绕当前端口位置旋转
                % 先平移使端口到原点
                obj.transform_shape(0, -current_x, -current_y);

                % 旋转
                obj.transform_shape(rotation_angle, 0, 0);

                % 平移到目标位置
                obj.transform_shape(0, options.tar_xy(1), options.tar_xy(2));
            else
                % 只平移，不旋转
                T_x = options.tar_xy(1) - current_x;
                T_y = options.tar_xy(2) - current_y;
                obj.transform_shape(0, T_x, T_y);
            end

        end

        function obj = move_to(obj, align_mode, targetxy)
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
                obj Wcli_poly
                align_mode (1, :) char {mustBeMember(align_mode, ...
                    {'cleft', 'cright', 'ctop', 'cbot', ...
                    'topleft', 'topright', 'botleft', 'botright', 'cen'})} = 'cleft'
                targetxy (1, 2) double = [0, 0]
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
        function next_obj = align_poly(obj, next_obj, align_mode, targetxy)
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
                obj Wcli_poly
                next_obj Wcli_poly
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
                obj Wcli_poly
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

        %% 多边形拼接方法
        function obj = merge_polys(obj, next_poly, offset_x, offset_y, remove_con_points, obj_port_idx, next_port_idx)
            % 将另一个 Wcli_poly 对象拼接到当前对象
            % 输入:
            %   next_poly - 要拼接的 Wcli_poly 对象
            %   offset_x - X方向附加偏移量 (μm)，默认0
            %   offset_y - Y方向附加偏移量 (μm)，默认0
            %   remove_connection_points - 是否删除连接处的重复点，默认true
            %   obj_port_idx - 当前对象使用的开口索引，默认2（右侧）
            %   next_port_idx - 下一个对象使用的开口索引，默认1（左侧）

            arguments
                obj Wcli_poly
                next_poly Wcli_poly
                offset_x (1, 1) double = 0
                offset_y (1, 1) double = 0
                remove_con_points (1, 1) logical = true
                obj_port_idx (1, 1) double {mustBeInteger, mustBePositive} = 2
                next_port_idx (1, 1) double {mustBeInteger, mustBePositive} = 1
            end

            % 验证 etch_angle 和 thickness 是否一致
            if abs(obj.etch_angle - next_poly.etch_angle) > 1e-6 || ...
                    abs(obj.thickness - next_poly.thickness) > 1e-6
                warning('刻蚀角度或厚度不匹配');
            end

            % 验证开口处索引
            if obj_port_idx > size(obj.port_edges, 1)
                error('当前对象开口索引 %d 超出范围 (1-%d)', obj_port_idx, size(obj.port_edges, 1));
            end

            if next_port_idx > size(next_poly.port_edges, 1)
                error('下一对象开口索引 %d 超出范围 (1-%d)', next_port_idx, size(next_poly.port_edges, 1));
            end

            % 复制下一个对象（避免修改原对象）
            next_poly_copy = next_poly.copy();

            np_obj = size(obj.XY, 1); %A的点数
            np_next = size(next_poly_copy.XY, 1); %B的点数
            nport_obj = size(obj.port_list, 1); %A的端口数目
            nport_next = size(next_poly_copy.port_list, 1); %B的端口数目

            % 获取当前对象连接开口的坐标和角度
            [obj_port_x, obj_port_y, obj_port_angle] = obj.get_port(obj_port_idx);

            % 获取下一个对象连接开口的坐标和角度
            [~, ~, next_port_angle] = next_poly_copy.get_port(next_port_idx);

            % 计算需要的旋转角度（使两个开口方向相反）
            % 相反方向意味着角度差为π
            angle_diff = obj_port_angle - next_port_angle;
            rotation_angle = angle_diff + pi; % 旋转使开口相对

            % 旋转下一个对象（绕其开口中心旋转）
            next_poly_copy.transform_shape(rotation_angle);

            % 重新计算旋转后的开口坐标
            next_poly_copy.update_port_list();
            [next_port_x_rotated, next_port_y_rotated, ~] = next_poly_copy.get_port(next_port_idx);

            % 计算平移量（将下一个对象的开口移到当前对象的开口位置）
            T_x = obj_port_x - next_port_x_rotated + offset_x;
            T_y = obj_port_y - next_port_y_rotated + offset_y;

            % 平移下一个对象
            next_poly_copy.transform_shape(0, T_x, T_y);

            % 获取连接处的顶点索引
            obj_con_edge = obj.port_edges(obj_port_idx, :);
            next_con_edge = next_poly_copy.port_edges(next_port_idx, :);

            % 处理底部坐标拼接
            obj_XY = obj.XY;
            next_XY = next_poly_copy.XY;
            obj_XY_top = obj.XY_top;
            next_XY_top = next_poly_copy.XY_top;

            obj_port_vec = diff(obj_XY(obj_con_edge, :));
            next_port_vec = diff(next_XY(next_con_edge, :));

            if dot(obj_port_vec, next_port_vec) > 0
                next_XY = flip(next_XY);
                next_XY_top = flip(next_XY_top);
                next_con_edge = size(next_XY, 1) - next_con_edge + 1;
                next_con_edge = flip(next_con_edge);
            end

            obj_ind_lis = [obj_con_edge(2):np_obj, 1:mod(obj_con_edge(1), np_obj)];
            next_ind_lis = [next_con_edge(2):np_next, 1:mod(next_con_edge(1), np_next)];
            new_obj_XY = [obj_XY(obj_ind_lis, :); next_XY(next_ind_lis, :)];
            new_obj_XY_top = [obj_XY_top(obj_ind_lis, :); next_XY_top(next_ind_lis, :)];

            if remove_con_points
                remove_index = (obj_ind_lis == obj_con_edge(1)) | (obj_ind_lis == obj_con_edge(2));
                obj_ind_lis(remove_index) = [];
                new_obj_XY(remove_index, :) = [];
                new_obj_XY_top(remove_index, :) = [];
                np_obj = np_obj - 2; %减去重合的两个点
            end

            obj_left_edge_index = setdiff(1:nport_obj, obj_port_idx);
            next_left_edge_index = setdiff(1:nport_next, next_port_idx);
            new_port_edge = ones(length(obj_left_edge_index) + length(next_left_edge_index), 2);

            for i = 1:nport_obj - 1
                temp_edge = obj.port_edges(obj_left_edge_index(i), :);
                new_port_edge(i, :) = find((obj_ind_lis == temp_edge(1)) | (obj_ind_lis == temp_edge(2)));
            end

            for i = 1:nport_next - 1
                temp_edge = next_poly_copy.port_edges(next_left_edge_index(i), :);
                new_port_edge(i + nport_obj - 1, :) = find((next_ind_lis == temp_edge(1)) | (next_ind_lis == temp_edge(2))) + np_obj;
            end

            %更新属性
            obj.XY = new_obj_XY;
            obj.XY_top = new_obj_XY_top;
            obj.port_edges = new_port_edge;

            if obj.width_mode
                obj.update_xy_bottom;
            else
                obj.update_xy_top;
            end

            obj.update_port_list;
        end

        function obj = merge_polys_nv(obj, next_poly, options)
            % MERGE_POLYS_NV 将另一个 Wcli_poly 对象拼接到当前对象（名称-值参数版本）
            %
            % 输入参数:
            %   obj - 当前 Wcli_poly 对象
            %   next_poly - 要拼接的 Wcli_poly 对象
            %
            % 名称-值参数:
            %   ofs_xy - XY方向附加偏移量 [x, y] (μm)，默认 [0, 0]
            %   rm_pts - 是否删除连接处的重复点，默认 true
            %   p1 - 当前对象使用的端口索引，默认 2（右侧）
            %   p2 - 下一个对象使用的端口索引，默认 1（左侧）
            %
            % 示例:
            %   obj.merge_polys_nv(next_poly, ofs_xy=[0.5, 0.2]);
            %   obj.merge_polys_nv(next_poly, p1=1, p2=2);

            arguments
                obj Wcli_poly
                next_poly Wcli_poly
                options.ofs_xy (1, 2) double = [0, 0]
                options.rm_pts (1, 1) logical = true
                options.p1 (1, 1) double {mustBeInteger, mustBePositive} = 2
                options.p2 (1, 1) double {mustBeInteger, mustBePositive} = 1
            end

            % 验证 etch_angle 和 thickness 是否一致
            if abs(obj.etch_angle - next_poly.etch_angle) > 1e-6 || ...
                    abs(obj.thickness - next_poly.thickness) > 1e-6
                warning('刻蚀角度或厚度不匹配');
            end

            % 验证开口处索引
            if options.p1 > size(obj.port_edges, 1)
                error('当前对象开口索引 %d 超出范围 (1-%d)', options.p1, size(obj.port_edges, 1));
            end

            if options.p2 > size(next_poly.port_edges, 1)
                error('下一对象开口索引 %d 超出范围 (1-%d)', options.p2, size(next_poly.port_edges, 1));
            end

            % 复制下一个对象（避免修改原对象）
            next_poly_copy = next_poly.copy();

            np_obj = size(obj.XY, 1); %A的点数
            np_next = size(next_poly_copy.XY, 1); %B的点数
            nport_obj = size(obj.port_list, 1); %A的端口数目
            nport_next = size(next_poly_copy.port_list, 1); %B的端口数目

            % 获取当前对象连接开口的坐标和角度
            [obj_port_x, obj_port_y, obj_port_angle] = obj.get_port(options.p1);

            % 获取下一个对象连接开口的坐标和角度
            [~, ~, next_port_angle] = next_poly_copy.get_port(options.p2);

            % 计算需要的旋转角度（使两个开口方向相反）
            % 相反方向意味着角度差为π
            angle_diff = obj_port_angle - next_port_angle;
            rotation_angle = angle_diff + pi; % 旋转使开口相对

            % 旋转下一个对象（绕其开口中心旋转）
            next_poly_copy.transform_shape(rotation_angle);

            % 重新计算旋转后的开口坐标
            next_poly_copy.update_port_list();
            [next_port_x_rotated, next_port_y_rotated, ~] = next_poly_copy.get_port(options.p2);

            % 计算平移量（将下一个对象的开口移到当前对象的开口位置）
            T_x = obj_port_x - next_port_x_rotated + options.ofs_xy(1);
            T_y = obj_port_y - next_port_y_rotated + options.ofs_xy(2);

            % 平移下一个对象
            next_poly_copy.transform_shape(0, T_x, T_y);

            % 获取连接处的顶点索引
            obj_con_edge = obj.port_edges(options.p1, :);
            next_con_edge = next_poly_copy.port_edges(options.p2, :);

            % 处理底部坐标拼接
            obj_XY = obj.XY;
            next_XY = next_poly_copy.XY;
            obj_XY_top = obj.XY_top;
            next_XY_top = next_poly_copy.XY_top;

            obj_port_vec = diff(obj_XY(obj_con_edge, :));
            next_port_vec = diff(next_XY(next_con_edge, :));

            if dot(obj_port_vec, next_port_vec) > 0
                next_XY = flip(next_XY);
                next_XY_top = flip(next_XY_top);
                next_con_edge = size(next_XY, 1) - next_con_edge + 1;
                next_con_edge = flip(next_con_edge);
            end

            obj_ind_lis = [obj_con_edge(2):np_obj, 1:mod(obj_con_edge(1), np_obj)];
            next_ind_lis = [next_con_edge(2):np_next, 1:mod(next_con_edge(1), np_next)];
            new_obj_XY = [obj_XY(obj_ind_lis, :); next_XY(next_ind_lis, :)];
            new_obj_XY_top = [obj_XY_top(obj_ind_lis, :); next_XY_top(next_ind_lis, :)];

            if options.rm_pts
                remove_index = (obj_ind_lis == obj_con_edge(1)) | (obj_ind_lis == obj_con_edge(2));
                obj_ind_lis(remove_index) = [];
                new_obj_XY(remove_index, :) = [];
                new_obj_XY_top(remove_index, :) = [];
                np_obj = np_obj - 2; %减去重合的两个点
            end

            obj_left_edge_index = setdiff(1:nport_obj, options.p1);
            next_left_edge_index = setdiff(1:nport_next, options.p2);
            new_port_edge = ones(length(obj_left_edge_index) + length(next_left_edge_index), 2);

            for i = 1:nport_obj - 1
                temp_edge = obj.port_edges(obj_left_edge_index(i), :);
                new_port_edge(i, :) = find((obj_ind_lis == temp_edge(1)) | (obj_ind_lis == temp_edge(2)));
            end

            for i = 1:nport_next - 1
                temp_edge = next_poly_copy.port_edges(next_left_edge_index(i), :);
                new_port_edge(i + nport_obj - 1, :) = find((next_ind_lis == temp_edge(1)) | (next_ind_lis == temp_edge(2))) + np_obj;
            end

            %更新属性
            obj.XY = new_obj_XY;
            obj.XY_top = new_obj_XY_top;
            obj.port_edges = new_port_edge;

            if obj.width_mode
                obj.update_xy_bottom;
            else
                obj.update_xy_top;
            end

            obj.update_port_list;
        end

        function obj = merge_multiple_polys(obj, offset_x, offset_y, remove_points, varargin)
            % 批量拼接多个 Wcli_poly 对象
            % 输入:
            %   offset_x - X方向偏移量向量 (μm)
            %   offset_y - Y方向偏移量向量 (μm)
            %   remove_points - 是否删除连接点的向量 (logical)
            %   varargin - 其他 Wcli_poly 对象

            arguments
                obj Wcli_poly
                offset_x (1, :) double = 0
                offset_y (1, :) double = 0
                remove_points (1, :) logical = true
            end

            arguments (Repeating)
                varargin
            end

            num_structures = length(varargin);

            if num_structures == 0
                warning('没有提供要拼接的对象');
                return;
            end

            % 扩展参数向量到足够长度
            if length(offset_x) < num_structures
                offset_x = [offset_x, repmat(offset_x(end), 1, num_structures - length(offset_x))];
            end

            if length(offset_y) < num_structures
                offset_y = [offset_y, repmat(offset_y(end), 1, num_structures - length(offset_y))];
            end

            if length(remove_points) < num_structures
                remove_points = [remove_points, repmat(remove_points(end), 1, num_structures - length(remove_points))];
            end

            % 逐个拼接
            for i = 1:num_structures
                next_poly = varargin{i};

                % 使用当前对象的开口2和下一个对象的开口1
                obj.merge_polys(next_poly, offset_x(i), offset_y(i), remove_points(i), 2, 1);

                fprintf('--- 完成第 %d/%d 个拼接 ---\n', i, num_structures);
            end

            fprintf('批量拼接完成，共拼接 %d 个对象\n', num_structures);
        end

        %% 2D投影方法
        function xy_2d = get_2d_projection(obj)
            % 获取2D投影坐标
            % 输入:
            %   use_top - true:返回顶部坐标, false:返回底部坐标
            % 输出:
            %   xy_2d - N×2坐标矩阵

            arguments
                obj Wcli_poly
            end

            if obj.width_mode
                xy_2d = obj.XY_top;
            else
                xy_2d = obj.XY;
            end

        end

        %% 边界计算方法
        function output = get_boundary_points(obj)
            % 获取整体边界（考虑顶底面选择）
            if obj.width_mode
                all_x = obj.XY_top(:, 1);
                all_y = obj.XY_top(:, 2);
            else
                all_x = obj.XY(:, 1);
                all_y = obj.XY(:, 2);
            end

            x_min = min(all_x);
            x_max = max(all_x);
            y_min = min(all_y);
            y_max = max(all_y);
            output = [x_min, y_min; x_max, y_max];
        end

        function dx = get_boundary_dx(obj)
            output = obj.get_boundary_points();
            dx = output(2) - output(1);
        end

        function dy = get_boundary_dy(obj)
            output = obj.get_boundary_points();
            dy = output(4) - output(3);
        end

        function x_min = get_boundary_xmin(obj)
            oustput = obj.get_boundary_points();
            x_min = oustput(1);
        end

        function x_max = get_boundary_xmax(obj)
            output = obj.get_boundary_points();
            x_max = output(2);
        end

        function y_min = get_boundary_ymin(obj)
            ouput = obj.get_boundary_points();
            y_min = ouput(3);
        end

        function y_max = get_boundary_ymax(obj)
            output = obj.get_boundary_points();
            y_max = output(4);
        end

        function alignxy = get_align_point(obj, align_mode)
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
                obj Wcli_poly
                align_mode (1, :) char {mustBeMember(align_mode, ...
                    {'cleft', 'cright', 'ctop', 'cbot', ...
                    'topleft', 'topright', 'botleft', 'botright', 'cen'})} = 'cen'
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

        %% FDTD/HFSS转换方法
        function vtx = posdata2fdtd(obj)
            % FDTD 3D顶点数据
            h_wg = obj.thickness;
            XY_bot_nm = round(obj.XY * 1e3);
            XY_top_nm = round(obj.XY_top * 1e3);

            Bot_xyz = [XY_bot_nm, zeros(size(XY_bot_nm, 1), 1)];
            Top_xyz = [XY_top_nm, ones(size(XY_top_nm, 1), 1) * h_wg * 1e3];

            vtx = [Bot_xyz; Top_xyz];
            % vtx = [Bot_xyz; flip(Top_xyz)];
        end

        function poly2d = postohfss2d(obj)
            % HFSS 2D投影（整数nm单位）
            arguments
                obj Wcli_poly
            end

            if obj.width_mode
                poly2d = round(obj.XY_top * 1e3);
            else
                poly2d = round(obj.XY * 1e3);
            end

            % 确保闭合
            if ~isequal(poly2d(1, :), poly2d(end, :))
                poly2d(end + 1, :) = poly2d(1, :);
            end

        end

        %% GDS生成方法
        function generate_gds(obj, FileDc, layers, cell_name)
            % 生成GDS文件（双层：底部和顶部）
            arguments
                obj Wcli_poly
                FileDc (1, :) char
                layers (1, 1) double {mustBeInteger, mustBePositive} = 2
                cell_name (1, :) char = 'Polygon3D'
            end

            if obj.width_mode
                poly_xy_nm = round(obj.XY_top * 1e3);
            else
                poly_xy_nm = round(obj.XY * 1e3);
            end

            Wcli_poly.generate_gds_from_coords(FileDc, {poly_xy_nm}, layers, cell_name);
        end

        %% 绘图方法
        function plot_polygon(obj, fig_handle)
            % 绘制3D多边形投影（带坐标顺序箭头）
            % 输入:
            %   fig_handle - 可选的图窗句柄

            if nargin < 2
                fig_handle = gcf;
            end

            % 设置图窗
            figure(fig_handle);
            set(gcf, 'Name', '3D Polygon Projection');

            % 绘制底部多边形
            plot(obj.XY(:, 1), obj.XY(:, 2), '-', 'LineWidth', 1.5, 'DisplayName', 'Bottom', 'Color', '#0072bd');
            hold on;
            % 底部坐标顺序箭头
            scale_factor = 0.1;
            x_bot = obj.XY(:, 1);
            y_bot = obj.XY(:, 2);
            quiver(x_bot(1:end - 1), y_bot(1:end - 1), ...
                diff(x_bot) * scale_factor, diff(y_bot) * scale_factor, 0, ...
                'r', 'LineWidth', 1.5, 'DisplayName', 'Dir-bot');
            % 绘制顶部多边形
            plot(obj.XY_top(:, 1), obj.XY_top(:, 2), '--', 'LineWidth', 1.5, 'DisplayName', 'Top', 'Color', '#edb120');

            % 顶部坐标顺序箭头
            x_top = obj.XY_top(:, 1);
            y_top = obj.XY_top(:, 2);
            quiver(x_top(1:end - 1), y_top(1:end - 1), ...
                diff(x_top) * scale_factor, diff(y_top) * scale_factor, 0, ...
                'g', 'LineWidth', 1.5, 'DisplayName', 'Dir-top');

            % 标记起点和终点
            plot(obj.XY(1, 1), obj.XY(1, 2), 'ro', 'MarkerSize', 12, 'DisplayName', 'Bottom Start');

            plot(obj.XY_top(1, 1), obj.XY_top(1, 2), 'g*', 'MarkerSize', 8, 'DisplayName', 'Top Start');

            obj.plot_ports(fig_handle); %画端口
            hold on;
            quiver(x_bot(end), y_bot(end), ...
                - (x_bot(end) - x_bot(1)), - (y_bot(end) - y_bot(1)), 1, ...
                '--r', 'LineWidth', 1.5, 'DisplayName', 'End to start');
            quiver(x_top(end), y_top(end), ...
                - (x_top(end) - x_top(1)), - (y_top(end) - y_top(1)), 1, ...
                '--g', 'LineWidth', 1.5, 'DisplayName', 'End to start');
            hold off;
            legend('Location', 'eastoutside');
            axis equal;
            title('3D Polygon Projection');
            xlabel('X (μm)');
            ylabel('Y (μm)');
        end

        function plot_3d(obj, fig_handle)
            % 绘制真3D视图：根据底/顶点画简单棱柱（不绘制箭头，保持实现简单）
            if nargin < 2
                fig_handle = gcf;
            end

            figure(fig_handle);
            clf;
            hold on;

            h = obj.thickness;

            % 准备顶点（去掉重复的闭合点）
            Bot = obj.XY;
            Top = obj.XY_top;

            if size(Bot, 1) > 1 && isequal(Bot(1, :), Bot(end, :))
                Bot = Bot(1:end - 1, :);
            end

            if size(Top, 1) > 1 && isequal(Top(1, :), Top(end, :))
                Top = Top(1:end - 1, :);
            end

            % 保证顶点数量一致
            N = min(size(Bot, 1), size(Top, 1));
            Bot = Bot(1:N, :);
            Top = Top(1:N, :);

            % 绘制底面与顶面（简单颜色区分）
            patch('XData', Bot(:, 1), 'YData', Bot(:, 2), 'ZData', zeros(N, 1), ...
                'FaceColor', '#4f81bd', 'EdgeColor', 'k', 'FaceAlpha', 1, 'DisplayName', 'Bottom');
            patch('XData', Top(:, 1), 'YData', Top(:, 2), 'ZData', ones(N, 1) * h, ...
                'FaceColor', '#4f81bd', 'EdgeColor', 'k', 'FaceAlpha', 1, 'DisplayName', 'Top');
            legend;

            % 向量化绘制侧面（一次性绘制所有四边形）
            % 构造所有侧面的顶点矩阵
            idx1 = 1:N;
            idx2 = [2:N, 1]; % 循环索引

            % 每个侧面4个顶点: Bot(i) -> Bot(j) -> Top(j) -> Top(i)
            X_sides = [Bot(idx1, 1)'; Bot(idx2, 1)'; Top(idx2, 1)'; Top(idx1, 1)'];
            Y_sides = [Bot(idx1, 2)'; Bot(idx2, 2)'; Top(idx2, 2)'; Top(idx1, 2)'];
            Z_sides = [zeros(1, N); zeros(1, N); ones(1, N) * h; ones(1, N) * h];

            % 一次性绘制所有侧面
            patch('XData', X_sides, 'YData', Y_sides, 'ZData', Z_sides, ...
                'FaceColor', '#4f81bd', 'FaceAlpha', 0.8, 'EdgeColor', 'k');

            % 照明与视图（简单设置）
            %             lighting phong;
            %             camlight headlight;
            %             material dull;

            hold off;
            view(3);
            xlabel('X (μm)');
            ylabel('Y (μm)');
            zlabel('Z (μm)');
            title('3D Polygon Structure');
        end
                % 在 %% 绘图方法 部分添加以下方法（在 plot_polygon 方法之前或之后）
        
        function plot_2d(obj, options)
            % 绘制 2D 多边形填充图
            % 
            % 名称-值参数:
            %   fig_handle   - 图窗句柄，默认使用当前图窗
            %   face_color   - 填充颜色，默认 'auto'（MATLAB 自动分配）
            %                  可以是：'r', 'g', 'b', [R G B], 'auto' 等
            %   edge_color   - 边界颜色，默认 'k'（黑色）
            %   face_alpha   - 填充透明度，默认 0.6 (0-1)
            %   edge_width   - 边界线宽，默认 1.5
            %   show_ports   - 是否显示端口，默认 false
            %   use_top      - 使用顶部坐标还是底部坐标，默认根据 width_mode
            %
            % 示例:
            %   obj.plot_2d();  % 使用默认参数
            %   obj.plot_2d('face_color', 'r');  % 红色填充
            %   obj.plot_2d('face_color', [0.3 0.75 0.93]);  % RGB 颜色
            %   obj.plot_2d('face_color', 'auto', 'show_ports', true);  % 自动颜色并显示端口
        
            arguments
                obj Wcli_poly
                options.fig_handle = []
                options.face_color = '#f4d967'
                options.edge_color = 'none'
                options.face_alpha (1,1) double {mustBeInRange(options.face_alpha, 0, 1)} = 1
                options.edge_width (1,1) double {mustBePositive} = 1
                options.show_ports (1,1) logical = false
                options.use_top (1,1) logical = false
            end
            
            % 确定使用哪个图窗
            if isempty(options.fig_handle)
                fig_handle = gcf;
            else
                fig_handle = options.fig_handle;
            end
            
            figure(fig_handle);
            hold on;
            
            % 确定使用顶部还是底部坐标
            if isempty(options.use_top)
                use_top = obj.width_mode;
            else
                use_top = options.use_top;
            end
            
            % 获取坐标
            if use_top
                xy = obj.XY_top;
            else
                xy = obj.XY;
            end
            
            % 确保多边形闭合（绘图需要）
            if ~isequal(xy(1,:), xy(end,:))
                xy = [xy; xy(1,:)];
            end
            
            % 处理颜色参数
            if strcmpi(options.face_color, 'auto')
                % 使用 MATLAB 自动颜色（从默认色序中获取下一个颜色）
                patch_handle = patch('XData', xy(:,1), 'YData', xy(:,2), ...
                    'EdgeColor', options.edge_color, ...
                    'FaceAlpha', options.face_alpha, ...
                    'LineWidth', options.edge_width);
            else
                % 使用指定颜色
                patch_handle = patch('XData', xy(:,1), 'YData', xy(:,2), ...
                    'FaceColor', options.face_color, ...
                    'EdgeColor', options.edge_color, ...
                    'FaceAlpha', options.face_alpha, ...
                    'LineWidth', options.edge_width);
            end
            
            % 可选：显示端口
            if options.show_ports && ~isempty(obj.port_list)
                obj.plot_ports(fig_handle);
            end
            
            % 设置坐标轴
            axis equal;
            xlabel('X (μm)');
            ylabel('Y (μm)');
            title(sprintf('2D Polygon: %s', obj.name));
            hold off;
            box on;
        end


    end

    %% 静态方法
    methods (Static)
        %% 坐标变换静态方法
        function XY_new = rotate_translate_xy(XY_old, theta, T_x, T_y)
            % 对N×2坐标矩阵进行旋转和平移
            arguments
                XY_old (:, 2) double
                theta (1, 1) double = 0
                T_x (1, 1) double = 0
                T_y (1, 1) double = 0
            end

            X_old = XY_old(:, 1);
            Y_old = XY_old(:, 2);
            cos_theta = cos(theta);
            sin_theta = sin(theta);

            X_rot = X_old * cos_theta - Y_old * sin_theta;
            Y_rot = X_old * sin_theta + Y_old * cos_theta;

            X_new = X_rot + T_x;
            Y_new = Y_rot + T_y;
            XY_new = [X_new, Y_new];
        end

        function XY_new = mirror_translate_xy(XY_old, axis, T_x, T_y)
            % 对N×2坐标矩阵进行镜像和平移
            arguments
                XY_old (:, 2) double
                axis (1, :) char {mustBeMember(axis, {'x', 'y', 'xy'})} = 'x'
                T_x (1, 1) double = 0
                T_y (1, 1) double = 0
            end

            X_old = XY_old(:, 1);
            Y_old = XY_old(:, 2);

            switch axis
                case 'x'
                    X_mirrored = X_old;
                    Y_mirrored = -Y_old;
                case 'y'
                    X_mirrored = -X_old;
                    Y_mirrored = Y_old;
                case 'xy'
                    X_mirrored = -X_old;
                    Y_mirrored = -Y_old;
            end

            X_new = X_mirrored + T_x;
            Y_new = Y_mirrored + T_y;
            XY_new = [X_new, Y_new];
        end

        %% 多边形内外偏移算法
        function [data_top, data_bottom] = Top_bot_polygon_gen(data_in, offset_dist)
            % 多边形向内偏移（基于角平分线算法）
            % 输入:
            %   data_bot - 底部坐标 (nm单位) N×2矩阵，不含重复闭合点
            %   delta_w - 偏移距离 (μm)
            % 输出:
            %   data_top - 顶部坐标 (nm单位)，顶点顺序与data_bot对应

            N = size(data_in, 1); % 顶点数

            % 预分配输出
            offset_inward = zeros(N, 2);
            offset_outward = zeros(N, 2);

            % 对每个顶点计算偏移
            for i = 1:N
                % 获取相邻三个点的索引（循环）
                i_prev = mod(i - 2, N) + 1;
                i_curr = i;
                i_next = mod(i, N) + 1;

                % 三个点的坐标
                p_prev = data_in(i_prev, :);
                p_curr = data_in(i_curr, :);
                p_next = data_in(i_next, :);

                % 计算两条边的向量
                v1 = -p_curr + p_prev; % 前一条边（指向当前点）
                v2 = p_next - p_curr; % 后一条边（从当前点出发）

                % 归一化
                v1_len = norm(v1);
                v2_len = norm(v2);

                if v1_len < 1e-10 || v2_len < 1e-10
                    % 退化情况：点重合，跳过
                    offset_inward(i, :) = p_curr;
                    offset_outward(i, :) = p_curr;
                    continue;
                end

                v1_norm = v1 / v1_len;
                v2_norm = v2 / v2_len;

                % 计算角平分线方向
                bisector = v1_norm + v2_norm;
                bisector_len = norm(bisector);

                % 处理180度的情况（两向量共线且反向）
                if bisector_len < 1e-10
                    % 使用垂直于边的方向（逆时针旋转90度）
                    bisector = [-v1_norm(2), v1_norm(1)];
                    bisector_len = 1;
                end

                % 归一化角平分线
                WAbisector = bisector / bisector_len;

                % 计算偏移长度
                % 使用向量v1的法向量来判断方向
                % 法向量：逆时针旋转90度
                v1_normal = [-v1_norm(2), v1_norm(1)];

                % 角平分线与法向量的点积，判断角平分线指向
                % 正值表示角平分线指向多边形外侧
                direction_sign = dot(bisector, v1_normal);

                % 计算夹角（使用叉积的绝对值）
                % sin(half_angle) = |cross(v1_norm, v2_norm)| / 2
                cross_product = v1_norm(1) * v2_norm(2) - v1_norm(2) * v2_norm(1);
                dot_product = dot(v1_norm, v2_norm);

                % 计算两向量夹角
                angle = atan2(abs(cross_product), dot_product);
                % angle = acos(dot_product);
                half_angle = angle / 2;

                % 防止除零
                if abs(sin(half_angle)) < 1e-10
                    offset_length = offset_dist * 100; % 很大的值
                else
                    % 偏移长度 = offset_dist / sin(half_angle)
                    offset_length = offset_dist / sin(half_angle);
                end

                % 限制最大偏移长度（避免尖角问题）
                max_offset = offset_dist * 100;
                offset_length = min(offset_length, max_offset);

                % 根据方向标志决定内外偏移
                if direction_sign > 0
                    % 角平分线指向外侧
                    offset_outward(i, :) = p_curr + WAbisector * offset_length;
                    offset_inward(i, :) = p_curr - WAbisector * offset_length;
                else
                    % 角平分线指向内侧
                    offset_inward(i, :) = p_curr + WAbisector * offset_length;
                    offset_outward(i, :) = p_curr - WAbisector * offset_length;
                end

                % 检测是否出现复数（调试用）
                if ~isreal(offset_inward(i, :)) || ~isreal(offset_outward(i, :))
                    warning('在顶点 %d 处检测到复数坐标！', i);
                    fprintf('\n=== 调试信息 ===\n');
                    fprintf('当前顶点索引: %d\n', i);
                    fprintf('前一点索引: %d, 坐标: [%.6f, %.6f]\n', i_prev, p_prev);
                    fprintf('当前点索引: %d, 坐标: [%.6f, %.6f]\n', i_curr, p_curr);
                    fprintf('后一点索引: %d, 坐标: [%.6f, %.6f]\n', i_next, p_next);
                    fprintf('向量 v1: [%.6f, %.6f], 长度: %.6f\n', v1, v1_len);
                    fprintf('向量 v2: [%.6f, %.6f], 长度: %.6f\n', v2, v2_len);
                    fprintf('角平分线: [%.6f, %.6f]\n', WAbisector);
                    fprintf('偏移长度: %.6f\n', offset_length);
                    fprintf('内偏移坐标: [%.6f, %.6f]\n', offset_inward(i, :));
                    fprintf('外偏移坐标: [%.6f, %.6f]\n', offset_outward(i, :));
                    fprintf('================\n\n');

                    % 暂停进入调试模式
                    keyboard;
                end

            end

            data_top = offset_inward;
            data_bottom = offset_outward;
        end

        function area = polygon_area(vertices)
            % 使用Shoelace公式计算多边形面积
            % 输入: N×2坐标矩阵（不含重复闭合点）
            % 输出: 带符号面积（逆时针为正，顺时针为负）

            N = size(vertices, 1);
            x = vertices(:, 1);
            y = vertices(:, 2);

            % Shoelace公式
            area = 0.5 * abs(sum(x(1:N) .* y([2:N, 1]) - x([2:N, 1]) .* y(1:N)));

            % 判断方向（通过叉积符号）
            cross_sum = sum(x(1:N) .* y([2:N, 1]) - x([2:N, 1]) .* y(1:N));

            if cross_sum < 0
                area = -area; % 顺时针为负
            end

        end

        %% GDS生成静态方法
        function generate_gds_from_coords(FileDc, dataoutputs, layers, cell_name)
            % 从坐标列表生成GDS文件
            % 输入:
            %   FileDc - 输出文件路径
            %   dataoutputs - cell数组，每个元素为N×2坐标矩阵(nm单位)
            %   layers - 层号向量
            %   cell_name - Cell名称

            arguments
                FileDc (1, :) char
                dataoutputs (1, :) cell
                layers (1, :) double {mustBeInteger, mustBePositive}
                cell_name (1, :) char = 'Polygon'
            end

            if length(dataoutputs) ~= length(layers)
                error('dataoutputs与layers的长度必须一致');
            end

            % 创建文件夹
            [folder_path, ~, ~] = fileparts(FileDc);

            if ~isempty(folder_path) && ~exist(folder_path, 'dir')
                mkdir(folder_path);
            end

            fid = fopen(FileDc, 'w');

            % 写入GDS头部
            fprintf(fid, 'HEADER 600\r\n');
            fprintf(fid, 'BGNLIB 4/20/2021 12:33:18 4/20/2021 12:33:18 \r\n');
            fprintf(fid, 'LIBNAME Polygon\r\n');
            fprintf(fid, 'UNITS 0.005 1e-009 \r\n');
            fprintf(fid, 'BGNSTR 4/20/2021 12:33:18 4/20/2021 12:33:18  \r\n');

            if mod(length(cell_name), 2) ~= 0
                cell_name = [cell_name 'E'];
            end

            fprintf(fid, 'STRNAME %s\r\n', cell_name);

            % 逐层写入
            for idx = 1:length(dataoutputs)
                coords_nm = dataoutputs{idx};
                layer = layers(idx);
                Wcli_poly.write_boundary(fid, coords_nm, layer);
            end

            fprintf(fid, 'ENDSTR \r\n');
            fprintf(fid, 'ENDLIB \r\n');
            fclose(fid);
        end

        function generate_multi_flatten_gds(poly_objs, FileDc, layers_list, cell_name, lib_name)
            % 将多个 Wcli_poly 对象合并写入到同一个扁平化的 GDS 文件中
            % 所有结构都在同一个cell中，没有层级结构
            %
            % 输入参数:
            %   poly_objs - Wcli_poly 对象的元胞数组
            %   FileDc - GDS 文件路径 (字符串)
            %   layers_list - 层号列表，可以是：
            %                 1) 单个层号（所有结构使用同一层）
            %                 2) 与 poly_objs 长度相同的向量（每个结构对应一个层号）
            %   cell_name - 单一结构名称
            %   lib_name - 可选，库名称，默认为 'FlattenedPolygons'
            %
            % 示例:
            %   poly1 = Wcli_poly.create_T_rail_S(5, 50, 100, 5, 10, 2, 40, 80, 0.22);
            %   poly2 = Wcli_poly.create_T_rail_G(3, 50, 100, 5, 10, 2, 40, 80, 0.22);
            %   Wcli_poly.generate_multi_flatten_gds({poly1, poly2}, 'output.gds', [1, 2], 'MULTI_POLY');

            arguments
                poly_objs (1, :) cell
                FileDc (1, :) char
                layers_list (1, :) double {mustBeInteger, mustBePositive}
                cell_name (1, :) char
                lib_name (1, :) char = 'FlattenedPolygons'
            end

            num_polys = length(poly_objs);

            % 处理层号列表
            if length(layers_list) == 1
                layers_list = repmat(layers_list, 1, num_polys);
            elseif length(layers_list) ~= num_polys
                error('layers_list 的长度必须为 1 或与 poly_objs 的长度相同');
            end

            % 验证所有输入都是 Wcli_poly 对象
            for i = 1:num_polys

                if ~isa(poly_objs{i}, 'Wcli_poly')
                    error('poly_objs{%d} 不是 Wcli_poly 对象', i);
                end

            end

            % 收集所有边界数据
            all_boundary_data = cell(1, num_polys);

            for poly_idx = 1:num_polys
                obj = poly_objs{poly_idx};

                % 获取需要的多边形坐标（nm单位）
                if obj.width_mode
                    poly_xy_nm = round(obj.XY_top * 1e3);
                else
                    poly_xy_nm = round(obj.XY * 1e3);
                end

                % 确保多边形闭合
                if ~isequal(poly_xy_nm(1, :), poly_xy_nm(end, :))
                    poly_xy_nm(end + 1, :) = poly_xy_nm(1, :);
                end

                all_boundary_data{poly_idx} = poly_xy_nm;
            end

            % 创建文件夹
            [folder_path, ~, ~] = fileparts(FileDc);

            if ~isempty(folder_path) && ~exist(folder_path, 'dir')
                mkdir(folder_path);
            end

            % 打开文件并写入
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

                % 确保结构名称长度为偶数
                if mod(length(cell_name), 2) ~= 0
                    cell_name = [cell_name 'E'];
                end

                % 写入结构开始标记
                fprintf(fid, 'BGNSTR 4/20/2021 12:33:18 4/20/2021 12:33:18  \r\n');
                fprintf(fid, 'STRNAME %s\r\n', cell_name);

                % 写入所有收集的边界数据
                for poly_idx = 1:num_polys
                    data = all_boundary_data{poly_idx};
                    layer = layers_list(poly_idx);
                    Wcli_poly.write_boundary(fid, data, layer);
                end

                % 写入结构和库结束标记
                fprintf(fid, 'ENDSTR \r\n');
                fprintf(fid, 'ENDLIB \r\n');

            catch ME
                fclose(fid);
                rethrow(ME);
            end

            fclose(fid);
        end

        function generate_multi_cell_gds(poly_objs, FileDc, layers_list, top_cell_name, lib_name)
            % 将多个 Wcli_poly 对象写入 GDS 文件，每个对象单独成为一个 cell
            % 创建层级结构：顶层 cell 引用所有子 cell
            %
            % 输入参数:
            %   poly_objs - Wcli_poly 对象的元胞数组
            %   FileDc - GDS 文件路径 (字符串)
            %   layers_list - 层号列表，可以是：
            %                 1) 单个层号（所有结构使用同一层）
            %                 2) 与 poly_objs 长度相同的向量（每个结构对应一个层号）
            %   lib_name - 库名称，默认为 'PolyLib'
            %   top_cell_name - 顶层 cell 名称，默认为 'TOP'
            %
            % 示例:
            %   poly1 = Wcli_poly.create_T_rail_S(5, 50, 100, 5, 10, 2, 40, 80, 0.22);
            %   poly1.name = 'T_RAIL_S';
            %   poly2 = Wcli_poly.create_T_rail_G(3, 50, 100, 5, 10, 2, 40, 80, 0.22);
            %   poly2.name = 'T_RAIL_G';
            %   Wcli_poly.generate_multi_cell_gds({poly1, poly2}, 'output.gds', [1, 2]);

            arguments
                poly_objs (1, :) cell
                FileDc (1, :) char
                layers_list (1, :) double {mustBeInteger, mustBePositive}
                top_cell_name (1, :) char = 'TOP'
                lib_name (1, :) char = 'PolyLib'

            end

            num_polys = length(poly_objs);

            % 处理层号列表
            if length(layers_list) == 1
                layers_list = repmat(layers_list, 1, num_polys);
            elseif length(layers_list) ~= num_polys
                error('layers_list 的长度必须为 1 或与 poly_objs 的长度相同');
            end

            % 验证所有输入都是 Wcli_poly 对象
            for i = 1:num_polys

                if ~isa(poly_objs{i}, 'Wcli_poly')
                    error('poly_objs{%d} 不是 Wcli_poly 对象', i);
                end

            end

            % 收集所有 cell 名称和边界数据
            cell_names = cell(1, num_polys);
            all_boundary_data = cell(1, num_polys);

            for poly_idx = 1:num_polys
                obj = poly_objs{poly_idx};

                % 获取 cell 名称
                if isprop(obj, 'name') && ~isempty(obj.name)
                    cell_name = sprintf('%sc%d', obj.name, poly_idx); % 避免重复名称
                else
                    cell_name = sprintf('POLY_%d', poly_idx);
                end

                % 确保名称长度为偶数
                if mod(length(cell_name), 2) ~= 0
                    cell_name = [cell_name, 'E'];
                end

                cell_names{poly_idx} = cell_name;

                % 获取需要多边形坐标（nm单位）
                if obj.width_mode
                    poly_xy_nm = round(obj.XY_top * 1e3);
                else
                    poly_xy_nm = round(obj.XY * 1e3);
                end

                % 确保多边形闭合
                if ~isequal(poly_xy_nm(1, :), poly_xy_nm(end, :))
                    poly_xy_nm(end + 1, :) = poly_xy_nm(1, :);
                end

                all_boundary_data{poly_idx} = poly_xy_nm;
            end

            % 创建文件夹
            [folder_path, ~, ~] = fileparts(FileDc);

            if ~isempty(folder_path) && ~exist(folder_path, 'dir')
                mkdir(folder_path);
            end

            % 打开文件并写入
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

                % 写入所有子 cell（每个多边形对象一个 cell）
                for poly_idx = 1:num_polys
                    cell_name = cell_names{poly_idx};
                    data = all_boundary_data{poly_idx};
                    layer = layers_list(poly_idx);

                    % 写入子 cell 开始标记
                    fprintf(fid, 'BGNSTR 4/20/2021 12:33:18 4/20/2021 12:33:18  \r\n');
                    fprintf(fid, 'STRNAME %s\r\n', cell_name);

                    % 写入边界数据
                    Wcli_poly.write_boundary(fid, data, layer);

                    % 写入子 cell 结束标记
                    fprintf(fid, 'ENDSTR \r\n');
                end

                % 确保顶层 cell 名称长度为偶数
                if mod(length(top_cell_name), 2) ~= 0
                    top_cell_name = [top_cell_name, 'E'];
                end

                % 写入顶层 cell
                fprintf(fid, 'BGNSTR 4/20/2021 12:33:18 4/20/2021 12:33:18  \r\n');
                fprintf(fid, 'STRNAME %s\r\n', top_cell_name);

                % 在顶层 cell 中引用所有子 cell（SREF）
                for poly_idx = 1:num_polys
                    cell_name = cell_names{poly_idx};

                    fprintf(fid, 'SREF \r\n');
                    fprintf(fid, 'SNAME %s\r\n', cell_name);
                    fprintf(fid, 'XY 0:0\r\n'); % 默认位置在原点
                    fprintf(fid, 'ENDEL \r\n');
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

            % 显示成功信息
            fprintf('成功创建多层级 GDS 文件: %s\n', FileDc);
            fprintf('库名称: %s\n', lib_name);
            fprintf('顶层 cell: %s\n', top_cell_name);
            fprintf('子 cell 列表:\n');

            for i = 1:num_polys
                fprintf('  [%d] %s (Layer %d)\n', i, cell_names{i}, layers_list(i));
            end

        end

        function write_boundary(fid, data, layer)
            % 写入单个边界到GDS文件
            fprintf(fid, 'BOUNDARY \r\n');
            fprintf(fid, 'LAYER %d \r\n', layer);
            fprintf(fid, 'DATATYPE 0 \r\n');
            fprintf(fid, 'XY \r\n');

            % 向量化写入
            coord_str = sprintf('%d:%d\t\r\n', data');
            fprintf(fid, '%s', coord_str);

            fprintf(fid, 'ENDEL \r\n');
        end

        function gds2gdsii(input_txt_file, output_gds_file)
            % GDS文本转二进制（完整移植自Wcli_wg）
            fid_in = fopen(input_txt_file, 'r');

            if fid_in == -1
                error('无法打开输入文件: %s', input_txt_file);
            end

            fid_out = fopen(output_gds_file, 'wb', 'ieee-be');

            if fid_out == -1
                error('无法创建输出文件: %s', output_gds_file);
            end

            repeat_flag = 0;

            while ~feof(fid_in)

                if ~repeat_flag
                    tline = strtrim(fgetl(fid_in));
                else
                    repeat_flag = 0;
                end

                if isempty(tline)
                    continue;
                end

                tokens = strsplit(tline);

                switch tokens{1}
                    case 'HEADER'
                        hex_str = ['00'; '06'; '00'; '02'];
                        fwrite(fid_out, hex2dec(hex_str), 'uint8', 'ieee-be');
                        fwrite(fid_out, str2double(tokens{2}), 'uint16', 'ieee-be');

                    case 'BGNLIB'
                        fwrite(fid_out, [0, 28, 1, 2], 'uint8', 'ieee-be');
                        BGN_str = ['07'; 'e8'; '00'; '04'; '00'; '11'; '00'; '0d'; '00'; '35'; '00'; '0b'];
                        fwrite(fid_out, hex2dec(BGN_str), 'uint8', 'ieee-be');
                        fwrite(fid_out, hex2dec(BGN_str), 'uint8', 'ieee-be');

                    case 'LIBNAME'
                        name = strtrim(tline(8:end));
                        name_len = length(name);

                        if mod(name_len, 2) == 1
                            name_len = name_len + 1;
                            name = [name ' '];
                        end

                        fwrite(fid_out, 4 + name_len, 'uint16', 'ieee-be');
                        fwrite(fid_out, [2, 6], 'uint8', 'ieee-be');
                        fwrite(fid_out, name, 'char');

                    case 'UNITS'
                        unit_str = ['00'; '14'; '03'; '05'; '3E'; '41'; '89'; '37'; '4B'; 'C6'; ...
                            'A7'; 'F0'; '39'; '44'; 'B8'; '2F'; 'A0'; '9B'; '5A'; '54'];
                        fwrite(fid_out, hex2dec(unit_str), 'uint8', 'ieee-be');

                    case 'BGNSTR'
                        fwrite(fid_out, [0, 28, 5, 2], 'uint8', 'ieee-be');
                        BGN_str = ['07'; 'e8'; '00'; '04'; '00'; '11'; '00'; '0d'; '00'; '35'; '00'; '0b'];
                        fwrite(fid_out, hex2dec(BGN_str), 'uint8', 'ieee-be');
                        fwrite(fid_out, hex2dec(BGN_str), 'uint8', 'ieee-be');

                    case 'STRNAME'
                        name = strtrim(tline(9:end));
                        name_len = length(name);

                        if mod(name_len, 2) == 1
                            name_len = name_len + 1;
                            name = [name, ' '];
                        end

                        fwrite(fid_out, 4 + name_len, 'uint16', 'ieee-be');
                        fwrite(fid_out, [6, 6], 'uint8', 'ieee-be');
                        fwrite(fid_out, name, 'char');

                    case 'BOUNDARY'
                        fwrite(fid_out, [0, 4, 8, 0], 'uint8', 'ieee-be');

                    case 'LAYER'
                        fwrite(fid_out, [0, 6, 13, 2], 'uint8', 'ieee-be');
                        fwrite(fid_out, str2double(tokens{2}), 'uint16', 'ieee-be');

                    case 'DATATYPE'
                        fwrite(fid_out, [0, 6, 14, 2], 'uint8', 'ieee-be');
                        fwrite(fid_out, str2double(tokens{2}), 'uint16', 'ieee-be');

                    case 'XY'
                        max_coords = 8192;
                        coords_buffer = zeros(max_coords, 2);
                        coord_count = 0;
                        coord_lines = cell(max_coords, 1);
                        line_count = 0;

                        while ~feof(fid_in)
                            tline = strtrim(fgetl(fid_in));

                            if startsWith(tline, 'ENDEL') || startsWith(tline, 'BOUNDARY')
                                repeat_flag = 1;
                                break;
                            end

                            line_count = line_count + 1;
                            coord_lines{line_count} = tline;
                        end

                        if line_count > 0
                            all_lines = strjoin(coord_lines(1:line_count), ' ');
                            all_numbers = regexp(all_lines, '-?\d+', 'match');

                            if ~isempty(all_numbers)
                                num_values = length(all_numbers);

                                if mod(num_values, 2) ~= 0
                                    error('坐标数据不完整');
                                end

                                coord_count = num_values / 2;

                                if coord_count > max_coords
                                    error('坐标点超过限制');
                                end

                                coords = reshape(str2double(all_numbers), 2, [])';
                            else
                                coords = [];
                                coord_count = 0;
                            end

                        else
                            coords = [];
                            coord_count = 0;
                        end

                        if coord_count > 8191
                            error('坐标点超过GDS限制');
                        end

                        if coord_count > 0
                            int32_coordinates = int32(coords);
                            int32_coordinates = [int32_coordinates; int32_coordinates(1, :)];
                            xy_data_32 = reshape(int32_coordinates', [], 1);

                            fwrite(fid_out, 4 + 8 * (coord_count + 1), 'uint16', 'ieee-be');
                            fwrite(fid_out, [16, 3], 'int8', 'ieee-be');
                            fwrite(fid_out, xy_data_32, 'int32', 'ieee-be');
                        else
                            fwrite(fid_out, 4, 'uint16', 'ieee-be');
                            fwrite(fid_out, [16, 3], 'int8', 'ieee-be');
                        end

                    case 'ENDEL'
                        fwrite(fid_out, [0, 4, 17, 0], 'uint8', 'ieee-be');

                    case 'ENDSTR'
                        fwrite(fid_out, [0, 4, 7, 0], 'uint8', 'ieee-be');

                    case 'ENDLIB'
                        fwrite(fid_out, [0, 4, 4, 0], 'uint8', 'ieee-be');

                    otherwise
                        warning('未知关键字: %s', tokens{1});
                end

            end

            fclose(fid_in);
            fclose(fid_out);
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
                input_gds_file (1, :) char
                output_gds_file (1, :) char
                klayout_exe_path (1, :) char = ''
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
        function klayout_gds_subtract(input_gds, options)
            % klayout_gds_subtract: 执行 Layer A - Layer B 的布尔运算
            %
            % 输入参数:
            %   input_gds              - 输入 GDS 路径
            %   options.output_gds     - 输出 GDS 路径 (默认: 原路径加 '_sub' 后缀)
            %   options.layer_a        - [Layer, Datatype] 被减层，例如 [1, 0]
            %   options.layer_b        - [Layer, Datatype] 减去层，例如 [5, 0]
            %   options.keep_layer_b   - 是否保留原始 layer_b。默认为 false
            %   options.klayout_exe_path - klayout_app.exe 的路径

            arguments
                input_gds (1,:) char
                options.output_gds (1,:) char = ''
                options.layer_a (1,2) double = [1,0]  % 格式如 [1, 0]
                options.layer_b (1,2) double = [10,0]  % 格式如 [5, 0]
                options.keep_layer_b (1,1) logical = false
                options.klayout_exe_path (1,:) char = ''
            end

            if ~exist(input_gds, 'file'), error('输入文件不存在: %s', input_gds); end
            if isempty(options.klayout_exe_path)
                options.klayout_exe_path = Wcli_poly.find_klayout_exe('klayout_app');
            end

            % 如果未指定输出路径，则使用原路径加 '_sub' 后缀
            if isempty(options.output_gds)
                [filepath, name, ext] = fileparts(input_gds);
                options.output_gds = fullfile(filepath, [name, '_sub', ext]);
            end

            % 将逻辑值转为 Python 字符串
            py_keep_str = 'True'; if ~options.keep_layer_b, py_keep_str = 'False'; end

            % 动态生成 Python 脚本
            py_script_path = [tempname, '.py'];
            fid = fopen(py_script_path, 'w');

            fprintf(fid, 'import pya\n\n');
            fprintf(fid, 'layout = pya.Layout()\n');
            fprintf(fid, 'layout.read(r"%s")\n', input_gds);
            fprintf(fid, 'top = layout.top_cell()\n\n');

            % 使用传入的层号和数据类型定义层
            fprintf(fid, 'la = layout.layer(%d, %d)\n', options.layer_a(1), options.layer_a(2));
            fprintf(fid, 'lb = layout.layer(%d, %d)\n\n', options.layer_b(1), options.layer_b(2));

            % 转换为 Region
            fprintf(fid, 'reg_a = pya.Region(top.begin_shapes_rec(la))\n');
            fprintf(fid, 'reg_b = pya.Region(top.begin_shapes_rec(lb))\n\n');

            % 布尔运算: A - B
            fprintf(fid, 'reg_result = reg_a - reg_b\n\n');

            % 修改被减层 (Layer A)
            fprintf(fid, 'top.shapes(la).clear()\n');
            fprintf(fid, 'top.shapes(la).insert(reg_result)\n\n');

            % 处理减去层 (Layer B) 的保留逻辑
            fprintf(fid, 'if not %s:\n', py_keep_str);
            fprintf(fid, '    layout.delete_layer(lb)\n\n');

            % 保存结果
            fprintf(fid, 'layout.write(r"%s")\n', options.output_gds);
            fclose(fid);

            % 执行
            cmd = sprintf('"%s" -zz -r "%s"', options.klayout_exe_path, py_script_path);
            fprintf('正在计算: Layer %d/%d - Layer %d/%d (保留减数层: %s)...\n', ...
                options.layer_a(1), options.layer_a(2), options.layer_b(1), options.layer_b(2), string(options.keep_layer_b));

            [status, result] = system(cmd);

            if exist(py_script_path, 'file'), delete(py_script_path); end

            if status == 0
                fprintf('操作成功！保存至: %s\n', options.output_gds);
            else
                error('KLayout 运行失败: %s', result);
            end
        end

        %% 多边形生成工具（从Wcli_wg移植）
        function poly_xy = T_rail_S_gen(N_ele, period, W_S, W_rail, L_rail, W_T, L_T)
            % 生成T型导轨S结构
            arguments
                N_ele (1, 1) double {mustBeInteger, mustBePositive} = 100
                period (1, 1) double {mustBePositive} = 50
                W_S (1, 1) double {mustBeNonnegative} = 100
                W_rail (1, 1) double {mustBePositive} = 5
                L_rail (1, 1) double {mustBePositive} = 10
                W_T (1, 1) double {mustBeNonnegative} = 2
                L_T (1, 1) double {mustBePositive} = 40
            end

            x0 = [-period / 2, -L_rail / 2, -L_rail / 2, -L_T / 2, -L_T / 2, ...
                L_T / 2, L_T / 2, L_rail / 2, L_rail / 2, period / 2]' + period / 2;
            y0 = [0, 0, W_rail, W_rail, W_rail + W_T, W_rail + W_T, ...
                W_rail, W_rail, 0, 0]' + W_S / 2;

            if N_ele > 1
                xr = repmat(x0(2:end), 1, N_ele - 1) + (1:N_ele - 1) * period;
                yr = repmat(y0(2:end), 1, N_ele - 1);
                x_upper = [x0; xr(:)];
                y_upper = [y0; yr(:)];
            else
                x_upper = x0;
                y_upper = y0;
            end

            % 下半部分(关于x轴镜像,反向连接)
            x_lower = flipud(x_upper);
            y_lower = -flipud(y_upper);
            % 组合成闭合多边形(上半→下半→回到起点)
            % poly_x = [x_upper; x_lower; x_upper(1)];
            % poly_y = [y_upper; y_lower; y_upper(1)];
            poly_x = [x_upper; x_lower; ];
            poly_y = [y_upper; y_lower; ];
            poly_xy = [poly_x, poly_y];
            poly_xy = flip(poly_xy); %确定是逆时针
        end

        function poly_xy = Slot_S_gen(N_ele, period, W_S, FF, W_T)
            % 生成T型导轨S结构
            arguments
                N_ele (1, 1) double {mustBeInteger, mustBePositive} = 100
                period (1, 1) double {mustBePositive} = 50
                W_S (1, 1) double {mustBeNonnegative} = 100
                FF (1, 1) double {mustBePositive} = 0.5
                W_T (1, 1) double {mustBeNonnegative} = 2
            end

            L_rail = period * FF;
            x0 = [-period / 2, -L_rail / 2, -L_rail / 2, L_rail / 2, L_rail / 2, period / 2]' + period / 2;
            y0 = [0, 0, W_T, W_T, 0, 0]' + W_S / 2;

            if N_ele > 1
                xr = repmat(x0(2:end), 1, N_ele - 1) + (1:N_ele - 1) * period;
                yr = repmat(y0(2:end), 1, N_ele - 1);
                x_upper = [x0; xr(:)];
                y_upper = [y0; yr(:)];
            else
                x_upper = x0;
                y_upper = y0;
            end

            % 下半部分(关于x轴镜像,反向连接)
            x_lower = flipud(x_upper);
            y_lower = -flipud(y_upper);
            % 组合成闭合多边形(上半→下半→回到起点)
            % poly_x = [x_upper; x_lower; x_upper(1)];
            % poly_y = [y_upper; y_lower; y_upper(1)];
            poly_x = [x_upper; x_lower; ];
            poly_y = [y_upper; y_lower; ];
            poly_xy = [poly_x, poly_y];
            poly_xy = flip(poly_xy); %确定是逆时针
        end

        function poly_xy = Slot_G_gen(N_ele, period, W_S, FF, W_T)
            % 生成T型导轨S结构
            arguments
                N_ele (1, 1) double {mustBeInteger, mustBePositive} = 100
                period (1, 1) double {mustBePositive} = 50
                W_S (1, 1) double {mustBeNonnegative} = 100
                FF (1, 1) double {mustBePositive} = 0.5
                W_T (1, 1) double {mustBeNonnegative} = 2
            end

            L_rail = period * FF;
            x0 = [-period / 2, -L_rail / 2, -L_rail / 2, L_rail / 2, L_rail / 2, period / 2]' + period / 2;
            y0 = [0, 0, W_T, W_T, 0, 0]' + W_S / 2;

            if N_ele > 1
                xr = repmat(x0(2:end), 1, N_ele - 1) + (1:N_ele - 1) * period;
                yr = repmat(y0(2:end), 1, N_ele - 1);
                x_upper = [x0; xr(:)];
                y_upper = [y0; yr(:)];
            else
                x_upper = x0;
                y_upper = y0;
            end

            % 下半部分(关于x轴镜像,反向连接)
            x_lower = [x_upper(end); x_upper(1)];
            y_lower = [-W_S / 2; -W_S / 2];
            % 组合成闭合多边形(上半→下半→回到起点)
            % poly_x = [x_upper; x_lower; x_upper(1)];
            % poly_y = [y_upper; y_lower; y_upper(1)];
            poly_x = [x_upper; x_lower; ];
            poly_y = [y_upper; y_lower; ];
            poly_xy = [poly_x, poly_y];
            poly_xy = flip(poly_xy); %确定是逆时针
        end

        function poly_xy = T_rail_G_gen(N_ele, period, W_G, W_rail, L_rail, W_T, L_T)
            % 生成T型导轨G结构
            % 与T_rail_S_gen相同,仅参数名W_S改为W_G
            arguments
                N_ele (1, 1) double {mustBeInteger, mustBePositive} = 100
                period (1, 1) double {mustBePositive} = 50
                W_G (1, 1) double {mustBeNonnegative} = 100
                W_rail (1, 1) double {mustBePositive} = 5
                L_rail (1, 1) double {mustBePositive} = 10
                W_T (1, 1) double {mustBeNonnegative} = 2
                L_T (1, 1) double {mustBePositive} = 40
            end

            x0 = [-period / 2, -L_rail / 2, -L_rail / 2, -L_T / 2, -L_T / 2, ...
                L_T / 2, L_T / 2, L_rail / 2, L_rail / 2, period / 2]' + period / 2;
            y0 = [0, 0, W_rail, W_rail, W_rail + W_T, W_rail + W_T, ...
                W_rail, W_rail, 0, 0]' + W_G / 2;

            if N_ele > 1
                xr = repmat(x0(2:end), 1, N_ele - 1) + (1:N_ele - 1) * period;
                yr = repmat(y0(2:end), 1, N_ele - 1);
                x_upper = [x0; xr(:)];
                y_upper = [y0; yr(:)];
            else
                x_upper = x0;
                y_upper = y0;
            end

            poly_x = [x_upper; x_upper(end); x_upper(1); ];
            poly_y = [y_upper; -W_G / 2; -W_G / 2; ];
            % poly_x = [x_upper; x_upper(end); x_upper(1); x_upper(1)];
            % poly_y = [y_upper; -W_G/2; -W_G/2; W_G/2];
            poly_xy = [poly_x, poly_y];
            poly_xy = flip(poly_xy); %确定是逆时针
        end

        function poly_xy = semicircle_gen(radius, N_points, center_x, center_y, direction)
            % 生成半圆
            arguments
                radius (1, 1) double {mustBePositive} = 100
                N_points (1, 1) double {mustBeInteger, mustBePositive} = 201
                center_x (1, 1) double = 0
                center_y (1, 1) double = 0
                direction (1, :) char {mustBeMember(direction, {'upper', 'lower', 'left', 'right'})} = 'right'
            end

            switch direction
                case 'upper'
                    theta = linspace(0, pi, N_points);
                case 'lower'
                    theta = linspace(pi, 2 * pi, N_points);
                case 'left'
                    theta = linspace(pi / 2, 3 * pi / 2, N_points);
                case 'right'
                    theta = linspace(-pi / 2, pi / 2, N_points);
            end

            x_arc = center_x + radius * cos(theta);
            y_arc = center_y + radius * sin(theta);

            poly_x = x_arc(:);
            poly_y = y_arc(:);
            poly_xy = [poly_x, poly_y];
        end

        function poly_obj = create_T_rail_G(N_ele, period, W_G, W_rail, L_rail, W_T, L_T, etch_angle, thickness)
            % 直接创建T型导轨G结构的Wcli_poly对象
            % 输入:
            %   N_ele - 单元数量
            %   period - 周期 (μm)
            %   W_G - G结构宽度 (μm)
            %   W_rail - 导轨宽度 (μm)
            %   L_rail - 导轨长度 (μm)
            %   W_T - T型横梁宽度 (μm)
            %   L_T - T型横梁长度 (μm)
            %   etch_angle - 刻蚀角度 (degrees)
            %   thickness - 厚度 (μm)
            %   port_edges - 开口处索引 (可选)

            arguments
                N_ele (1, 1) double {mustBeInteger, mustBePositive} = 100
                period (1, 1) double {mustBePositive} = 50
                W_G (1, 1) double {mustBeNonnegative} = 100
                W_rail (1, 1) double {mustBePositive} = 5
                L_rail (1, 1) double {mustBePositive} = 10
                W_T (1, 1) double {mustBeNonnegative} = 2
                L_T (1, 1) double {mustBePositive} = 40
                etch_angle (1, 1) double = 60
                thickness (1, 1) double {mustBePositive} = 0.25
            end

            para.N = N_ele;
            para.per = period;
            para.W = W_G;
            para.W_r = W_rail;
            para.L_r = L_rail;
            para.W_T = W_T;
            para.L_T = L_T;

            poly_name = Wcli_poly.generate_save_name(para, 'T_rail_single');

            % 生成T型导轨G结构坐标
            poly_xy = Wcli_poly.T_rail_G_gen(N_ele, period, W_G, W_rail, L_rail, W_T, L_T);
            num_of_point = size(poly_xy, 1);
            port_edges = [num_of_point, 1; 2, 3];
            % 创建Wcli_poly对象
            poly_obj = Wcli_poly(poly_xy, etch_angle, thickness, port_edges, poly_name);

            fprintf('已创建T型导轨G结构 (N_ele=%d, period=%.2f μm)\n', N_ele, period);
        end

        function poly_obj = create_T_rail_S(N_ele, period, W_S, W_rail, L_rail, W_T, L_T, etch_angle, thickness)
            % 直接创建T型导轨S结构的Wcli_poly对象
            % 输入:
            %   N_ele - 单元数量
            %   period - 周期 (μm)
            %   W_S - S结构宽度 (μm)
            %   W_rail - 导轨宽度 (μm)
            %   L_rail - 导轨长度 (μm)
            %   W_T - T型横梁宽度 (μm)
            %   L_T - T型横梁长度 (μm)
            %   etch_angle - 刻蚀角度 (degrees)
            %   thickness - 厚度 (μm)
            %   port_edges - 开口处索引 (可选)

            arguments
                N_ele (1, 1) double {mustBeInteger, mustBePositive} = 100
                period (1, 1) double {mustBePositive} = 50
                W_S (1, 1) double {mustBeNonnegative} = 100
                W_rail (1, 1) double {mustBePositive} = 5
                L_rail (1, 1) double {mustBePositive} = 10
                W_T (1, 1) double {mustBeNonnegative} = 2
                L_T (1, 1) double {mustBePositive} = 40
                etch_angle (1, 1) double = 60
                thickness (1, 1) double {mustBePositive} = 0.25
            end

            para.N = N_ele;
            para.per = period;
            para.W = W_S;
            para.W_r = W_rail;
            para.L_r = L_rail;
            para.W_T = W_T;
            para.L_T = L_T;

            poly_name = Wcli_poly.generate_save_name(para, 'T_rail_dou');

            % 生成T型导轨S结构坐标
            poly_xy = Wcli_poly.T_rail_S_gen(N_ele, period, W_S, W_rail, L_rail, W_T, L_T);

            % 创建Wcli_poly对象
            poly_obj = Wcli_poly(poly_xy, etch_angle, thickness, [], poly_name);

            fprintf('已创建T型导轨S结构 (N_ele=%d, period=%.2f μm)\n', N_ele, period);
        end

        function poly_obj = create_slot_S(N_ele, period, W_S, FF, W_T, etch_angle, thickness)
            % 直接创建Slot S结构的Wcli_poly对象
            % 输入:
            %   N_ele - 单元数量
            %   period - 周期 (μm)
            %   W_S - S结构宽度 (μm)
            %   FF - 填充因子 (0-1)
            %   W_T - Slot宽度 (μm)
            %   etch_angle - 刻蚀角度 (degrees)
            %   thickness - 厚度 (μm)

            arguments
                N_ele (1, 1) double {mustBeInteger, mustBePositive} = 100
                period (1, 1) double {mustBePositive} = 50
                W_S (1, 1) double {mustBeNonnegative} = 100
                FF (1, 1) double {mustBePositive, mustBeLessThanOrEqual(FF, 1)} = 0.5
                W_T (1, 1) double {mustBeNonnegative} = 2
                etch_angle (1, 1) double = 60
                thickness (1, 1) double {mustBePositive} = 0.25
            end

            % 构造参数结构用于命名
            para.N = N_ele;
            para.per = period;
            para.W = W_S;
            para.FF = FF;
            para.W_T = W_T;

            poly_name = Wcli_poly.generate_save_name(para, 'Slot_dou');

            % 生成Slot S结构坐标
            poly_xy = Wcli_poly.Slot_S_gen(N_ele, period, W_S, FF, W_T);

            % 创建Wcli_poly对象（无指定端口,自动生成默认端口）
            poly_obj = Wcli_poly(poly_xy, etch_angle, thickness, [], poly_name);

            fprintf('已创建Slot S结构 (N_ele=%d, period=%.2f μm, FF=%.2f)\n', N_ele, period, FF);
        end

        function poly_obj = create_slot_G(N_ele, period, W_G, FF, W_T, etch_angle, thickness)
            % 直接创建Slot G结构的Wcli_poly对象
            % 输入:
            %   N_ele - 单元数量
            %   period - 周期 (μm)
            %   W_G - G结构宽度 (μm)
            %   FF - 填充因子 (0-1)
            %   W_T - Slot宽度 (μm)
            %   etch_angle - 刻蚀角度 (degrees)
            %   thickness - 厚度 (μm)

            arguments
                N_ele (1, 1) double {mustBeInteger, mustBePositive} = 100
                period (1, 1) double {mustBePositive} = 50
                W_G (1, 1) double {mustBeNonnegative} = 100
                FF (1, 1) double {mustBePositive, mustBeLessThanOrEqual(FF, 1)} = 0.5
                W_T (1, 1) double {mustBeNonnegative} = 2
                etch_angle (1, 1) double = 60
                thickness (1, 1) double {mustBePositive} = 0.25
            end

            % 构造参数结构用于命名
            para.N = N_ele;
            para.per = period;
            para.W = W_G;
            para.FF = FF;
            para.W_T = W_T;

            poly_name = Wcli_poly.generate_save_name(para, 'Slot_single');

            % 生成Slot G结构坐标
            poly_xy = Wcli_poly.Slot_G_gen(N_ele, period, W_G, FF, W_T);

            % 指定端口（类似T_rail_G的端口设置）
            num_of_point = size(poly_xy, 1);
            port_edges = [num_of_point, 1; 2, 3];

            % 创建Wcli_poly对象
            poly_obj = Wcli_poly(poly_xy, etch_angle, thickness, port_edges, poly_name);

            fprintf('已创建Slot G结构 (N_ele=%d, period=%.2f μm, FF=%.2f)\n', N_ele, period, FF);
        end

        function poly_obj = create_semicircle(radius, N_points, center_x, center_y, direction, etch_angle, thickness)
            % 直接创建半圆结构的Wcli_poly对象
            % 输入:
            %   radius - 半径 (μm)
            %   N_points - 圆弧采样点数
            %   center_x - 圆心x坐标 (μm)
            %   center_y - 圆心y坐标 (μm)
            %   direction - 方向 'upper'/'lower'/'left'/'right'
            %   etch_angle - 刻蚀角度 (degrees)
            %   thickness - 厚度 (μm)

            arguments
                radius (1, 1) double {mustBePositive} = 100
                N_points (1, 1) double {mustBeInteger, mustBePositive} = 100
                center_x (1, 1) double = 0
                center_y (1, 1) double = 0
                direction (1, :) char {mustBeMember(direction, {'upper', 'lower', 'left', 'right'})} = 'right'
                etch_angle (1, 1) double = 60
                thickness (1, 1) double {mustBePositive} = 0.25
            end

            % 生成半圆坐标
            poly_xy = Wcli_poly.semicircle_gen(radius, N_points, center_x, center_y, direction);

            % 确定开口位置（半圆的两个端点）
            num_of_point = size(poly_xy, 1);
            % 第一个开口：最后一个点和第一个点的边（直径边）
            % 第二个开口：圆弧中点附近的边
            mid_idx = round(N_points / 2);
            port_edges = [num_of_point, 1; mid_idx, mid_idx + 1];
            poly_name = Wcli_poly.generate_save_name(struct('R', radius, 'Dir', direction), 'semicircle');
            % 创建Wcli_poly对象
            poly_obj = Wcli_poly(poly_xy, etch_angle, thickness, port_edges, poly_name);

            fprintf('已创建半圆结构 (radius=%.2f μm, direction=%s, N_points=%d)\n', ...
                radius, direction, N_points);
        end

        function poly_obj = create_quad(options)
            %根据起点和终点的位置、宽度和延伸角度生成四边形 Wcli_poly 对
            arguments
                options.start_pos (1, 2) double = [0, 0]
                options.end_pos (1, 2) double = [10, 0]
                options.start_width (1, 1) double {mustBePositive} = 1
                options.end_width (1, 1) double {mustBePositive} = 1
                options.start_angle (1, 1) double = 90
                options.end_angle (1, 1) double = 90
                options.etch_angle (1, 1) double = 60
                options.thickness (1, 1) double {mustBePositive} = 0.25
                options.name (1, :) char = 'quad_obj'
            end

            % 将角度转换为弧度
            start_angle_rad = deg2rad(options.start_angle);
            end_angle_rad = deg2rad(options.end_angle);

            % 计算起点处延伸方向的单位向量
            start_dir = [cos(start_angle_rad), sin(start_angle_rad)];

            % 计算终点处延伸方向的单位向量
            end_dir = [cos(end_angle_rad), sin(end_angle_rad)];

            % 计算起点处的两个顶点
            start_left = options.start_pos + start_dir * (options.start_width / 2);
            start_right = options.start_pos - start_dir * (options.start_width / 2);

            % 计算终点处的两个顶点
            end_left = options.end_pos + end_dir * (options.end_width / 2);
            end_right = options.end_pos - end_dir * (options.end_width / 2);

            % 按顺序组合四个顶点（逆时针方向）
            quad_points = [
                start_right; % 起点右侧
                end_right; % 终点右侧
                end_left; % 终点左侧
                start_left % 起点左侧
                ];

            % 定义开口处：第一个开口在起点，第二个开口在终点
            % 起点开口: 顶点 4 -> 1 (start_left -> start_right)
            % 终点开口: 顶点 2 -> 3 (end_right -> end_left)
            port_edges = [4, 1; 2, 3];

            % 创建 Wcli_poly 对象
            poly_obj = Wcli_poly(quad_points, options.etch_angle, options.thickness, port_edges, options.name);
        end
        function poly_obj = create_rect_not(options)
            % 创建带半圆凹槽的矩形 Wcli_poly 对象（左侧凹槽，向右方向）
            arguments
                options.width (1, 1) double {mustBePositive} = 100
                options.height (1, 1) double {mustBePositive} = 200
                options.radius (1, 1) double {mustBePositive} = 100
                options.ofst (1, 1) double = 0
                options.N_points (1, 1) double {mustBeInteger, mustBePositive} = 101
                options.etch_angle (1, 1) double = 60
                options.thickness (1, 1) double {mustBePositive} = 0.25
                options.name (1, :) char = 'rect_notch'
            end

            % 生成左侧半圆凹槽（从下到上）
            theta = linspace(-pi / 2, pi / 2, options.N_points);
            circle_x = options.radius * cos(theta);
            circle_y = options.radius * sin(theta);

            % 组合顶点（逆时针）
            vertices = [
                circle_x', circle_y'; % 半圆凹槽
                0, options.height+options.radius; % 左上角
                options.width+options.radius, options.height+options.radius; % 右上角
                options.width+options.radius, -options.height-options.radius; % 右下角
                0, -options.height-options.radius; % 左下角
                ];
            vertices = flip(vertices);
            % 定义端口：底部和顶部边
            num_points = size(vertices, 1);
            port_edges = [num_points, 1; 4,5];

            % 创建 Wcli_poly 对象
            poly_obj = Wcli_poly(vertices, options.etch_angle, options.thickness, port_edges, options.name);

            fprintf('已创建带半圆凹槽的矩形 (width=%.1f, height=%.1f, radius=%.1f)\n', ...
                options.width, options.height, options.radius);
        end
        function poly_obj = create_sq(options)
            % CREATE_SQ 创建正方形 Wcli_poly 对象
            %
            % 名称-值参数:
            %   cen - 中心位置 [x, y] (μm)，默认 [0, 0]
            %   len - 边长 (μm)，默认 10
            %   angle - 旋转角度（度数），默认 0
            %   etch_angle - 刻蚀角度 (degrees)，默认 60
            %   thickness - 厚度 (μm)，默认 0.25
            %   name - 对象名称，默认 'sq_obj'
            %
            % 示例:
            %   sq = Wcli_poly.create_sq(cen=[5,5], len=20);
            %   sq = Wcli_poly.create_sq(cen=[0,0], len=15, angle=45);

            arguments
                options.cen (1, 2) double = [0, 0]
                options.len (1, 1) double {mustBePositive} = 75
                options.angle (1, 1) double = 0
                options.etch_angle (1, 1) double = 60
                options.thickness (1, 1) double {mustBePositive} = 0.25
                options.name (1, :) char = 'sq_obj'
            end

            % 计算正方形的四个顶点（以中心为原点）
            half_len = options.len / 2;

            % 未旋转的四个顶点（逆时针）
            vertices = [
                -half_len, -half_len; % 左下
                half_len, -half_len; % 右下
                half_len, half_len; % 右上
                -half_len, half_len % 左上
                ];

            % 平移到指定中心位置
            vertices = vertices + options.cen;

            % 定义端口：左边和右边的中点
            % 端口1: 顶点 4->1 (左边)
            % 端口2: 顶点 2->3 (右边)
            port_edges = [4, 1; 2, 3];

            % 创建 Wcli_poly 对象
            poly_obj = Wcli_poly(vertices, options.etch_angle, options.thickness, port_edges, options.name);
            poly_obj.transform_shape(options.angle);
        end
        function poly_obj = create_rect(options)
            % CREATE_RECT 创建矩形 Wcli_poly 对象
            %
            % 名称-值参数:
            %   cen - 中心位置 [x, y] (μm)，默认 [0, 0]
            %   width - 宽度 (μm)，默认 20
            %   height - 高度 (μm)，默认 10
            %   angle - 旋转角度（度数），默认 0
            %   etch_angle - 刻蚀角度 (degrees)，默认 60
            %   thickness - 厚度 (μm)，默认 0.25
            %   name - 对象名称，默认 'rect_obj'
            %
            % 示例:
            %   rect = Wcli_poly.create_rect('cen', [5,5], 'width', 30, 'height', 20);
            %   rect = Wcli_poly.create_rect('width', 50, 'height', 25, 'angle', 30);

            arguments
                options.cen (1, 2) double = [0, 0]
                options.len (1, 1) double {mustBePositive} = 20
                options.height (1, 1) double {mustBePositive} = 10
                options.angle (1, 1) double = 0
                options.etch_angle (1, 1) double = 60
                options.thickness (1, 1) double {mustBePositive} = 0.25
                options.name (1, :) char = 'rect_obj'
            end

            % 计算矩形的四个顶点（以中心为原点）
            half_len = options.len / 2;
            half_height = options.height / 2;

            % 未旋转的四个顶点（逆时针）
            vertices = [
                -half_len, -half_height;   % 左下
                half_len, -half_height;   % 右下
                half_len,  half_height;   % 右上
                -half_len,  half_height    % 左上
                ];

            % 平移到指定中心位置
            vertices = vertices + options.cen;

            % 定义端口：左边和右边的中点
            % 端口1: 顶点 4->1 (左边)
            % 端口2: 顶点 2->3 (右边)
            port_edges = [4, 1; 2, 3];

            % 创建 Wcli_poly 对象
            poly_obj = Wcli_poly(vertices, options.etch_angle, options.thickness, ...
                port_edges, options.name);
            poly_obj.transform_shape(options.angle);
        end

        %% 单元模块
        function mmi_half = mmi_1x2_poly_gen(opt)
            % 生成1x2 MMI结构
            % 用法: mmi = Wcli_poly.mmi_1x2_poly_gen('spac', 4.8, 'len_mmi', 59)

            arguments
                opt.etch_angle (1, 1) double {mustBeInRange(opt.etch_angle, 0, 90)} = 70
                opt.h_wg (1, 1) double {mustBePositive} = 0.25
                opt.wid_mmi (1, 1) double {mustBePositive} = 9
                opt.len_mmi (1, 1) double {mustBePositive} = 58
                opt.Tin_len (1, 1) double {mustBePositive} = 50
                opt.Tout_len (1, 1) double {mustBePositive} = 50
                opt.spac (1, 1) double {mustBeNonnegative} = 4.7
                opt.Win (1, 1) double {mustBePositive} = 1.4
                opt.Wout (1, 1) double {mustBePositive} = 1.4
                opt.m_wid (1, 1) double {mustBePositive} = 1
                opt.in_len (1, 1) double {mustBePositive} = 15
            end

            % 参数逻辑验证
            Tin_wid = opt.wid_mmi - opt.spac;
            Tout_wid = opt.wid_mmi - opt.spac;

            assert(opt.spac < opt.wid_mmi, '波导间距必须小于MMI宽度');
            assert(Tin_wid > opt.Win, '输入锥形宽度必须大于输入波导宽度');
            assert(Tout_wid > opt.Wout, '输出锥形宽度必须大于输出波导宽度');

            %% TODO: 生成MMI结构
            % 示例返回
            poly_xy = [0, -opt.Win / 2; ...
                opt.in_len, -opt.Win / 2; ...
                opt.in_len + opt.Tin_len, -Tin_wid / 2; ...
                opt.in_len + opt.Tin_len, -opt.wid_mmi / 2; ...
                opt.in_len + opt.Tin_len + opt.len_mmi, -opt.wid_mmi / 2; ...
                opt.in_len + opt.Tin_len + opt.len_mmi + opt.Tout_len, -opt.spac / 2 - opt.Wout / 2; ...
                opt.in_len + opt.Tin_len + opt.len_mmi + opt.Tout_len, -opt.spac / 2 + opt.Wout / 2; ...
                opt.in_len + opt.Tin_len + opt.len_mmi, -opt.spac / 2 + Tout_wid / 2; ...
                ];
            poly_xy = [poly_xy; flip([poly_xy(:, 1), -poly_xy(:, 2)])];
            mmi_half = Wcli_poly(poly_xy, opt.etch_angle, opt.h_wg);

            fprintf('MMI: wid=%.2f, len=%.2f, spac=%.2f μm\n', ...
                opt.wid_mmi, opt.len_mmi, opt.spac);
        end

        function mmi_half = mmi_1x2_half_poly_gen(opt)
            % 生成半个1x2 MMI结构
            % 用法: mmi = Wcli_poly.mmi_1x2_poly_gen('spac', 4.8, 'len_mmi', 59)

            arguments
                opt.etch_angle (1, 1) double {mustBeInRange(opt.etch_angle, 0, 90)} = 70
                opt.h_wg (1, 1) double {mustBePositive} = 0.25
                opt.wid_mmi (1, 1) double {mustBePositive} = 9
                opt.len_mmi (1, 1) double {mustBePositive} = 58
                opt.Tin_len (1, 1) double {mustBePositive} = 50
                opt.Tout_len (1, 1) double {mustBePositive} = 50
                opt.spac (1, 1) double {mustBeNonnegative} = 4.7
                opt.Win (1, 1) double {mustBePositive} = 1.4
                opt.Wout (1, 1) double {mustBePositive} = 1.4
                opt.m_wid (1, 1) double {mustBePositive} = 1
                opt.in_len (1, 1) double {mustBePositive} = 15
            end

            % 参数逻辑验证
            Tin_wid = opt.wid_mmi - opt.spac;
            Tout_wid = opt.wid_mmi - opt.spac;

            assert(opt.spac < opt.wid_mmi, '波导间距必须小于MMI宽度');
            assert(Tin_wid > opt.Win, '输入锥形宽度必须大于输入波导宽度');
            assert(Tout_wid > opt.Wout, '输出锥形宽度必须大于输出波导宽度');

            %% TODO: 生成MMI结构
            % 示例返回
            poly_xy = [0, -opt.Win / 2; ...
                opt.in_len, -opt.Win / 2; ...
                opt.in_len + opt.Tin_len, -Tin_wid / 2; ...
                opt.in_len + opt.Tin_len, -opt.wid_mmi / 2; ...
                opt.in_len + opt.Tin_len + opt.len_mmi, -opt.wid_mmi / 2; ...
                opt.in_len + opt.Tin_len + opt.len_mmi + opt.Tout_len, -opt.spac / 2 - opt.Wout / 2; ...
                opt.in_len + opt.Tin_len + opt.len_mmi + opt.Tout_len, -opt.spac / 2 + opt.Wout / 2; ...
                opt.in_len + opt.Tin_len + opt.len_mmi, -opt.spac / 2 + Tout_wid / 2; ...
                opt.in_len + opt.Tin_len + opt.len_mmi, opt.wid_mmi / 2; ...
                opt.in_len + opt.Tin_len, opt.wid_mmi / 2; ...
                opt.in_len + opt.Tin_len, Tin_wid / 2; ...
                opt.in_len, opt.Win / 2; ...
                0, opt.Win / 2; ...
                ];
            port_edges = [13, 1; 6, 7];
            poly_name = Wcli_poly.generate_save_name(opt, 'mmi');
            mmi_half = Wcli_poly(poly_xy, opt.etch_angle, opt.h_wg, port_edges, poly_name);

            fprintf('MMI: wid=%.2f, len=%.2f, spac=%.2f μm\n', ...
                opt.wid_mmi, opt.len_mmi, opt.spac);
        end
        function single_AM_circuit = create_single_AM_electrode(options)
            % CREATE_SINGLE_AM_ELECTRODE 创建 Single AM 调制器电极结构(纯电极,无波导)
            %
            % 名称-值参数:
            %   E_para      - 电极参数结构体 (必需)
            %   Disp_S      - S 电极位移 (必需)
            %   circuit_name - 电路名称 (默认: 'single_electrode')

            arguments
                options.E_para struct
                options.circuit_name char = 'single_electrode'
            end

            % 提取参数
            E_para = options.E_para;
            Disp_S = 2 * E_para.Gap + 4 * E_para.W_rail + 4 * E_para.W_T + E_para.W_G + E_para.W_S; % 目标侧向位移 (dy)

            % S连接 (Single)
            T_rail_S_single = Wcli_poly.create_T_rail_S(E_para.N_ele, E_para.period, ...
                E_para.W_S, E_para.W_rail, E_para.L_rail, E_para.W_T, E_para.L_T);
            T_rail_S_single.move_to("cleft");

            % G连接 (Single)
            T_rail_G_down_single = Wcli_wg.create_T_rail_G(E_para.N_ele, E_para.period, ...
                E_para.W_G, E_para.W_rail, E_para.L_rail, E_para.W_T, E_para.L_T);
            T_rail_G_down_single.transform_shape(0, 0, -Disp_S / 2);

            T_rail_G_up_single = T_rail_G_down_single.copy;
            T_rail_G_up_single.mirror_translate_shape('x');

            % 建立 gdscell (只包含电极)
            gdscell = {T_rail_S_single, T_rail_G_up_single, T_rail_G_down_single};
            laycells = [5, 5, 5];

            single_AM_circuit = Wcli_circuit(gdscell, 'laycells', laycells, 'name', options.circuit_name);
        end
        function res_circuit = create_termination_resistor(options)
            % CREATE_TERMINATION_RESISTOR 创建终端电阻电路
            %
            % 名称-值参数:
            %   res_gap     - 上下电阻间距 (默认: 100)
            %   G_res_len   - G电阻长度 (默认: 10)
            %   G_res_height - G电阻高度 (默认: 50)
            %   S_res_len   - S电阻长度 (默认: 10)
            %   S_res_height - S电阻高度 (默认: 50)
            %   term_len    - 终端金属长度 (默认: 5)
            %   term_height - 终端金属高度 (默认: 60)
            %   circuit_name - 电路名称 (默认: 'termination_res')

            arguments
                options.res_gap (1,1) double = 120
                options.G_res_len (1,1) double = 20
                options.G_res_height (1,1) double = 50
                options.S_res_len (1,1) double = 20
                options.S_res_height (1,1) double = 50
                options.term_len (1,1) double = 12
                options.term_height (1,1) double = 94
                options.circuit_name char = 'termination_res'
            end

            % 提取参数
            res_gap = options.res_gap;

            % 创建 G 电阻 (上下对称)
            G_res_up = Wcli_poly.create_rect("len", options.G_res_len, ...
                "height", options.G_res_height, ...
                "cen", [0, res_gap]);

            G_res_down = Wcli_poly.create_rect("len", options.G_res_len, ...
                "height", options.G_res_height, ...
                "cen", [0, -res_gap]);

            % 创建 S 电阻 (中间)
            S_res = Wcli_poly.create_rect("len", options.S_res_len, ...
                "height", options.S_res_height);

            % 创建终端金属 (上下)
            res_term_up = Wcli_poly.create_rect("len", options.term_len, ...
                "height", options.term_height, ...
                "cen", [0, res_gap/2]);

            res_term_down = Wcli_poly.create_rect("len", options.term_len, ...
                "height", options.term_height, ...
                "cen", [0, -res_gap/2]);

            % 建立 circuit
            % Layer 5: 电阻层, Layer 20: 终端金属层
            gdscell = {G_res_up, G_res_down, S_res, res_term_down, res_term_up};
            laycells = [5, 5, 5, 4, 4];

            res_circuit = Wcli_circuit(gdscell, 'laycells', laycells, 'name', options.circuit_name);
        end
        function slot_AM_circuit = create_slot_AM_electrode(options)
            % CREATE_SLOT_AM_ELECTRODE 创建 Slot AM 调制器电极结构(纯电极,无波导)
            %
            % 与 Trail AM 的主要区别:
            %   - 使用 Slot_S 和 Slot_G 结构(填充因子 FF)
            %   - 没有 rail 和 T 连接结构
            %   - 参数更简化(W_T 替代 W_rail, L_rail, L_T)
            %
            % 名称-值参数:
            %   E_para      - 电极参数结构体 (必需，包含 FF 填充因子)
            %   Disp_S      - S 电极位移 (必需)
            %   circuit_name - 电路名称 (默认: 'slot_electrode')

            arguments
                options.E_para struct
                options.circuit_name char = 'slot_electrode'
            end

            % 提取参数
            E_para = options.E_para;
            Disp_S = 2*E_para.Gap+4*E_para.W_T + E_para.W_G + E_para.W_S;

            % 验证必需的 Slot 参数
            if ~isfield(E_para, 'FF')
                error('E_para 必须包含 FF (填充因子) 字段');
            end
            if ~isfield(E_para, 'W_T')
                error('E_para 必须包含 W_T (Slot 宽度) 字段');
            end

            % S 连接 (Slot structure)
            Slot_S_single = Wcli_poly.create_slot_S(E_para.N_ele, E_para.period, ...
                E_para.W_S, E_para.FF, E_para.W_T);
            Slot_S_single.move_to("cleft");

            % G 连接 (Slot structure) - 上下对称
            Slot_G_down_single = Wcli_poly.create_slot_G(E_para.N_ele, E_para.period, ...
                E_para.W_G, E_para.FF, E_para.W_T);
            Slot_G_down_single.transform_shape(0, 0, -Disp_S / 2);

            Slot_G_up_single = Wcli_poly.create_slot_G(E_para.N_ele, E_para.period, ...
                E_para.W_G, E_para.FF, E_para.W_T);
            Slot_G_up_single.mirror_translate_shape('x');
            Slot_G_up_single.transform_shape(0, 0, Disp_S / 2);

            % 建立 gdscell (只包含电极)
            gdscell = {Slot_S_single, Slot_G_up_single, Slot_G_down_single};
            laycells = [5, 5, 5];

            slot_AM_circuit = Wcli_circuit(gdscell, 'laycells', laycells, 'name', options.circuit_name);
        end

        %% 参数扫描工具
        function param_combinations = generate_param_combinations(default_params, sweep_params)
            % 生成参数扫描组合
            sweep_names = fieldnames(sweep_params);
            n_params = length(sweep_names);

            if n_params == 0
                param_combinations = default_params;
                return;
            end

            sweep_values = cell(1, n_params);

            for i = 1:n_params
                sweep_values{i} = sweep_params.(sweep_names{i});
            end

            grids = cell(1, n_params);
            [grids{:}] = ndgrid(sweep_values{:});

            total_combinations = numel(grids{1});
            param_combinations = repmat(default_params, total_combinations, 1);

            for i = 1:n_params
                param_name = sweep_names{i};
                grid_values = grids{i}(:);

                for j = 1:total_combinations
                    param_combinations(j).(param_name) = grid_values(j);
                end

            end

        end

        function save_name = generate_save_name(para, prefix)
            % 生成保存文件名
            fields = fieldnames(para);
            save_name = prefix;

            for i = 1:length(fields)
                field_name = fields{i};
                field_value = para.(field_name);

                if isnumeric(field_value) && mod(field_value, 1) == 0
                    save_name = strcat(save_name, '_', field_name, '_', num2str(field_value, '%d'));
                else
                    save_name = strcat(save_name, '_', field_name, '_', num2str(field_value, '%.10g'));
                end

            end

        end

        %% FDTD仿真
        function run_fdtd_sim(fdtd_data, options)
            % 运行 FDTD 仿真
            %
            % 输入参数:
            %   fdtd_data - 包含仿真数据的结构体，必须包含以下字段:
            %       .sim_file_name - 仿真文件名
            %       .para_name - 当前参数组合名称
            %       .device_name - 设备名前缀
            %   fdtd_data - 可选字段:
            %       .sim_file_path - 仿真文件搜索起始路径
            %       .run_date - 运行日期字符串，默认 datestr(now,'yyyymmdd')
            %       .output_root - 结果保存根目录，默认当前工作路径 pwd
            %   options - 可选参数（名称-值对）:
            %       gui_flag - 是否显示 GUI (0: 无界面, 1: 显示界面), 默认 0
            %       lsf_script - LSF 脚本文件名, 默认 'FDTD_lsf.lsf'
            %       fdtd_exe - FDTD 可执行文件路径
            %                  Windows 默认 'C:\Program Files\Lumerical\v252\bin\fdtd-solutions.exe'
            %                  Ubuntu 默认 '/opt/lumerical/v251/bin/fdtd-solutions'
            %       run_flag - 是否运行仿真 (0: 跳过, 1: 运行), 默认 1
            %
            % 用法示例:
            %   run_fdtd_sim(fdtd_data);  % 使用默认参数
            %   run_fdtd_sim(fdtd_data, 'gui_flag', 1);  % 显示界面
            %   run_fdtd_sim(fdtd_data, 'gui_flag', 0, 'run_flag', 0);  % 不运行

            arguments
                fdtd_data struct {mustBeNonempty}
                options.gui_flag (1, 1) double {mustBeMember(options.gui_flag, [0, 1])} = 1
                options.lsf_script (1, :) char = 'FDTD_lsf.lsf'
                options.fdtd_exe (1, :) char = ''
                options.flag_run (1, 1) double {mustBeMember(options.flag_run, [0, 1])} = 0
            end

            % 检查必需字段
            required_fields = {'sim_file_name', 'para_name', 'device_name'};

            for i = 1:length(required_fields)

                if ~isfield(fdtd_data, required_fields{i})
                    error('fdtd_data 缺少必需字段: %s', required_fields{i});
                end

            end

            if isfield(fdtd_data, 'output_root') && ~isempty(fdtd_data.output_root)
                outputRoot = fdtd_data.output_root;
            else
                outputRoot = pwd;
            end

            deviceName = fdtd_data.device_name;

            if isfield(fdtd_data, 'run_date') && ~isempty(fdtd_data.run_date)
                runDate = fdtd_data.run_date;
            else
                runDate = datestr(now, 'yyyymmdd');
            end

            sw_folder = fullfile(outputRoot, ['dat_', deviceName, '_', runDate]);

            libFolder = fileparts(mfilename('fullpath'));
            libFdtdFolder = fullfile(libFolder, 'fdtd');
            searchFolders = {};
            if isfield(fdtd_data, 'sim_file_path') && ~isempty(fdtd_data.sim_file_path)
                searchFolders{end + 1} = fdtd_data.sim_file_path; %#ok<AGROW>
            end
            searchFolders{end + 1} = pwd; %#ok<AGROW>
            searchFolders{end + 1} = libFdtdFolder; %#ok<AGROW>

            sim_file_full_path = '';
            resolvedSimFolder = '';
            for i_folder = 1:numel(searchFolders)
                candidateSimPath = fullfile(searchFolders{i_folder}, fdtd_data.sim_file_name);
                if exist(candidateSimPath, 'file')
                    sim_file_full_path = candidateSimPath;
                    resolvedSimFolder = searchFolders{i_folder};
                    break;
                end
            end

            save_name_fdtd = fullfile(sw_folder, fdtd_data.para_name);
            fdtd_data.output_root = outputRoot;
            fdtd_data.device_name = deviceName;
            fdtd_data.run_date = runDate;
            fdtd_data.sw_folder = sw_folder;
            fdtd_data.save_name_fdtd = save_name_fdtd;
            fdtd_data.flag_run = options.flag_run;
            fdtd_data.sim_file_path = resolvedSimFolder;

            % 检查仿真文件是否存在
            if isempty(sim_file_full_path)
                error('未找到仿真文件 %s。已搜索路径: %s', fdtd_data.sim_file_name, strjoin(searchFolders, ', '));
            end

            if ~isempty(searchFolders)
                primarySearchFolder = searchFolders{1};
                if ~strcmp(resolvedSimFolder, primarySearchFolder)
                    warning('当前目录未找到仿真文件 %s，已回退到: %s', fdtd_data.sim_file_name, resolvedSimFolder);
                end
            end

            if ~exist(save_name_fdtd, "dir")
                mkdir(save_name_fdtd);
            end

            lsf_full_path = '';
            for i_folder = 1:numel(searchFolders)
                candidateLsfPath = fullfile(searchFolders{i_folder}, options.lsf_script);
                if exist(candidateLsfPath, 'file')
                    lsf_full_path = candidateLsfPath;
                    break;
                end
            end

            if isempty(lsf_full_path)
                warning('LSF 脚本不存在: %s', options.lsf_script);
            end

            if ~isempty(options.fdtd_exe)
                fdtdExePath = options.fdtd_exe;
            elseif ispc
                fdtdExePath = 'C:\Program Files\Lumerical\v252\bin\fdtd-solutions.exe';
            elseif isunix && ~ismac
                fdtdExePath = '/opt/lumerical/v251/bin/fdtd-solutions';
            else
                error('当前操作系统未配置默认 FDTD 可执行文件路径，请手动指定 options.fdtd_exe。');
            end

            % 检查 FDTD 可执行文件是否存在
            if ~exist(fdtdExePath, 'file')
                error('FDTD 可执行文件不存在: %s', fdtdExePath);
            end

            save('matlab2fdtd_data.mat', '-struct', 'fdtd_data', '-v7.3');
            save(fullfile(save_name_fdtd, 'matlab2fdtd_data.mat'), '-struct', 'fdtd_data', '-v7.3');
            Wcli_wg.save_params_to_txt(fdtd_data, save_name_fdtd);

            % 构建命令行
            if options.gui_flag
                % 显示界面运行
                run_system_cmd = sprintf('"%s" -trust-script -run -logall %s %s', ...
                    fdtdExePath, lsf_full_path, sim_file_full_path);
                fprintf('运行模式: 显示 GUI\n');
            else
                % 无界面运行
                run_system_cmd = sprintf('"%s" -trust-script -run -logall -exit %s %s -hide', ...
                    fdtdExePath, lsf_full_path, sim_file_full_path);
                fprintf('运行模式: 后台运行（无界面）\n');
            end

            % 显示信息
            fprintf('开始运行 FDTD 仿真\n');
            fprintf('仿真文件: %s\n', sim_file_full_path);
            fprintf('LSF 脚本: %s\n', lsf_full_path);
            fprintf('FDTD 可执行文件: %s\n', fdtdExePath);

            % 运行仿真
            tic;
            [status, cmdout] = system(run_system_cmd);
            elapsed_time = toc;

            % 检查运行状态
            if status == 0
                fprintf('仿真完成！\n');
                fprintf('耗时: %.2f 秒 (%.2f 分钟)\n', elapsed_time, elapsed_time / 60);
            else
                warning('仿真可能出现错误，退出状态码: %d', status);
                fprintf('命令输出:\n%s\n', cmdout);
            end

        end

        function exePath = find_klayout_exe(toolName)
            arguments
                toolName (1,:) char = 'strm2gds'
            end

            if ispc
                exeName = [toolName, '.exe'];
            else
                exeName = toolName;
            end

            exePath = '';
            [status, foundPath] = system(sprintf('where %s', exeName));
            if status ~= 0
                [status, foundPath] = system(sprintf('which %s', exeName));
            end
            if status == 0
                candidatesFromPath = regexp(strtrim(foundPath), '\r?\n', 'split');
                if ~isempty(candidatesFromPath) && exist(candidatesFromPath{1}, 'file')
                    exePath = candidatesFromPath{1};
                    return;
                end
            end

            candidates = {};
            if ispc
                candidates = {
                    fullfile(getenv('APPDATA'), 'KLayout', exeName), ...
                    fullfile(getenv('ProgramFiles'), 'KLayout', exeName), ...
                    fullfile(getenv('ProgramFiles(x86)'), 'KLayout', exeName)};
            elseif isunix && ~ismac
                candidates = {
                    fullfile('/usr/bin', exeName), ...
                    fullfile('/usr/local/bin', exeName), ...
                    fullfile('/opt/klayout/bin', exeName)};
            end

            for i_candidate = 1:numel(candidates)
                if exist(candidates{i_candidate}, 'file')
                    exePath = candidates{i_candidate};
                    return;
                end
            end

        end

    end

end
