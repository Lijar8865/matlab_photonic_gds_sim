% -*- coding: utf-8 -*-
% 20250422更新：增加选择版图顶宽还是底宽的选项
% 20250708更新：修正波导角度与内外沿的关系
classdef Wcli_wg < Wcli_poly

    properties
        WOX
        WOY
        WIX
        WIY
        WOX_top
        WOY_top
        WIX_top
        WIY_top
        WTX
        WTY

        L_list % List of lengths along the waveguide path,在函数里面调用
        theta_list % List of angles along the waveguide path
        width_list % List of widths along the waveguide path


        trace_length % Length of the waveguide path in μm
        wid_corr = 0.12
        %注释掉，因为从Wcli_poly继承了属性
        %         etch_angle % Etch angle in degrees
        %         thickness % Thickness of the waveguide in μm
        %         delta_w
    end

    %% 内部方法

    methods
        %% 构造函数
        function obj = Wcli_wg(TX, TY, theta_list, width_list, etch_angle, thickness, width_mode)
            % 构造函数
            % 输入参数:
            %   TX, TY - 中心轨迹坐标
            %   theta_list - 角度列表(弧度)
            %   width_list - 宽度列表(μm)
            %   etch_angle - 刻蚀角度(度), 默认60度
            %   thickness - 波导厚度(μm), 默认0.25μm
            %   width_mode - 宽度模式(0: bottom宽度, 1: top宽度), 默认0

            arguments
                TX = linspace(0, 15, 100)        % 默认长度15μm, 100个点
                TY = zeros(1, 100)                % Y坐标全为0
                theta_list = zeros(1, 100)        % 角度全为0
                width_list (1,:) double {mustBePositive} = 2  % 默认宽度2μm
                etch_angle (1,1) double {mustBeInRange(etch_angle, 0, 90)} = 60  % 默认刻蚀角度60度
                thickness (1,1) double {mustBePositive} = 0.25  % 默认厚度0.25μm
                width_mode = []  % 默认为空，触发优先级逻辑（移除验证器）
            end

            % 处理 width_mode 的优先级逻辑
            if isempty(width_mode)
                % 如果没有输入 width_mode，尝试从工作区获取
                try
                    % 尝试从调用者工作区获取 width_mode
                    width_mode = evalin('caller', 'width_mode');
                    % 验证获取的值是否有效
                    if ~ismember(width_mode, [0, 1])
                        warning('从工作区获取的 width_mode 值无效，使用默认值 0\n');
                    end
                catch
                    %                     fprintf('工作区中未找到 width_mode,使用默认值 \n');
                end
            else
                % 如果提供了 width_mode，验证其有效性
                if ~isscalar(width_mode) || ~ismember(width_mode, [0, 1])
                    error('width_mode 必须是标量 0 或 1');
                end
                obj.width_mode = width_mode;
            end

            % 计算顶部宽度的偏移量
            delta_w = 2 * thickness * tan((90 - etch_angle) / 180 * pi);
            % 如果width_list是标量，扩展为与TX同样长度的向量
            if isscalar(width_list)
                width_list = repmat(width_list, size(TX));
            end
            obj.width_list = width_list;
            % 如果是顶部宽度模式，调整width_list为底部宽度
            if obj.width_mode
                width_list = width_list + delta_w;
            end



            % 确保theta_list与TX长度一致
            if isscalar(theta_list)
                theta_list = repmat(theta_list, size(TX));
            end

            % 计算波导轮廓坐标
            WOX = TX - width_list / 2 .* sin(theta_list);
            WOY = TY + width_list / 2 .* cos(theta_list);
            WIX = TX + width_list / 2 .* sin(theta_list);
            WIY = TY - width_list / 2 .* cos(theta_list);

            % 计算顶部波导轮廓坐标
            WOX_top = TX - (width_list - delta_w) / 2 .* sin(theta_list);
            WOY_top = TY + (width_list - delta_w) / 2 .* cos(theta_list);
            WIX_top = TX + (width_list - delta_w) / 2 .* sin(theta_list);
            WIY_top = TY - (width_list - delta_w) / 2 .* cos(theta_list);

            % 赋值给对象属性
            obj.WOX = WOX;
            obj.WOY = WOY;
            obj.WIX = WIX;
            obj.WIY = WIY;
            obj.WOX_top = WOX_top;
            obj.WOY_top = WOY_top;
            obj.WIX_top = WIX_top;
            obj.WIY_top = WIY_top;
            obj.WTX = TX;
            obj.WTY = TY;
            obj.etch_angle = etch_angle;
            obj.thickness = thickness;
            obj.theta_list = theta_list;
%             obj.width_list = width_list;
            obj.delta_w = delta_w;
            obj.trace_length = 0; % 初始化轨迹长度为0
            obj.calc_trace_length(); % 计算轨迹长度
            obj.L_list = obj.calc_length_list(); % 计算长度列表
        end
        %% 对象合并方法
        function ring_wg = close_to_ring(obj)
            % 将波导首尾直接连接形成闭合环路
            % 在末尾添加起点和第二个点，确保闭合且有重叠
            %
            % 输出:
            %   ring_wg - 闭合的环形波导对象
            %
            % 示例:
            %   arc_wg = Wcli_wg.Arc_wg_gen(100, 7*pi/4, 0, 501, 2.8, 2.8, 83, 0.22);
            %   ring_wg = arc_wg.close_to_ring();

            % 创建副本
            ring_wg = obj.copy();

            % 直接在末尾添加起点和第二个点的坐标
            ring_wg.WOX = [ring_wg.WOX, ring_wg.WOX(1), ring_wg.WOX(2)];
            ring_wg.WOY = [ring_wg.WOY, ring_wg.WOY(1), ring_wg.WOY(2)];
            ring_wg.WIX = [ring_wg.WIX, ring_wg.WIX(1), ring_wg.WIX(2)];
            ring_wg.WIY = [ring_wg.WIY, ring_wg.WIY(1), ring_wg.WIY(2)];
            ring_wg.WOX_top = [ring_wg.WOX_top, ring_wg.WOX_top(1), ring_wg.WOX_top(2)];
            ring_wg.WOY_top = [ring_wg.WOY_top, ring_wg.WOY_top(1), ring_wg.WOY_top(2)];
            ring_wg.WIX_top = [ring_wg.WIX_top, ring_wg.WIX_top(1), ring_wg.WIX_top(2)];
            ring_wg.WIY_top = [ring_wg.WIY_top, ring_wg.WIY_top(1), ring_wg.WIY_top(2)];
            ring_wg.WTX = [ring_wg.WTX, ring_wg.WTX(1), ring_wg.WTX(2)];
            ring_wg.WTY = [ring_wg.WTY, ring_wg.WTY(1), ring_wg.WTY(2)];
            ring_wg.theta_list = [ring_wg.theta_list, ring_wg.theta_list(1), ring_wg.theta_list(2)];
            ring_wg.width_list = [ring_wg.width_list, ring_wg.width_list(1), ring_wg.width_list(2)];

            % 更新派生属性
            ring_wg.calc_trace_length();
            ring_wg.L_list = ring_wg.calc_length_list();

            % 计算首尾间隙
            gap = sqrt((obj.WTX(end) - obj.WTX(1))^2 + (obj.WTY(end) - obj.WTY(1))^2);

            % 显示信息
            fprintf('环形波导闭合完成:\n');
            fprintf('  原波导点数: %d\n', length(obj.WTX));
            fprintf('  闭合后点数: %d\n', length(ring_wg.WTX));
            fprintf('  首尾间隙: %.6f μm\n', gap);
            fprintf('  添加了起点和第二个点用于重叠\n');

        end

        function obj = center_to_position(obj, center_x, center_y)
            % 将波导对象居中到指定位置
            % 通过计算边界框中心点，然后平移到目标位置
            %
            % 输入参数:
            %   center_x - 目标中心x坐标 (默认为0)
            %   center_y - 目标中心y坐标 (默认为0)
            % 输出:
            %   obj - 居中后的波导对象
            %
            % 示例:
            %   % 将波导居中到原点
            %   wg = wg.center_to_position();
            %   % 将波导居中到(100, 50)
            %   wg = wg.center_to_position(100, 50);

            arguments
                obj Wcli_wg
                center_x (1,1) double = 0  % 默认居中到x=0
                center_y (1,1) double = 0  % 默认居中到y=0
            end

            % 计算当前边界框的中心点
            x_min = obj.get_boundary_xmin();
            x_max = obj.get_boundary_xmax();
            y_min = obj.get_boundary_ymin();
            y_max = obj.get_boundary_ymax();

            current_center_x = (x_min + x_max) / 2;
            current_center_y = (y_min + y_max) / 2;

            % 计算需要的平移量
            T_x = center_x - current_center_x;
            T_y = center_y - current_center_y;

            % 应用平移（不旋转，只平移）
            obj.transform_shape(0, T_x, T_y);

            % 显示信息
            fprintf('波导对象已居中:\n');
            fprintf('  原中心位置: (%.3f, %.3f) μm\n', current_center_x, current_center_y);
            fprintf('  新中心位置: (%.3f, %.3f) μm\n', center_x, center_y);
            fprintf('  平移量: (%.3f, %.3f) μm\n', T_x, T_y);
        end

        function plot_wg_pos(obj, fig_handle)
            % 如果没有提供图窗句柄，使用当前图窗
            if nargin < 2
                fig_handle = gcf;
            end

            figure(fig_handle);
            plot(obj.WTX, obj.WTY, "DisplayName", "Trace");
            hold on;
            plot(obj.WOX, obj.WOY, '-o', "DisplayName", "O-bot", "MarkerSize", 3);
            plot(obj.WIX, obj.WIY, '-o', "DisplayName", "I-Bot", "MarkerSize", 3);
            plot(obj.WIX_top, obj.WIY_top, '-*', "DisplayName", "I-top", "MarkerSize", 5);
            plot(obj.WOX_top, obj.WOY_top, '-*', "DisplayName", "O-top", "MarkerSize", 5);

            x = obj.WTX;
            y = obj.WTY;
            quiver(x(1:end - 1), y(1:end - 1), diff(x), diff(y), 0.1, ...
                'r', 'LineWidth', 1.5, 'MaxHeadSize', 0.1, 'Displayname', 'direct');

            hold off;
            legend;
            axis equal;
        end

        function obj = merge_and_translate(obj, offset_x, offset_y, remove_first, varargin)
            % 合并多个 Wcli_wg 对象到当前对象
            % offset_x, offset_y: 偏移量向量
            % remove_first: 是否移除每个对象的第一个点
            % varargin: 其他 Wcli_wg 对象

            % 获取当前对象的末尾坐标
            last_TX = obj.WTX(end);
            last_TY = obj.WTY(end);

            % 确保偏移量和 remove_first 的长度足够
            num_structures = length(varargin);

            if length(offset_x) < num_structures
                offset_x = [offset_x, repmat(offset_x(end), 1, num_structures - length(offset_x))];
            end

            if length(offset_y) < num_structures
                offset_y = [offset_y, repmat(offset_y(end), 1, num_structures - length(offset_y))];
            end

            if length(remove_first) < num_structures
                remove_first = [remove_first, repmat(remove_first(end), 1, num_structures - length(remove_first))];
            end

            % 合并每个对象
            for i = 1:num_structures
                W_str_next = varargin{i}.copy();

                % 验证 etch_angle 和 thickness 是否一致
                if abs(obj.etch_angle - W_str_next.etch_angle) > 1e-6 || ...
                        abs(obj.thickness - W_str_next.thickness) > 1e-6
                    error('Etch angle or thickness mismatch. Cannot merge.');
                end

                % 获取当前对象的首个坐标
                first_TX = W_str_next.WTX(1);
                first_TY = W_str_next.WTY(1);

                % 计算平移量
                T_x = last_TX - first_TX + offset_x(i);
                T_y = last_TY - first_TY + offset_y(i);

                % 平移当前对象
                W_str_next.WOX = W_str_next.WOX + T_x;
                W_str_next.WOY = W_str_next.WOY + T_y;
                W_str_next.WIX = W_str_next.WIX + T_x;
                W_str_next.WIY = W_str_next.WIY + T_y;
                W_str_next.WOX_top = W_str_next.WOX_top + T_x;
                W_str_next.WOY_top = W_str_next.WOY_top + T_y;
                W_str_next.WIX_top = W_str_next.WIX_top + T_x;
                W_str_next.WIY_top = W_str_next.WIY_top + T_y;
                W_str_next.WTX = W_str_next.WTX + T_x;
                W_str_next.WTY = W_str_next.WTY + T_y;

                % 如果需要移除第一个点
                if remove_first(i) == 1
                    W_str_next.WOX(1) = [];
                    W_str_next.WOY(1) = [];
                    W_str_next.WIX(1) = [];
                    W_str_next.WIY(1) = [];
                    W_str_next.WOX_top(1) = [];
                    W_str_next.WOY_top(1) = [];
                    W_str_next.WIX_top(1) = [];
                    W_str_next.WIY_top(1) = [];
                    W_str_next.WTX(1) = [];
                    W_str_next.WTY(1) = [];
                    W_str_next.theta_list(1) = [];
                    W_str_next.width_list(1) = [];
                end

                % 合并到当前对象
                obj.WOX = [obj.WOX, W_str_next.WOX];
                obj.WOY = [obj.WOY, W_str_next.WOY];
                obj.WIX = [obj.WIX, W_str_next.WIX];
                obj.WIY = [obj.WIY, W_str_next.WIY];
                obj.WOX_top = [obj.WOX_top, W_str_next.WOX_top];
                obj.WOY_top = [obj.WOY_top, W_str_next.WOY_top];
                obj.WIX_top = [obj.WIX_top, W_str_next.WIX_top];
                obj.WIY_top = [obj.WIY_top, W_str_next.WIY_top];
                obj.WTX = [obj.WTX, W_str_next.WTX];
                obj.WTY = [obj.WTY, W_str_next.WTY];
                obj.theta_list = [obj.theta_list, W_str_next.theta_list];
                obj.theta_list = wrapToPi(obj.theta_list); % %收窄到pi
                obj.width_list = [obj.width_list, W_str_next.width_list];
                obj.L_list = obj.calc_length_list(); % 重新计算长度列表

                % 更新末尾坐标
                last_TX = obj.WTX(end);
                last_TY = obj.WTY(end);
            end

            obj.calc_trace_length(); % 计算轨迹长度

        end

        function obj = merge_wg(obj, next_objs, options)
            % 合并多个 Wcli_wg 对象到当前对象（使用名称-值参数）
            % 
            % 输入参数:
            %   obj - 当前 Wcli_wg 对象
            %   next_objs - 要合并的波导对象，可以是：
            %               1) 单个 Wcli_wg 对象
            %               2) Wcli_wg 对象的元胞数组
            % 
            % 名称-值参数:
            %   ofs_xy       - 偏移量 [offset_x, offset_y]，默认 [0, 0]
            %                  可以是 1×2 向量（应用于所有对象）或 N×2 矩阵（每个对象一行）
            %   remove_first - 是否移除第一个点，默认 1（移除，用于连续连接）
            %                  可以是标量（应用于所有对象）或向量（每个对象一个值）
            %   show_info    - 是否显示合并信息，默认 false
            %
            % 输出:
            %   obj - 合并后的波导对象
            %
            % 示例:
            %   % 基本用法（默认移除第一个点，无偏移）
            %   wg1.merge_wg(wg2);
            %
            %   % 指定偏移量
            %   wg1.merge_wg(wg2, 'ofs_xy', [10, 5]);
            %
            %   % 不移除第一个点（断开连接）
            %   wg1.merge_wg(wg2, 'remove_first', 0);
            %
            %   % 合并多个波导
            %   wg1.merge_wg({wg2, wg3, wg4});
            %
            %   % 为每个波导指定不同的参数
            %   wg1.merge_wg({wg2, wg3}, 'ofs_xy', [0, 0; 10, 5], ...
            %                'remove_first', [1, 0]);
            %
            %   % 显示合并信息
            %   wg1.merge_wg({wg2, wg3}, 'show_info', true);
        
            arguments
                obj Wcli_wg
                next_objs  % 可以是单个对象或元胞数组
                options.ofs_xy = [0, 0]  % 偏移量 [offset_x, offset_y]
                options.remove_first = 1  % 是否移除第一个点
                options.show_info (1,1) logical = false  % 是否显示信息
            end
        
            % 处理输入对象：统一转换为元胞数组
            if ~iscell(next_objs)
                next_objs = {next_objs};
            end
        
            num_structures = length(next_objs);
        
            % 验证所有输入都是 Wcli_wg 对象
            for i = 1:num_structures
                if ~isa(next_objs{i}, 'Wcli_wg')
                    error('第 %d 个对象不是 Wcli_wg 类型', i);
                end
            end
        
            % 扩展 ofs_xy 参数
            if size(options.ofs_xy, 1) == 1
                % 单行：复制为 N×2 矩阵
                ofs_xy = repmat(options.ofs_xy, num_structures, 1);
            elseif size(options.ofs_xy, 1) == num_structures
                % 已经是正确尺寸
                ofs_xy = options.ofs_xy;
            else
                error('ofs_xy 的行数必须为 1 或与对象数量 (%d) 相同', num_structures);
            end
        
            % 确保 ofs_xy 是 N×2 矩阵
            if size(ofs_xy, 2) ~= 2
                error('ofs_xy 必须是 N×2 矩阵，每行为 [offset_x, offset_y]');
            end
        
            % 扩展 remove_first 参数
            remove_first = expand_param(options.remove_first, num_structures);
        
            % 获取当前对象的末尾坐标
            last_TX = obj.WTX(end);
            last_TY = obj.WTY(end);
        
            % 合并每个对象
            for i = 1:num_structures
                W_str_next = next_objs{i}.copy();
        
                % 验证 etch_angle 和 thickness 是否一致
                if abs(obj.etch_angle - W_str_next.etch_angle) > 1e-6
                    error('第 %d 个波导的刻蚀角度不匹配 (%.2f° vs %.2f°)', ...
                        i, obj.etch_angle, W_str_next.etch_angle);
                end
                if abs(obj.thickness - W_str_next.thickness) > 1e-6
                    error('第 %d 个波导的厚度不匹配 (%.3f vs %.3f μm)', ...
                        i, obj.thickness, W_str_next.thickness);
                end
        
                % 获取当前对象的首个坐标
                first_TX = W_str_next.WTX(1);
                first_TY = W_str_next.WTY(1);
        
                % 计算平移量（对齐末尾到起始 + 用户指定的偏移）
                T_x = last_TX - first_TX + ofs_xy(i, 1);
                T_y = last_TY - first_TY + ofs_xy(i, 2);
        
                % 平移当前对象的所有坐标
                W_str_next.WOX = W_str_next.WOX + T_x;
                W_str_next.WOY = W_str_next.WOY + T_y;
                W_str_next.WIX = W_str_next.WIX + T_x;
                W_str_next.WIY = W_str_next.WIY + T_y;
                W_str_next.WOX_top = W_str_next.WOX_top + T_x;
                W_str_next.WOY_top = W_str_next.WOY_top + T_y;
                W_str_next.WIX_top = W_str_next.WIX_top + T_x;
                W_str_next.WIY_top = W_str_next.WIY_top + T_y;
                W_str_next.WTX = W_str_next.WTX + T_x;
                W_str_next.WTY = W_str_next.WTY + T_y;
        
                % 如果需要移除第一个点（连续连接）
                if remove_first(i) == 1
                    W_str_next.WOX(1) = [];
                    W_str_next.WOY(1) = [];
                    W_str_next.WIX(1) = [];
                    W_str_next.WIY(1) = [];
                    W_str_next.WOX_top(1) = [];
                    W_str_next.WOY_top(1) = [];
                    W_str_next.WIX_top(1) = [];
                    W_str_next.WIY_top(1) = [];
                    W_str_next.WTX(1) = [];
                    W_str_next.WTY(1) = [];
                    W_str_next.theta_list(1) = [];
                    W_str_next.width_list(1) = [];
                end
        
                % 合并到当前对象
                obj.WOX = [obj.WOX, W_str_next.WOX];
                obj.WOY = [obj.WOY, W_str_next.WOY];
                obj.WIX = [obj.WIX, W_str_next.WIX];
                obj.WIY = [obj.WIY, W_str_next.WIY];
                obj.WOX_top = [obj.WOX_top, W_str_next.WOX_top];
                obj.WOY_top = [obj.WOY_top, W_str_next.WOY_top];
                obj.WIX_top = [obj.WIX_top, W_str_next.WIX_top];
                obj.WIY_top = [obj.WIY_top, W_str_next.WIY_top];
                obj.WTX = [obj.WTX, W_str_next.WTX];
                obj.WTY = [obj.WTY, W_str_next.WTY];
                obj.theta_list = [obj.theta_list, W_str_next.theta_list];
                obj.theta_list = wrapToPi(obj.theta_list); % 角度范围收窄到[-π, π]
                obj.width_list = [obj.width_list, W_str_next.width_list];
        
                % 可选：显示合并信息
                if options.show_info
                    fprintf('已合并第 %d 个波导:\n', i);
                    fprintf('  偏移量: (%.3f, %.3f) μm\n', ofs_xy(i, 1), ofs_xy(i, 2));
                    fprintf('  移除首点: %s\n', iif(remove_first(i), '是', '否'));
                    fprintf('  新增点数: %d\n', length(W_str_next.WTX));
                    fprintf('  累计总点数: %d\n', length(obj.WTX));
                end
        
                % 更新末尾坐标（用于下一次合并）
                last_TX = obj.WTX(end);
                last_TY = obj.WTY(end);
            end
        
            % 重新计算派生属性
            obj.L_list = obj.calc_length_list();
            obj.calc_trace_length();
        
            % 显示总体信息
            if options.show_info
                fprintf('\n波导合并完成:\n');
                fprintf('  合并对象数: %d\n', num_structures);
                fprintf('  最终总点数: %d\n', length(obj.WTX));
                fprintf('  总长度: %.3f μm\n', obj.trace_length);
            end
        
            % 内部函数：扩展参数以匹配数量
            function expanded = expand_param(param, target_len)
                if isscalar(param)
                    % 标量：扩展为向量
                    expanded = repmat(param, 1, target_len);
                elseif length(param) == target_len
                    % 已经是正确长度
                    expanded = param;
                elseif length(param) < target_len
                    % 长度不足：用最后一个值填充
                    expanded = [param, repmat(param(end), 1, target_len - length(param))];
                else
                    % 长度过长：截断并警告
                    warning('参数长度 (%d) 超过对象数量 (%d)，多余部分将被忽略', ...
                        length(param), target_len);
                    expanded = param(1:target_len);
                end
            end
        
            % 内部函数：条件表达式
            function result = iif(condition, true_val, false_val)
                if condition
                    result = true_val;
                else
                    result = false_val;
                end
            end
        end

        function obj = merge(obj, varargin)
            % 简化版合并函数：将多个波导对象依次连接
            % 自动去除每个新对象的第一个点（与前一个对象的最后一个点重合）
            %
            % 输入:
            %   varargin - 要合并的其他 Wcli_wg 对象
            %
            % 输出:
            %   obj - 合并后的波导对象
            %
            % 示例:
            %   wg1 = Wcli_wg.Straight_wg_gen(10, 0, 2, 80, 0.22);
            %   wg2 = Wcli_wg.Arc_wg_gen(100, pi/4, 0, 501, 2, 2, 80, 0.22);
            %   wg3 = Wcli_wg.Straight_wg_gen(10, pi/4, 2, 80, 0.22);
            %   wg1.merge(wg2, wg3);  % 依次合并wg2和wg3

            % 遍历所有要合并的对象
            for i = 1:length(varargin)
                next_wg = varargin{i}.copy();

                % 验证刻蚀角度和厚度是否一致
                if abs(obj.etch_angle - next_wg.etch_angle) > 1e-6 || ...
                        abs(obj.thickness - next_wg.thickness) > 1e-6
                    error('第%d个波导的刻蚀角度或厚度不匹配，无法合并', i);
                end

                % 计算平移量（使新对象的起点与当前对象的终点对齐）
                T_x = obj.WTX(end) - next_wg.WTX(1);
                T_y = obj.WTY(end) - next_wg.WTY(1);

                % 平移新对象的所有坐标
                next_wg.WOX = next_wg.WOX + T_x;
                next_wg.WOY = next_wg.WOY + T_y;
                next_wg.WIX = next_wg.WIX + T_x;
                next_wg.WIY = next_wg.WIY + T_y;
                next_wg.WOX_top = next_wg.WOX_top + T_x;
                next_wg.WOY_top = next_wg.WOY_top + T_y;
                next_wg.WIX_top = next_wg.WIX_top + T_x;
                next_wg.WIY_top = next_wg.WIY_top + T_y;
                next_wg.WTX = next_wg.WTX + T_x;
                next_wg.WTY = next_wg.WTY + T_y;

                % 去除新对象的第一个点（与当前对象的最后一个点重合）
                next_wg.WOX(1) = [];
                next_wg.WOY(1) = [];
                next_wg.WIX(1) = [];
                next_wg.WIY(1) = [];
                next_wg.WOX_top(1) = [];
                next_wg.WOY_top(1) = [];
                next_wg.WIX_top(1) = [];
                next_wg.WIY_top(1) = [];
                next_wg.WTX(1) = [];
                next_wg.WTY(1) = [];
                next_wg.theta_list(1) = [];
                next_wg.width_list(1) = [];

                % 合并到当前对象
                obj.WOX = [obj.WOX, next_wg.WOX];
                obj.WOY = [obj.WOY, next_wg.WOY];
                obj.WIX = [obj.WIX, next_wg.WIX];
                obj.WIY = [obj.WIY, next_wg.WIY];
                obj.WOX_top = [obj.WOX_top, next_wg.WOX_top];
                obj.WOY_top = [obj.WOY_top, next_wg.WOY_top];
                obj.WIX_top = [obj.WIX_top, next_wg.WIX_top];
                obj.WIY_top = [obj.WIY_top, next_wg.WIY_top];
                obj.WTX = [obj.WTX, next_wg.WTX];
                obj.WTY = [obj.WTY, next_wg.WTY];
                obj.theta_list = [obj.theta_list, next_wg.theta_list];
                obj.theta_list = wrapToPi(obj.theta_list);
                obj.width_list = [obj.width_list, next_wg.width_list];
            end

            % 重新计算派生属性
            obj.L_list = obj.calc_length_list();
            obj.calc_trace_length();

            fprintf('成功合并 %d 个波导对象\n', length(varargin));
        end

        % 翻转波导对象
        function obj = flip_shape(obj)
            % 翻转波导对象的所有坐标和属性
            obj_temp = obj.copy(); % 复制当前对象
            obj.WOX = flip(obj_temp.WIX);
            obj.WOY = flip(obj_temp.WIY);
            obj.WIX = flip(obj_temp.WOX);
            obj.WIY = flip(obj_temp.WOY);
            obj.WOX_top = flip(obj_temp.WIX_top);
            obj.WOY_top = flip(obj_temp.WIY_top);
            obj.WIX_top = flip(obj_temp.WOX_top);
            obj.WIY_top = flip(obj_temp.WOY_top);
            obj.WTX = flip(obj_temp.WTX);
            obj.WTY = flip(obj_temp.WTY);
            obj.theta_list = flip(obj_temp.theta_list) + pi; %交换的时候需要旋转180度
            obj.width_list = flip(obj_temp.width_list);
            obj.calc_length_list;%更新List
        end

        % 在 Wcli_wg 类的 methods 部分添加以下方法
        function obj=mirror_translate_shape(obj, axis, T_x, T_y)
            % 对波导对象进行镜像翻转和平移变换
            %
            % 输入:
            %   axis: 指定镜像轴，可以是 'x'（沿X轴翻转）, 'y'（沿Y轴翻转）, 'xy'（沿XY轴翻转）
            %   T_x: 沿X轴的平移量，默认值为0
            %   T_y: 沿Y轴的平移量，默认值为0

            % 设置默认值
            if nargin < 3
                T_x = 0;
            end

            if nargin < 4
                T_y = 0;
            end

            % 对所有坐标进行镜像翻转和平移
            [WIX_new, WIY_new] = Wcli_wg.mirror_translate(obj.WIX, obj.WIY, axis, T_x, T_y);
            [WOX_new, WOY_new] = Wcli_wg.mirror_translate(obj.WOX, obj.WOY, axis, T_x, T_y);
            [WIX_top_new, WIY_top_new] = Wcli_wg.mirror_translate(obj.WIX_top, obj.WIY_top, axis, T_x, T_y);
            [WOX_top_new, WOY_top_new] = Wcli_wg.mirror_translate(obj.WOX_top, obj.WOY_top, axis, T_x, T_y);
            [WTX_new, WTY_new] = Wcli_wg.mirror_translate(obj.WTX, obj.WTY, axis, T_x, T_y);

            % 根据不同的镜像轴更新坐标
            switch axis
                case 'x'
                    obj.WOX = WIX_new;
                    obj.WOY = WIY_new;
                    obj.WIX = WOX_new;
                    obj.WIY = WOY_new;
                    obj.WOX_top = WIX_top_new;
                    obj.WOY_top = WIY_top_new;
                    obj.WIX_top = WOX_top_new;
                    obj.WIY_top = WOY_top_new;
                    obj.WTX = WTX_new;
                    obj.WTY = WTY_new;
                    obj.theta_list = -obj.theta_list; % 角度取反
                    obj.flip_shape(); % 要交换顺序
                case 'y'
                    obj.WOX = WIX_new;
                    obj.WOY = WIY_new;
                    obj.WIX = WOX_new;
                    obj.WIY = WOY_new;
                    obj.WOX_top = WIX_top_new;
                    obj.WOY_top = WIY_top_new;
                    obj.WIX_top = WOX_top_new;
                    obj.WIY_top = WOY_top_new;
                    obj.WTX = WTX_new;
                    obj.WTY = WTY_new;
                    obj.theta_list = pi - obj.theta_list; % 角度取反
                    obj.flip_shape(); % 默认要交换顺序
                case 'xy'
                    obj.WOX = WOX_new;
                    obj.WOY = WOY_new;
                    obj.WIX = WIX_new;
                    obj.WIY = WIY_new;
                    obj.WOX_top = WOX_top_new;
                    obj.WOY_top = WOY_top_new;
                    obj.WIX_top = WIX_top_new;
                    obj.WIY_top = WIY_top_new;
                    obj.WTX = WTX_new;
                    obj.WTY = WTY_new;
                    obj.theta_list = obj.theta_list + pi; % 角度旋转180度
                    obj.flip_shape(); % 要交换顺序
                otherwise
                    error('Invalid axis. Choose "x", "y", or "xy".');
            end
            obj.calc_length_list;%更新list

        end
        function obj = mir_wg(obj, options)
            % 对波导对象进行镜像翻转和平移变换（使用名称-值参数）
            %
            % 名称-值参数:
            %   axis - 指定镜像轴，可以是 'x'（沿X轴翻转）, 'y'（沿Y轴翻转）, 'xy'（沿XY轴翻转）
            %        默认值为 'x'
            %   Txy - 平移量 [T_x, T_y]，默认值为 [0, 0]
            %   show_info - 是否显示镜像信息，默认 false
            %
            % 示例:
            %   % 基本用法（沿x轴镜像，无平移）
            %   wg.mir_wg();
            %
            %   % 沿y轴镜像
            %   wg.mir_wg('axis', 'y');
            %
            %   % 沿xy轴镜像并平移
            %   wg.mir_wg('axis', 'xy', 'Txy', [10, 20]);
            %
            %   % 只平移不镜像（特殊用法：使用空字符串表示不镜像）
            %   wg.mir_wg('Txy', [5, 10]);
            %
            %   % 显示镜像信息
            %   wg.mir_wg('axis', 'y', 'Txy', [10, 5], 'show_info', true);
        
            arguments
                obj Wcli_wg
                options.axis (1,:) char {mustBeMember(options.axis, {'x', 'y', 'xy'})} = 'x'
                options.Txy (1,2) double = [0, 0]  % 平移量 [T_x, T_y]
                options.show_info (1,1) logical = false  % 是否显示信息
            end
        
            % 提取平移分量
            T_x = options.Txy(1);
            T_y = options.Txy(2);
        
            % 对所有坐标进行镜像翻转和平移
            [WIX_new, WIY_new] = Wcli_wg.mirror_translate(obj.WIX, obj.WIY, options.axis, T_x, T_y);
            [WOX_new, WOY_new] = Wcli_wg.mirror_translate(obj.WOX, obj.WOY, options.axis, T_x, T_y);
            [WIX_top_new, WIY_top_new] = Wcli_wg.mirror_translate(obj.WIX_top, obj.WIY_top, options.axis, T_x, T_y);
            [WOX_top_new, WOY_top_new] = Wcli_wg.mirror_translate(obj.WOX_top, obj.WOY_top, options.axis, T_x, T_y);
            [WTX_new, WTY_new] = Wcli_wg.mirror_translate(obj.WTX, obj.WTY, options.axis, T_x, T_y);
        
            % 根据不同的镜像轴更新坐标和角度
            switch options.axis
                case 'x'
                    % 沿X轴镜像（Y坐标取反）
                    obj.WOX = WIX_new;
                    obj.WOY = WIY_new;
                    obj.WIX = WOX_new;
                    obj.WIY = WOY_new;
                    obj.WOX_top = WIX_top_new;
                    obj.WOY_top = WIY_top_new;
                    obj.WIX_top = WOX_top_new;
                    obj.WIY_top = WOY_top_new;
                    obj.WTX = WTX_new;
                    obj.WTY = WTY_new;
                    obj.theta_list = -obj.theta_list; % 角度取反
                    obj.flip_shape(); % 要交换顺序
                    
                case 'y'
                    % 沿Y轴镜像（X坐标取反）
                    obj.WOX = WIX_new;
                    obj.WOY = WIY_new;
                    obj.WIX = WOX_new;
                    obj.WIY = WOY_new;
                    obj.WOX_top = WIX_top_new;
                    obj.WOY_top = WIY_top_new;
                    obj.WIX_top = WOX_top_new;
                    obj.WIY_top = WOY_top_new;
                    obj.WTX = WTX_new;
                    obj.WTY = WTY_new;
                    obj.theta_list = pi - obj.theta_list; % 角度取反
                    obj.flip_shape(); % 默认要交换顺序
                    
                case 'xy'
                    % 沿XY轴镜像（X和Y坐标都取反）
                    obj.WOX = WOX_new;
                    obj.WOY = WOY_new;
                    obj.WIX = WIX_new;
                    obj.WIY = WIY_new;
                    obj.WOX_top = WOX_top_new;
                    obj.WOY_top = WOY_top_new;
                    obj.WIX_top = WIX_top_new;
                    obj.WIY_top = WIY_top_new;
                    obj.WTX = WTX_new;
                    obj.WTY = WTY_new;
                    obj.theta_list = obj.theta_list + pi; % 角度旋转180度
                    obj.flip_shape(); % 要交换顺序
            end
            
            % 更新长度列表
            obj.calc_length_list();
        
            % 可选：显示镜像信息
            if options.show_info
                fprintf('波导镜像变换完成:\n');
                fprintf('  镜像轴: %s\n', options.axis);
                fprintf('  平移量: (%.3f, %.3f) μm\n', T_x, T_y);
                fprintf('  总点数: %d\n', length(obj.WTX));
                fprintf('  总长度: %.3f μm\n', obj.trace_length);
            end
        end
        %% 画图观察
        % 在 Wcli_wg 类的 methods 部分添加以下方法
        function plot_fdtd_structure(obj, fig_handle)
            % 绘制 FDTD 结构
            % 输入:
            %   fig_handle: 可选的图窗句柄

            % 如果没有提供图窗句柄，使用当前图窗
            if nargin < 2
                fig_handle = gcf;
            end

            % 准备数据
            fdtd_data = obj.posdata2fdtd; % 获取 FDTD 仿真所需的顶点数据
            len_data = length(fdtd_data);

            % 设置图窗
            figure(fig_handle);
            set(gcf, 'Name', 'fdtd_structure');

            % 绘制外部波导
            plot(fdtd_data(1:len_data / 2, 1), fdtd_data(1:len_data / 2, 2));
            hold on;
            scale_factor = 0.8; % 缩放因子
            % 绘制外部波导的方向箭头
            x = fdtd_data(1:len_data / 2, 1);
            y = fdtd_data(1:len_data / 2, 2);
            quiver(x(1:end - 1), y(1:end - 1), diff(x) * scale_factor, diff(y) * scale_factor, 0, ...
                'r', 'LineWidth', 1.5);

            % 绘制内部波导
            plot(fdtd_data(len_data / 2 + 1:end, 1), fdtd_data(len_data / 2 + 1:end, 2));

            % 绘制内部波导的方向箭头
            x = fdtd_data(len_data / 2 + 1:end, 1);
            y = fdtd_data(len_data / 2 + 1:end, 2);
            quiver(x(1:end - 1), y(1:end - 1), diff(x) * scale_factor, diff(y) * scale_factor, 0, ...
                'g', 'LineWidth', 1.5);

            % 完成绘图
            hold off;
            axis equal;
            title('FDTD Structure');
            xlabel('X (μm)');
            ylabel('Y (μm)');
        end

        function plot_R_at(obj, idx, fig_handle)
            % 绘制波导的曲率半径示意图
            % 输入:
            %   idx: 要显示曲率半径的点的索引，默认为1
            %   fig_handle: 可选的图窗句柄

            % 设置默认值
            if nargin < 2
                idx = 1;
            end

            if nargin < 3
                fig_handle = gcf;
            end

            hold on;

            plot_R_wg(obj, fig_handle);
            % 绘制曲率半径
            x = obj.WTX;
            y = obj.WTY;
            sin_theta = sin(obj.theta_list);
            cos_theta = cos(obj.theta_list);
            % 计算曲率半径
            [R, ~] = obj.computeCurvatureRadius();

            % 绘制曲率半径向量
            quiver(x(idx), y(idx), -R(idx) * sin_theta(idx), R(idx) * cos_theta(idx), 'r', 'LineWidth', 2);

            % 设置标题显示曲率半径值
            title(['Radius of curvature at point ' num2str(idx) ' = ' num2str(R(idx), '%.2f') ' μm']);
            hold off;
        end

        function plot_R_wg(obj, fig_handle)
            % 绘制波导的曲率半径示意图
            % 输入:
            %   idx: 要显示曲率半径的点的索引，默认为1
            %   fig_handle: 可选的图窗句柄

            % 设置默认值

            if nargin < 2
                fig_handle = gcf;
            end

            % 计算曲率半径
            [R, ~] = obj.computeCurvatureRadius();
            % 设置图窗
            figure(fig_handle);
            set(gcf, 'Name', 'plot_R');

            % 绘制曲率半径
            x = obj.WTX;
            y = obj.WTY;
            hold on;

            % patch([obj.WOX, fliplr(obj.WIX)], ...
            %     [obj.WOY, fliplr(obj.WIY)], ...
            %     [R, fliplr(R)], ...
            %     [R, fliplr(R)], ...
            %     'EdgeColor', 'none');

            surf([obj.WOX; obj.WIX], ...
                [obj.WOY; obj.WIY], ...
                [R; R], ...
                'EdgeColor', 'none', 'FaceColor', 'interp');

            plot3(x, y, R, 'k');

            % 设置标题显示曲率半径值
            title('Radius of curvature ');
            hold off;
            colorbar;
            view(2); % 设置为2D视图
            xlabel('X (μm)');
            ylabel('Y (μm)');
        end

        function plot_kappa_wg(obj, options)
            % 绘制波导的曲率示意图
            % 输入:
            %   fig_handle: 可选的图窗句柄
            %   scale_factor: 宽度放大倍数，默认为1（不放大）

            arguments
                obj Wcli_wg
                options.fig_handle = gcf  % 默认使用当前图窗
                options.scale_factor (1,1) double {mustBePositive} = 1  % 默认不放大
            end

            obj_copy = obj.copy();
            obj_copy.set_width_list(obj.width_list * options.scale_factor);

            % 计算曲率
            [~, kappa] = obj.computeCurvatureRadius();
            % 设置图窗
            figure(options.fig_handle);
            set(gcf, 'Name', 'plot_R');
            %             hold off;
            % 绘制曲率半径
            x = obj.WTX;
            y = obj.WTY;

            surf([obj_copy.WOX; obj_copy.WIX], ...
                [obj_copy.WOY; obj_copy.WIY], ...
                [kappa; kappa], ...
                'EdgeColor', 'none', 'FaceColor', 'interp');
            hold on;
            plot3(x, y, kappa, 'k');

            % 设置标题显示曲率半径值
            title('curvature ');
            hold off;
            grid off;
            box on;
            colorbar;
            view(2); % 设置为2D视图
            xlabel('X (μm)');
            ylabel('Y (μm)');
        end
        function plot_kappa_patch(obj, options)
            % 绘制波导的曲率示意图
            % 输入:
            %   fig_handle: 可选的图窗句柄
            %   scale_factor: 宽度放大倍数，默认为1（不放大）

            arguments
                obj Wcli_wg
                options.fig_handle = gcf  % 默认使用当前图窗
                options.scale_factor (1,1) double {mustBePositive} = 1  % 默认不放大
            end

            obj_copy = obj.copy();
            obj_copy.set_width_list(obj.width_list * options.scale_factor);

            % 计算曲率
            [~, kappa] = obj.computeCurvatureRadius();
            % 设置图窗
            figure(options.fig_handle);
            set(gcf, 'Name', 'plot_R');

            patch([obj_copy.WOX, flip(obj_copy.WIX)], ...
                [obj_copy.WOY,  flip(obj_copy.WIY)], ...
                [kappa, flip(kappa)]);
            hold on;
            % 设置标题显示曲率半径值
            title('curvature ');
            hold off;
            grid off;
            box on;
            colorbar;
            view(2); % 设置为2D视图
            xlabel('X (μm)');
            ylabel('Y (μm)');
        end
        function plot_kappa_surf(obj, options)
            % 绘制波导的 3D 表面图（名称-值参数）
            % 允许独立控制几何高度、颜色映射（曲率/宽度）或单一着色
            
            arguments
                obj Wcli_wg
                options.fig_handle = []                % 图窗句柄，默认当前
                options.height_data = 10               % 高度数据: 标量或字符串('kappa', 'width')
                options.color_data = 'kappa'           % 颜色数据: 'kappa', 'width', 或十六进制颜色如 '#FF0000'
                options.scale_factor (1,1) double = 1  % 宽度显示放大倍数
                options.show_colorbar (1,1) logical = false % 是否显示颜色条
                options.view_angle = 3                 % 视角，2 为平面，3 为 3D
            end

            % 准备图窗
            if isempty(options.fig_handle), fig = gcf; else, fig = options.fig_handle; end
            figure(fig); hold on;

            % 复制对象用于宽度缩放显示
            obj_plot = obj.copy();
            if options.scale_factor ~= 1
                obj_plot.set_width_list(obj.width_list * options.scale_factor);
            end

            % 获取基础物理数据
            [~, kappa] = obj.computeCurvatureRadius();
            
            % 1. 处理高度数据 (Z 轴)
            if isnumeric(options.height_data) && isscalar(options.height_data)
                Z_val = repmat(options.height_data, size(kappa));
            elseif ischar(options.height_data) || isstring(options.height_data)
                switch lower(options.height_data)
                    case 'zero',  Z_val = zeros(size(kappa));
                    case 'kappa', Z_val = kappa;
                    case 'width', Z_val = obj.width_list;
                    otherwise,    Z_val = zeros(size(kappa));
                end
            else
                Z_val = options.height_data;
            end

            % 2. 处理颜色数据 (C Data)
            is_single_color = false;
            if ischar(options.color_data) || isstring(options.color_data)
                color_str = char(options.color_data);
                if startsWith(color_str, '#')
                    % 用户输入了十六进制颜色编号，进行单一着色
                    is_single_color = true;
                    single_color_val = color_str;
                    C_val = zeros(size(kappa)); % 占位，实际绘图使用 FaceColor
                else
                    switch lower(color_str)
                        case 'kappa', C_val = kappa;
                        case 'width', C_val = obj.width_list;
                        otherwise,    C_val = kappa;
                    end
                end
            else
                C_val = options.color_data;
            end

            % 3. 绘制表面
            X_mesh = [obj_plot.WOX; obj_plot.WIX];
            Y_mesh = [obj_plot.WOY; obj_plot.WIY];
            Z_mesh = [Z_val; Z_val];
            C_mesh = [C_val; C_val];
            if is_single_color
                surf(X_mesh, Y_mesh, Z_mesh, ...
                    'EdgeColor', 'none', ...
                    'FaceColor', single_color_val);
            else
                surf(X_mesh, Y_mesh, Z_mesh, C_mesh, ...
                    'EdgeColor', 'none', 'FaceColor', 'interp');
                
                if options.show_colorbar
                    cb = colorbar;
                    if strcmpi(options.color_data, 'kappa')
                        ylabel(cb, 'Curvature (\mu m^{-1})');
                    end
                end
            end

            view(options.view_angle);
            xlabel('X (\mu m)'); ylabel('Y (\mu m)');
            title(sprintf('Waveguide Surf (Height: %g, Color: %s)', ...
                mean(Z_val), char(options.color_data)));
            
            hold off;
        end

        function plot_trace(obj, options)
            % 绘制波导中心轨迹的简化函数
            % 只显示 WTX, WTY 路径，使用默认绘图参数
            % 
            % 名称-值参数:
            %   fig_handle   - 图窗句柄，默认使用当前图窗
            %   line_color   - 线条颜色，默认 'b' (蓝色)
            %   line_width   - 线条宽度，默认 1.5
            %   line_style   - 线型，默认 '-'
            %   show_grid    - 是否显示网格，默认 true
            %   show_start_end - 是否标记起点和终点，默认 true
            %   marker_size  - 起点终点标记大小，默认 8
            %
            % 示例:
            %   obj.plot_trace();  % 使用全部默认参数
            %   obj.plot_trace('line_color', 'r', 'line_width', 2);  % 红色粗线
            %   obj.plot_trace('show_start_end', false);  % 不显示起点终点标记
        
            arguments
                obj Wcli_wg
                options.fig_handle = []
                options.line_color = '#1493ce'
                options.line_width (1,1) double {mustBePositive} = 1.5
                options.line_style (1,:) char = '-'
                options.show_start_end (1,1) logical = false
                options.marker_size (1,1) double {mustBePositive} = 8
            end
            
            % 确定使用哪个图窗
            if isempty(options.fig_handle)
                fig_handle = gcf;
            else
                fig_handle = options.fig_handle;
            end
            
            figure(fig_handle);
            hold on;
            
            % 绘制中心轨迹
            plot(obj.WTX, obj.WTY, ...
                'Color', options.line_color, ...
                'LineWidth', options.line_width, ...
                'LineStyle', options.line_style, ...
                'DisplayName', 'Trace');
            
            % 标记起点和终点
            if options.show_start_end
                % 起点 (绿色圆圈)
                plot(obj.WTX(1), obj.WTY(1), 'go', ...
                    'MarkerSize', options.marker_size, ...
                    'MarkerFaceColor', 'g', ...
                    'DisplayName', 'Start');
                
                % 终点 (红色方块)
                plot(obj.WTX(end), obj.WTY(end), 'rs', ...
                    'MarkerSize', options.marker_size, ...
                    'MarkerFaceColor', 'r', ...
                    'DisplayName', 'End');
                
                legend('show', 'Location', 'best');
            end
            
            % 设置坐标轴和标签
            axis equal;
            xlabel('X (μm)');
            ylabel('Y (μm)');
            title('Waveguide Center Trace');
            
            box on;
            hold off;
        end


        function plot_3D_wg(obj, fig_handle, scale_factor)
            % 绘制波导的3D结构＋曲率半径示意图
            % 输入:
            %   fig_handle: 可选的图窗句柄

            % 设置默认值

            if nargin < 2
                fig_handle = gcf;
                scale_factor = 10; % 缩放因子
            end

            if nargin < 3
                scale_factor = 5; % 缩放因子
            end

            % 计算曲率半径
            [~, kappa] = obj.computeCurvatureRadius();
            % 设置图窗
            figure(fig_handle);
            set(gcf, 'Name', 'plot_R');
            % 绘制曲率半径
            x = obj.WTX;
            y = obj.WTY;
            h_wg = obj.thickness * scale_factor; % 波导高度（单位：μm）
            plot3(x, y, kappa * 0 + h_wg / 2, 'Color', 'k');
            hold on;

            surf([obj.WOX_top; obj.WIX_top], ...
                [obj.WOY_top; obj.WIY_top], ...
                [kappa; kappa] * 0 + h_wg, ...
                [kappa; kappa], ...
                'EdgeColor', 'none', 'FaceColor', 'interp');
            surf([obj.WOX_top; obj.WOX], ...
                [obj.WOY_top; obj.WOY], ...
                [kappa * 0 + h_wg; kappa * 0], ...
                [kappa; kappa], ...
                'EdgeColor', 'none', 'FaceColor', 'interp');
            surf([obj.WOX; obj.WIX], ...
                [obj.WOY; obj.WIY], ...
                [kappa; kappa] * 0, ...
                [kappa; kappa], ...
                'EdgeColor', 'none', 'FaceColor', 'interp');
            surf([obj.WIX; obj.WIX_top], ...
                [obj.WIY; obj.WIY_top], ...
                [kappa * 0; kappa * 0 + h_wg], ...
                [kappa; kappa], ...
                'EdgeColor', 'none', 'FaceColor', 'interp');
            patch([obj.WOX(1), obj.WOX_top(1), obj.WIX_top(1), obj.WIX(1)], ...
                [obj.WOY(1), obj.WOY_top(1), obj.WIY_top(1), obj.WIY(1)], ...
                [0, h_wg, h_wg, 0], ...
                [kappa(1), kappa(1), kappa(1), kappa(1)], ...
                'EdgeColor', 'none', 'FaceColor', 'interp');

            patch([obj.WOX(end), obj.WOX_top(end), obj.WIX_top(end), obj.WIX(end)], ...
                [obj.WOY(end), obj.WOY_top(end), obj.WIY_top(end), obj.WIY(end)], ...
                [0, h_wg, h_wg, 0], ...
                [kappa(end), kappa(end), kappa(end), kappa(end)], ...
                'EdgeColor', 'none', 'FaceColor', 'interp');

            % 设置标题显示曲率半径值
            title('Wg 3D structure with Curvature');
            % 创建 light
            x_min = min(obj.WOX); % 最小x坐标
            y_min = min(obj.WOY); % 最小y坐标
            % 设置光照位置（在左下角正上方）
            light('Position', [x_min, y_min, h_wg * 50]); % 高度设为波导高度的10倍
            lighting gouraud; % 设置光照渲染模式，使表面更平滑
            material dull; % 设置材质属性，使光照效果更自然

            hold off;
            axis equal;
            c = colorbar;
            c.Label.String = 'Curvature (μm-1)';
            c.Label.FontSize = 12;
            xlabel('X (μm)');
            ylabel('Y (μm)');
            zlabel('Z (μm)');
            zlim([-h_wg * 3, h_wg * 6]);
            view(3); % 设置为3D视图
        end
        function plot_3d(obj, options)
            % 绘制波导的 3D 实体模型
            % 支持单一颜色着色或根据曲率 (kappa) 映射颜色
            
            arguments
                obj Wcli_wg
                options.color = '#1493ce'        % 十六进制颜色、'kappa'、或 [N x 3] 颜色矩阵
                options.scale_h (1,1) double = 4   % 高度放大的倍数
                options.height (1,1) double = 0     % 整体起始高度 (Z轴偏移)
                options.fig_handle = []             % 图窗句柄
                options.show_colorbar (1,1) logical = false % 是否显示颜色条
            end

            % 确定图窗
            if isempty(options.fig_handle), fig = gcf; else, fig = options.fig_handle; end
            figure(fig); hold on;

            
            h_wg = obj.thickness * options.scale_h; % 波导自身显示厚度
            z_bot = options.height-h_wg/2;                 % 底面高度
            z_top = z_bot + h_wg;                   % 顶面高度

            % 获取曲率数据用于颜色映射
            [~, kappa] = obj.computeCurvatureRadius();
            C_mesh = [kappa; kappa]; % 将曲率映射到 surf 的颜色属性

            % 判断着色模式
            is_mapping = false;
            col = options.color;
            
            if ischar(col) || isstring(col)
                if strcmpi(col, 'kappa')
                    is_mapping = true;
                    face_mode = 'interp';
                else
                    % 单一颜色字符串或十六进制
                    face_mode = col;
                end
            elseif isnumeric(col) && size(col, 2) == 3
                % 输入的是色彩矩阵 (Colormap)
                is_mapping = true;
                face_mode = 'interp';
                colormap(fig, col);
            else
                face_mode = '#1493ce'; % 默认色
            end

            % 绘制各个面
            % 1. 顶面
            surf([obj.WOX_top; obj.WIX_top], [obj.WOY_top; obj.WIY_top], ...
                zeros(2, length(obj.WTX)) + z_top, C_mesh, 'EdgeColor', 'none', 'FaceColor', face_mode);
            
            % 2. 侧面 (外侧)
            surf([obj.WOX_top; obj.WOX], [obj.WOY_top; obj.WOY], ...
                [zeros(1, length(obj.WTX)) + z_top; zeros(1, length(obj.WTX)) + z_bot], ...
                C_mesh, 'EdgeColor', 'none', 'FaceColor', face_mode);
            
            % 3. 底面
            surf([obj.WOX; obj.WIX], [obj.WOY; obj.WIY], ...
                zeros(2, length(obj.WTX)) + z_bot, C_mesh, 'EdgeColor', 'none', 'FaceColor', face_mode);
            
            % 4. 侧面 (内侧)
            surf([obj.WIX; obj.WIX_top], [obj.WIY; obj.WIY_top], ...
                [zeros(1, length(obj.WTX)) + z_bot; zeros(1, length(obj.WTX)) + z_top], ...
                C_mesh, 'EdgeColor', 'none', 'FaceColor', face_mode);
            % 5.输入口
%             keyboard
            surf([obj.WIX(1),obj.WOX(1); obj.WIX_top(1),obj.WOX_top(1)], [obj.WIY(1),obj.WOY(1); obj.WIY_top(1),obj.WOY_top(1)], ...
                [zeros(1, 2) + z_bot; zeros(1, 2) + z_top], ...
                C_mesh(1)*ones(2, 2), 'EdgeColor', 'none', 'FaceColor', face_mode);
            % 设置视图和辅助效果
            view(3); axis equal;
            xlabel('X (\mu m)'); ylabel('Y (\mu m)'); zlabel('Z (\mu m)');
            
            if is_mapping && options.show_colorbar
                cb = colorbar;
                ylabel(cb, 'Curvature (\mu m^{-1})');
            end
            
%             camlight;
            % lighting gouraud; 
            hold off;
        end

        function plot_2d(obj, options)
            % 绘制波导的 2D 填充图
            % 
            % 名称-值参数:
            %   fig_handle   - 图窗句柄，默认使用当前图窗
            %   face_color   - 填充颜色，默认 '#4DBEEE'（浅蓝色）
            %                  可以是：'r', 'g', 'b', [R G B], 'auto', 十六进制等
            %   edge_color   - 边界颜色，默认 'none'（无边界）
            %   face_alpha   - 填充透明度，默认 1 (0-1)
            %   edge_width   - 边界线宽，默认 1
            %   use_top      - 使用顶部坐标还是底部坐标，默认根据 width_mode
            %
            % 示例:
            %   obj.plot_2d();  % 使用默认参数
            %   obj.plot_2d('face_color', 'r');  % 红色填充
            %   obj.plot_2d('face_color', [0.3 0.75 0.93]);  % RGB 颜色
            %   obj.plot_2d('face_color', 'auto', 'edge_color', 'k');  % 自动颜色+黑边
        
            arguments
                obj Wcli_wg
                options.fig_handle = []
                options.face_color = '#1493ce'
                options.edge_color = 'none'
                options.face_alpha (1,1) double {mustBeInRange(options.face_alpha, 0, 1)} = 1
                options.edge_width (1,1) double {mustBePositive} = 1
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
            
            % 获取坐标并构造闭合多边形
            if use_top
                % 使用顶部坐标：外沿 + 翻转的内沿
                poly_x = [obj.WOX_top(:); flipud(obj.WIX_top(:))];
                poly_y = [obj.WOY_top(:); flipud(obj.WIY_top(:))];
            else
                % 使用底部坐标：外沿 + 翻转的内沿
                poly_x = [obj.WOX(:); flipud(obj.WIX(:))];
                poly_y = [obj.WOY(:); flipud(obj.WIY(:))];
            end
            
            % 确保多边形闭合（首尾相连）
            if ~isequal([poly_x(1), poly_y(1)], [poly_x(end), poly_y(end)])
                poly_x(end+1) = poly_x(1);
                poly_y(end+1) = poly_y(1);
            end
            
            % 处理颜色参数
            if strcmpi(options.face_color, 'auto')
                % 使用 MATLAB 自动颜色（从默认色序中获取下一个颜色）
                patch_handle = patch('XData', poly_x, 'YData', poly_y, ...
                    'EdgeColor', options.edge_color, ...
                    'FaceAlpha', options.face_alpha, ...
                    'LineWidth', options.edge_width);
            else
                % 使用指定颜色
                patch_handle = patch('XData', poly_x, 'YData', poly_y, ...
                    'FaceColor', options.face_color, ...
                    'EdgeColor', options.edge_color, ...
                    'FaceAlpha', options.face_alpha, ...
                    'LineWidth', options.edge_width);
            end
            
            % 设置坐标轴
            axis equal;
            xlabel('X (μm)');
            ylabel('Y (μm)');
            
            % 设置标题
            if use_top
                title('Waveguide 2D (Top Surface)');
            else
                title('Waveguide 2D (Bottom Surface)');
            end
            
            hold off;
            box on;
        end

        function plot_R_all(obj, fig_handle)
            % 绘制波导的曲率半径示意图
            % 输入:
            %   idx: 要显示曲率半径的点的索引，默认为1
            %   fig_handle: 可选的图窗句柄

            if nargin < 2
                fig_handle = gcf;
            end

            % 计算曲率半径
            [R, ~] = obj.computeCurvatureRadius();
            L_list = obj.calc_length_list();

            % 设置图窗
            figure(fig_handle);
            set(gcf, 'Name', 'plot_R_all');
            plot(L_list, R, 'LineWidth', 1);
            title('Radius of curvature');
            xlabel('Length (μm)');
            ylabel('Radius of curvature (μm)');
        end

        function plot_width_all(obj, fig_handle)
            % 绘制波导宽度沿长度的变化图
            % 输入:
            %   fig_handle: 可选的图窗句柄

            if nargin < 2
                fig_handle = gcf;
            end

            % 计算长度列表
            L_list = obj.calc_length_list();

            % 根据宽度模式确定显示的宽度
            if obj.width_mode == 1
                % 顶部宽度模式 - 显示顶部宽度
                display_width = obj.width_list - obj.delta_w;
                width_label = 'Top Width (μm)';
                title_text = 'Top Width Distribution';
            else
                % 底部宽度模式 - 显示底部宽度
                display_width = obj.width_list;
                width_label = 'Bottom Width (μm)';
                title_text = 'Bottom Width Distribution';
            end

            % 设置图窗
            figure(fig_handle);
            set(gcf, 'Name', 'plot_width_all');
            plot(L_list, display_width, 'LineWidth', 1.5);
            title(title_text);
            xlabel('Length (μm)');
            ylabel(width_label);
            grid on;

            % 添加宽度统计信息到图中
            min_width = min(display_width);
            max_width = max(display_width);
            avg_width = mean(display_width);

            % 在图上添加文本信息
            text(0.02, 0.98, sprintf('Min: %.3f μm\nMax: %.3f μm\nAvg: %.3f μm', ...
                min_width, max_width, avg_width), ...
                'Units', 'normalized', 'VerticalAlignment', 'top', ...
                'BackgroundColor', 'white', 'EdgeColor', 'black');
        end

        function plot_kappa_all(obj, fig_handle)
            % 绘制波导的曲率半径示意图
            % 输入:
            %   idx: 要显示曲率半径的点的索引，默认为1
            %   fig_handle: 可选的图窗句柄

            if nargin < 2
                fig_handle = gcf;
            end

            % 计算曲率
            [~, kappa] = obj.computeCurvatureRadius();
            L_list = obj.calc_length_list();
            L_list = L_list-mean(L_list); % 将长度中心化，便于观察曲率变化趋势
            % 设置图窗
            figure(fig_handle);
            set(gcf, 'Name', 'plot_R_all');
            plot(L_list, kappa, 'LineWidth', 1);
            title('kappa-curvature');
            xlabel('Length (μm)');
            ylabel('curvature (μm-1)');
        end

        function plot_theta_all(obj, fig_handle)
            % 绘制波导的曲率半径示意图
            % 输入:
            %   idx: 要显示曲率半径的点的索引，默认为1
            %   fig_handle: 可选的图窗句柄

            if nargin < 2
                fig_handle = gcf;
            end

            L_list = obj.calc_length_list();
            angle_list = wrapToPi(obj.theta_list) / pi * 180;
            % 设置图窗
            figure(fig_handle);
            set(gcf, 'Name', 'plot_theta_all');
            plot(L_list, angle_list, 'LineWidth', 1);
            title('theta');
            xlabel('Length (μm)');
            ylabel('theta(°)');
            ylim([-200, 200])
        end

        function gradient_kappa = plot_d_kappa_all(obj, fig_handle)
            % 绘制波导的曲率半径示意图
            % 输入:
            %   idx: 要显示曲率半径的点的索引，默认为1
            %   fig_handle: 可选的图窗句柄

            if nargin < 2
                fig_handle = gcf;
            end

            % 计算曲率半径
            [~, kappa] = obj.computeCurvatureRadius();
            L_list = obj.calc_length_list();
            gradient_kappa = gradient(kappa, L_list); % 计算曲率的梯度
            % 设置图窗
            figure(fig_handle);
            set(gcf, 'Name', 'plot_R_all');
            plot(L_list, gradient_kappa, 'LineWidth', 1);
            title('dkappa of curvature');
            xlabel('Length (μm)');
            ylabel('diff curvature (μm-2)');
            % ylim([-0.2, 0.2]);
        end

        % % 定义内部函数进行旋转和平移变换
        % function [X_new, Y_new] = rotate_translate(~, X_old, Y_old, theta, T_x, T_y)
        %     cos_theta = cos(theta);
        %     sin_theta = sin(theta);
        %     % 进行旋转
        %     X_rot = X_old * cos_theta - Y_old * sin_theta;
        %     Y_rot = X_old * sin_theta + Y_old * cos_theta;

        %     % 进行平移
        %     X_new = X_rot + T_x;
        %     Y_new = Y_rot + T_y;
        % end
        %% 对象变换方法
        function obj = resample_by_length(obj, N_point, method)
            % 按传播弧长对当前波导对象重采样
            % N_point: 重采样后的点数
            % method : 插值方法，'linear' 或 'pchip'，默认 'linear'
        
            arguments
                obj Wcli_wg
                N_point (1,1) double {mustBeInteger, mustBePositive}
                method (1,:) char {mustBeMember(method, {'linear','pchip'})} = 'linear'
            end
        
            % 点太少无法重采样
            if length(obj.WTX) < 2
                warning('当前对象点数不足，跳过重采样');
                return;
            end
        
            % 原始弧长
            L_raw = obj.calc_length_list();
        
            % 去掉重复弧长点，避免 interp1 报错
            [L_u, ia] = unique(L_raw, 'stable');
            if numel(L_u) < 2
                warning('有效弧长点不足，跳过重采样');
                return;
            end
        
            x_u = obj.WTX(ia);
            y_u = obj.WTY(ia);
            w_u = obj.width_list(ia);
        
            % 角度先 unwrap 再插值，避免跨 ±pi 跳变
            theta_u = unwrap(obj.theta_list(ia));
        
            % 目标等弧长采样点
            L_new = linspace(0, L_u(end), N_point);
        
            % 插值
            x_new = interp1(L_u, x_u, L_new, method);
            y_new = interp1(L_u, y_u, L_new, method);
            theta_new = interp1(L_u, theta_u, L_new, method);
            w_new = interp1(L_u, w_u, L_new, method);
        
            theta_new = wrapToPi(theta_new);
        
            % 回写中心线与截面
            obj.trace2shape(x_new, y_new, theta_new, w_new);
        
            % 刷新派生量
            obj.L_list = obj.calc_length_list();
            obj.calc_trace_length();
        end
        function swap_shape(obj)
            % 将波导对象的内外波导进行交换
            %
            % 输入：无需额外输入
            % 输出：无返回值，直接修改对象属性

            % 临时保存外部波导的值
            temp_WOX = obj.WOX;
            temp_WOY = obj.WOY;
            temp_WOX_top = obj.WOX_top;
            temp_WOY_top = obj.WOY_top;

            % 交换内外波导
            obj.WOX = obj.WIX;
            obj.WOY = obj.WIY;
            obj.WOX_top = obj.WIX_top;
            obj.WOY_top = obj.WIY_top;

            % 完成交换
            obj.WIX = temp_WOX;
            obj.WIY = temp_WOY;
            obj.WIX_top = temp_WOX_top;
            obj.WIY_top = temp_WOY_top;

            % WTX 和 WTY 不需要改变，因为它们代表中心轨迹
        end

        function set_width_list(obj, new_width_list)
            % 设置新的波导宽度并更新所有相关坐标
            % 输入参数:
            %   new_width_list - 新的宽度列表，可以是标量或与轨迹点数相同长度的向量

            arguments
                obj Wcli_wg
                new_width_list {mustBeNumeric, mustBePositive} % 新的宽度列表，必须为正数
            end

            % 如果new_width_list是标量，扩展为与TX同样长度的向量
            if isscalar(new_width_list)
                new_width_list = repmat(new_width_list, size(obj.WTX));
            elseif length(new_width_list) ~= length(obj.WTX)
                error('new_width_list的长度必须为1或与轨迹点数(%d)相同', n_points);
            end

            % 更新width_list
            obj.width_list = new_width_list;

            % 如果是顶部宽度模式，调整width_list为底部宽度
            if obj.width_mode
                bot_width_list = new_width_list + obj.delta_w;
                top_width_list = new_width_list;
            else
                bot_width_list = new_width_list;
                top_width_list = new_width_list - obj.delta_w;
            end

            % 重新计算波导轮廓坐标（底部）
            obj.WOX = obj.WTX - bot_width_list / 2 .* sin(obj.theta_list);
            obj.WOY = obj.WTY + bot_width_list / 2 .* cos(obj.theta_list);
            obj.WIX = obj.WTX + bot_width_list / 2 .* sin(obj.theta_list);
            obj.WIY = obj.WTY - bot_width_list / 2 .* cos(obj.theta_list);

            obj.WOX_top = obj.WTX - top_width_list / 2 .* sin(obj.theta_list);
            obj.WOY_top = obj.WTY + top_width_list / 2 .* cos(obj.theta_list);
            obj.WIX_top = obj.WTX + top_width_list / 2 .* sin(obj.theta_list);
            obj.WIY_top = obj.WTY - top_width_list / 2 .* cos(obj.theta_list);

            % 可选：显示更新信息
            %             if nargout == 0 % 如果没有输出参数，显示信息
            %                 fprintf('波导宽度已更新:\n');
            %                 fprintf('  最小宽度: %.3f μm\n', min(obj.width_list));
            %                 fprintf('  最大宽度: %.3f μm\n', max(obj.width_list));
            %                 fprintf('  平均宽度: %.3f μm\n', mean(obj.width_list));
            %
            %                 if length(unique(obj.width_list)) == 1
            %                     fprintf('  宽度类型: 均匀宽度\n');
            %                 else
            %                     fprintf('  宽度类型: 渐变宽度\n');
            %                 end
            %
            %             end

        end

        function trace2shape(obj, TX, TY, theta_list, width_list)
            % 根据给定的轨迹和参数更新波导形状
            %
            % 输入:
            %   TX, TY - 中心轨迹坐标
            %   theta_list - 角度列表
            %   width_list - 宽度列表

            % 计算外部波导坐标
            obj.WOX = TX - (width_list + obj.width_mode*obj.delta_w) / 2 .* sin(theta_list);
            obj.WOY = TY + (width_list + obj.width_mode*obj.delta_w) / 2 .* cos(theta_list);
            obj.WIX = TX + (width_list + obj.width_mode*obj.delta_w) / 2 .* sin(theta_list);
            obj.WIY = TY - (width_list + obj.width_mode*obj.delta_w) / 2 .* cos(theta_list);

            % 计算顶部波导坐标
            obj.WOX_top = TX - (width_list - (1-obj.width_mode)*obj.delta_w) / 2 .* sin(theta_list);
            obj.WOY_top = TY + (width_list - (1-obj.width_mode)*obj.delta_w) / 2 .* cos(theta_list);
            obj.WIX_top = TX + (width_list - (1-obj.width_mode)*obj.delta_w) / 2 .* sin(theta_list);
            obj.WIY_top = TY - (width_list - (1-obj.width_mode)*obj.delta_w) / 2 .* cos(theta_list);

            % 更新中心轨迹和参数
            obj.WTX = TX;
            obj.WTY = TY;
            obj.theta_list = theta_list;
            obj.width_list = width_list;
            obj.calc_trace_length();
        end

        function obj = transform_shape(obj, theta, T_x, T_y)
            % 对波导对象进行旋转和平移变换
            %
            % 输入:
            %   theta: 旋转角度（以弧度为单位）
            %   T_x: 沿X轴的平移量 (默认值为0)
            %   T_y: 沿Y轴的平移量 (默认值为0)

            % 设置默认值
            if nargin < 3
                T_x = 0;
            end

            if nargin < 4
                T_y = 0;
            end

            % 对所有坐标进行旋转和平移
            [obj.WOX, obj.WOY] = Wcli_wg.rotate_translate(obj.WOX, obj.WOY, theta, T_x, T_y);
            [obj.WIX, obj.WIY] = Wcli_wg.rotate_translate(obj.WIX, obj.WIY, theta, T_x, T_y);
            [obj.WOX_top, obj.WOY_top] = Wcli_wg.rotate_translate(obj.WOX_top, obj.WOY_top, theta, T_x, T_y);
            [obj.WIX_top, obj.WIY_top] = Wcli_wg.rotate_translate(obj.WIX_top, obj.WIY_top, theta, T_x, T_y);
            [obj.WTX, obj.WTY] = Wcli_wg.rotate_translate(obj.WTX, obj.WTY, theta, T_x, T_y);

            % 更新角度列表
            obj.theta_list = obj.theta_list + theta;
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
                obj Wcli_wg
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
        function next_obj = align_wg(obj, next_obj, align_mode, targetxy)
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
                obj Wcli_wg
                next_obj Wcli_wg
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
                obj Wcli_wg
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
        function obj = align_port_in(obj, targetxy)
            % 将输入端口对齐到目标坐标
            % 输入:
            %   target_x - 目标x坐标 (μm)
            %   target_y - 目标y坐标 (μm)

            arguments
                obj Wcli_wg
                targetxy (1,2) double = [0,0]
            end

            % 获取当前输入端口位置
            current_x = obj.WTX(1);
            current_y = obj.WTY(1);

            % 计算平移量
            T_x = targetxy(1) - current_x;
            T_y = targetxy(2) - current_y;

            % 应用平移
            obj.transform_shape(0, T_x, T_y);
        end
        function obj = align_port_out(obj, targetxy)
            % 将输出端口对齐到目标坐标
            % 输入:
            %   target_x - 目标x坐标 (μm)
            %   target_y - 目标y坐标 (μm)

            arguments
                obj Wcli_wg
                targetxy (1,2) double = [0,0]
            end

            % 获取当前输出端口位置
            current_x = obj.WTX(end);
            current_y = obj.WTY(end);

            % 计算平移量
            T_x = targetxy(1) - current_x;
            T_y = targetxy(2) - current_y;

            % 应用平移
            obj.transform_shape(0, T_x, T_y);
        end
        %% 获取长度
        function L = calc_trace_length(obj)
            % 计算轨迹总长度
            % 返回:
            %   L: 轨迹总长度（μm）

            % 计算相邻点之间的差值
            dx = diff(obj.WTX);
            dy = diff(obj.WTY);

            % 计算每段的长度并求和
            L = sum(sqrt(dx .^ 2 + dy .^ 2));

            % 更新对象属性
            obj.trace_length = L;
        end

        function L_list = calc_length_list(obj)
            % 计算轨迹总长度
            % 返回:
            %   L: 轨迹总长度（μm）

            % 计算相邻点之间的差值
            dx = diff(obj.WTX);
            dy = diff(obj.WTY);

            % 计算每段的长度并求和
            L_list = cumsum(sqrt(dx .^ 2 + dy .^ 2));
            L_list = [0, L_list];
            obj.L_list = L_list;

        end
        %% 获取波导端口和边界信息的方法
        function output = get_port_in(obj)
            % 计算轨迹总长度
            % 返回:
            %   L: 轨迹总长度（μm）

            x = obj.WTX(1);
            y = obj.WTY(1);
            angle = obj.theta_list(1); % 角度列表的第一个值
            output = [x, y, angle];

        end
        function output = get_port_inxy(obj)
            % 计算轨迹总长度
            % 返回:
            %   L: 轨迹总长度（μm）

            x = obj.WTX(1);
            y = obj.WTY(1);
            output = [x, y];

        end

        function output = get_port_out(obj)
            % 计算轨迹总长度
            % 返回:
            %   L: 轨迹总长度（μm）

            x = obj.WTX(end);
            y = obj.WTY(end);
            angle = obj.theta_list(end); % 角度列表的最后一个值
            output = [x, y, angle];
        end
        function output = get_port_outxy(obj)
            % 计算轨迹总长度
            % 返回:
            %   L: 轨迹总长度（μm）

            x = obj.WTX(end);
            y = obj.WTY(end);
            output = [x, y];
        end

        function x_in = get_port_in_x(obj)
            % 计算输入端口的x坐标
            % 返回:
            %   x_in: 输入端口x坐标（μm）

            x_in = obj.WTX(1);
        end

        function y_in = get_port_in_y(obj)
            % 计算输入端口的y坐标
            % 返回:
            %   y_in: 输入端口y坐标（μm）

            y_in = obj.WTY(1);
        end

        function x_out = get_port_out_x(obj)
            % 计算输出端口的x坐标
            % 返回:
            %   x_out: 输出端口x坐标（μm）

            x_out = obj.WTX(end);
        end

        function y_out = get_port_out_y(obj)
            % 计算输出端口的y坐标
            % 返回:
            %   y_out: 输出端口y坐标（μm）

            y_out = obj.WTY(end);
        end

        function dx = get_port_dx(obj)
            % 计算输入端口到输出端口的x方向位移
            % 返回:
            %   dx: x方向位移（μm）

            port_in = obj.get_port_in(); % [x_in, y_in, angle_in]
            port_out = obj.get_port_out(); % [x_out, y_out, angle_out]

            dx = port_out(1) - port_in(1); % x_out - x_in
        end

        function dy = get_port_dy(obj)
            % 计算输入端口到输出端口的y方向位移
            % 返回:
            %   dy: y方向位移（μm）

            port_in = obj.get_port_in(); % [x_in, y_in, angle_in]
            port_out = obj.get_port_out(); % [x_out, y_out, angle_out]

            dy = port_out(2) - port_in(2); % y_out - y_in
        end

        function output = get_boundary_points(obj)
            % 计算整个波导结构的边界点坐标
            % 返回:
            %   x_min: 结构最小x坐标
            %   x_max: 结构最大x坐标
            %   y_min: 结构最小y坐标
            %   y_max: 结构最大y坐标
            if obj.width_mode
            % 收集所有x坐标和y坐标
            x_coords = [ obj.WOX_top, obj.WIX_top];
            y_coords = [obj.WOY_top, obj.WIY_top];
            else
            % 收集所有x坐标和y坐标
            x_coords = [obj.WOX, obj.WIX];
            y_coords = [obj.WOY, obj.WIY];
            end
            x_min = min(x_coords);
            x_max = max(x_coords);
            y_min = min(y_coords);
            y_max = max(y_coords);
            output = [x_min, y_min; x_max, y_max];
        end

        function dx = get_boundary_dx(obj)
            output = obj.get_boundary_points;
            dx = output(2,1)-output(1,1);
        end
        
        function dy = get_boundary_dy(obj)
            % 计算整个波导结构在y方向上的尺寸
            % 返回:
            %   dy: 结构在y方向的尺寸（μm）
            
            boundary = obj.get_boundary_points();
            dy = boundary(2,2) - boundary(1,2);
        end
        
        function x_min = get_boundary_xmin(obj)
            % 计算整个波导结构的最小x坐标
            % 返回:
            %   x_min: 结构最小x坐标（μm）
            
            boundary = obj.get_boundary_points();
            x_min = boundary(1,1);
        end
        
        function x_max = get_boundary_xmax(obj)
            % 计算整个波导结构的最大x坐标
            % 返回:
            %   x_max: 结构最大x坐标（μm）
            
            boundary = obj.get_boundary_points();
            x_max = boundary(2,1);
        end
        
        function y_min = get_boundary_ymin(obj)
            % 计算整个波导结构的最小y坐标
            % 返回:
            %   y_min: 结构最小y坐标（μm）
            
            boundary = obj.get_boundary_points();
            y_min = boundary(1,2);
        end
        
        function y_max = get_boundary_ymax(obj)
            % 计算整个波导结构的最大y坐标
            % 返回:
            %   y_max: 结构最大y坐标（μm）
            
            boundary = obj.get_boundary_points();
            y_max = boundary(2,2);
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
                obj Wcli_wg
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


        function [R, kappa] = computeCurvatureRadius(obj)
            % 计算一阶导数
            %             dx = gradient(obj.WTX);
            %             dy = gradient(obj.WTY);
            %             delta_s = sqrt(dx .^ 2 + dy .^ 2);
            delta_s = gradient(obj.L_list);
            theta_unwrapped = unwrap(obj.theta_list);
            delta_phi = gradient(theta_unwrapped);

            % dx = diff(obj.WTX);
            % dy = diff(obj.WTY);
            % delta_s = sqrt(dx .^ 2 + dy .^ 2);
            % delta_phi = diff(obj.theta_list);

            R = delta_s ./ delta_phi; %数值计算曲率半径

            % R = [R, R(end)]; % 补齐最后一个点的曲率半径
            kappa = 1 ./ R;

        end

        %         function new_obj = copy(obj)
        %             % 创建对象的深度复制
        %             %
        %             % 返回:
        %             %   new_obj: Wcli_wg对象的新副本
        %
        %             % 使用构造函数创建新对象
        %             new_obj = Wcli_wg();
        %             p = properties(obj); % 获取所有属性名
        %
        %             for i = 1:length(p)
        %                 new_obj.(p{i}) = obj.(p{i}); % 复制每个属性的值
        %             end
        %
        %         end
        %% gds 直接生成
        function dataoutputs = generate_gds(obj, FileDc, layers, cell_name)

            arguments
                obj Wcli_wg
                FileDc (1, :) char % 文件路径
                layers (1, 1) double {mustBeInteger, mustBePositive} % 层号必须为正整数
                cell_name (1, :) char % 结构名称
            end

            MAX_POINTS = 2040; %实际包含内外两侧，2040*2=4080，要考虑段间连接
            total_points = length(obj.WOX);
            num_segments = ceil(total_points / MAX_POINTS);
            dataoutputs = cell(1, num_segments);
            % 检查最后一段的点数，如果小于2个点就减少段数
            if num_segments > 1
                last_segment_start = (num_segments - 1) * MAX_POINTS + 1;
                last_segment_points = total_points - last_segment_start + 1;

                % 如果最后一段小于2个点，合并到前一段
                if last_segment_points < 2
                    num_segments = num_segments - 1;
                end

            end

            for i = 1:num_segments
                start_idx = (i - 1) * MAX_POINTS + 1;

                if i <= num_segments - 1
                    end_idx = i * MAX_POINTS + 2; %加1是为了包含最后一个点
                else
                    end_idx = total_points; % 最后一个段的结束索引
                end

                % end_idx = min(i * MAX_POINTS, total_points);
                if obj.width_mode
                    current_WOX = obj.WOX_top(start_idx:end_idx);
                    current_WOY = obj.WOY_top(start_idx:end_idx);
                    current_WIX = obj.WIX_top(start_idx:end_idx);
                    current_WIY = obj.WIY_top(start_idx:end_idx);
                else
                    current_WOX = obj.WOX(start_idx:end_idx);
                    current_WOY = obj.WOY(start_idx:end_idx);
                    current_WIX = obj.WIX(start_idx:end_idx);
                    current_WIY = obj.WIY(start_idx:end_idx);
                end
                data_temp = [current_WOX, flip(current_WIX);
                    current_WOY, flip(current_WIY)]';
                dataoutputs{i} = round(data_temp * 1e3); % 转换为整数
            end


            % 路径处理
            [folder_path, ~, ~] = fileparts(FileDc);

            if ~isempty(folder_path) && ~exist(folder_path, 'dir')
                mkdir(folder_path);
            end

            fid = fopen(FileDc, 'w');

            fprintf(fid, 'HEADER 600\r\n');
            fprintf(fid, 'BGNLIB 4/20/2021 12:33:18 4/20/2021 12:33:18 \r\n');
            fprintf(fid, 'LIBNAME SBend\r\n');
            fprintf(fid, 'UNITS 0.005 1e-009 \r\n');
            fprintf(fid, 'BGNSTR 4/20/2021 12:33:18 4/20/2021 12:33:18  \r\n');

            if mod(length(cell_name), 2) ~= 0
                cell_name = [cell_name 'E']; % 如果长度为奇数，添加'E'
            end

            fprintf(fid, 'STRNAME %s\r\n', cell_name);

            for idx = 1:length(dataoutputs)
                data = dataoutputs{idx};
                Wcli_wg.write_boundary(fid, data, layers);
            end

            fprintf(fid, 'ENDSTR \r\n');
            fprintf(fid, 'ENDLIB \r\n');
            fclose(fid);
        end
        function dataoutput = gds_point_output(obj, unit)
            % 将波导坐标数据转换为GDS格式点数据
            % 直接处理全部点，不进行分段
            % 
            % 输入参数:
            %   obj - Wcli_wg对象
            %   unit - 输出单位，'nm' 或 'um'（可选，默认'nm'）
            %
            % 输出:
            %   dataoutput - 转换后的点数据矩阵（整数）
            
            if nargin < 2
                unit = 'nm';  % 默认单位为nm
            end
            
            % 根据width_mode选择坐标数据
            if obj.width_mode
                WOX = obj.WOX_top;
                WOY = obj.WOY_top;
                WIX = obj.WIX_top;
                WIY = obj.WIY_top;
            else
                WOX = obj.WOX;
                WOY = obj.WOY;
                WIX = obj.WIX;
                WIY = obj.WIY;
            end
            
            % 组合数据：外侧点 + 翻转的内侧点
            data_temp = [WOX, flip(WIX);
                         WOY, flip(WIY)]';
            
            % 根据单位转换
            if strcmpi(unit, 'nm')
                dataoutput = round(data_temp * 1e3);  % um转nm
            else
                dataoutput = round(data_temp * 1e3) / 1e3;  % 保留3位小数
            end
        end

        %% FDTD转换
        function vtx = posdata2fdtd(obj)
            % 获取 FDTD 仿真所需的顶点数据
            % 将坐标转换为 FDTD 仿真格式：翻转坐标顺序，乘以 1e3 并四舍五入为整数
            %
            % 输入:
            %   h_wg - 波导高度（单位：μm）
            %
            % 输出:
            %   vtx - Nx3 矩阵，包含波导所有顶点的三维坐标
            h_wg = obj.thickness; % 波导高度（单位：μm）
            % 转换并处理坐标
            WOX_scaled = round(flip(obj.WOX) * 1e3);
            WOY_scaled = round(flip(obj.WOY) * 1e3);
            WOX_top_scaled = round(flip(obj.WOX_top) * 1e3);
            WOY_top_scaled = round(flip(obj.WOY_top) * 1e3);
            WIX_scaled = round(obj.WIX * 1e3);
            WIY_scaled = round(obj.WIY * 1e3);
            WIX_top_scaled = round(obj.WIX_top * 1e3);
            WIY_top_scaled = round(obj.WIY_top * 1e3);

            % 构建三维坐标
            Out_Bottom_xyz = [WOX_scaled', WOY_scaled', zeros(length(WOX_scaled), 1)];
            Out_Top_xyz = [WOX_top_scaled', WOY_top_scaled', ones(length(WOX_top_scaled), 1) * h_wg * 1e3];
            In_Bottom_xyz = [WIX_scaled', WIY_scaled', zeros(length(WIX_scaled), 1)];
            In_Top_xyz = [WIX_top_scaled', WIY_top_scaled', ones(length(WIX_top_scaled), 1) * h_wg * 1e3];

            % 组合所有顶点
            vtx = [In_Bottom_xyz; Out_Bottom_xyz; In_Top_xyz; Out_Top_xyz];
        end

        function poly2d = postohfss2d(obj)
            % 将当前波导转换为二维闭合多边形坐标（单位：μm）
            % 不考虑倾角，仅输出 [x,y] 顶点序列。
            % 默认依据 width_mode 判断使用顶部或底部轮廓；
            % 若提供 use_top，则按输入执行：true=顶部，false=底部。
            %
            % 输出:
            %   poly2d: (N x 2) 的闭合坐标，最后一点与第一点相同。

            arguments
                obj Wcli_wg
            end

            if obj.width_mode
                ox = obj.WOX_top(:); oy = obj.WOY_top(:);
                ix = obj.WIX_top(:); iy = obj.WIY_top(:);
            else
                ox = obj.WOX(:); oy = obj.WOY(:);
                ix = obj.WIX(:); iy = obj.WIY(:);
            end

            % 外沿顺序 + 内沿反向，形成闭合多边形
            poly2d = [ox, oy; flipud([ix, iy])];
            poly2d = round(poly2d * 1e3); % 转换成整数nm
            % 若未闭合，补上起点
            if ~isequal(poly2d(1, :), poly2d(end, :))
                poly2d(end + 1, :) = poly2d(1, :);
            end

        end
        %% 转换成Wcli_poly对象
        function poly_obj = to_poly(obj)
            % 将波导对象退化为Wcli_poly对象
            % 波导的外内轮廓构成闭合多边形，首尾自动成为两个端口
            % 自动合并距离小于1nm的点，并更新端口索引
            % 输出:
            %   poly_obj - Wcli_poly对象
            %
            % 示例:
            %   wg = Wcli_wg.Straight_wg_gen(100, 0, 3, 83, 0.22);
            %   poly = wg.to_poly();
            %   figure; poly.plot_polygon();

            % 构造闭合多边形坐标序列
            % 顺序: 外边界(正向) -> 内边界(反向) 形成逆时针闭合
            if obj.width_mode
                % 外边界坐标 (从起点到终点)
                outer_coords = [obj.WOX_top(:), obj.WOY_top(:)];
                % 内边界坐标 (反向: 从终点到起点)
                inner_coords = [flipud(obj.WIX_top(:)), flipud(obj.WIY_top(:))];
            else
                % 外边界坐标 (从起点到终点)
                outer_coords = [obj.WOX(:), obj.WOY(:)];
                % 内边界坐标 (反向: 从终点到起点)
                inner_coords = [flipud(obj.WIX(:)), flipud(obj.WIY(:))];
            end

            % 拼接成闭合多边形
            poly_xy = [outer_coords; inner_coords];

            % 记录原始索引
            n_outer_original = size(outer_coords, 1);
            n_total_original = size(poly_xy, 1);

            % 定义合并阈值 (1nm = 0.001μm)
            merge_threshold = 0.001;

            % 合并相邻的近距离点
            [poly_xy_merged, index_map] = merge_close_points(poly_xy, merge_threshold);

            % 更新端口边索引
            % 端口1: 多边形的最后一个点 (内边界起点) 到第一个点 (外边界起点)
            port1_idx1 = index_map(n_total_original);  % 原最后一个点的新索引
            port1_idx2 = index_map(1);                 % 原第一个点的新索引

            % 端口2: 外边界终点到内边界起点的连接边
            port2_idx1 = index_map(n_outer_original);     % 外边界终点的新索引
            port2_idx2 = index_map(n_outer_original + 1); % 内边界起点的新索引

            % 检查索引是否相同(点被合并了)
            if port1_idx1 == port1_idx2
                warning('端口1的两个端点被合并，可能导致端口定义无效');
            end
            if port2_idx1 == port2_idx2
                warning('端口2的两个端点被合并，可能导致端口定义无效');
            end

            % 组装端口边
            port_edges = [port1_idx1, port1_idx2;
                port2_idx1, port2_idx2];

            % 确保逆时针方向
            if ispolycw(poly_xy_merged(:, 1), poly_xy_merged(:, 2))
                poly_xy_merged = flipud(poly_xy_merged);
                % 翻转后需要更新索引
                n_merged = size(poly_xy_merged, 1);
                port_edges = n_merged + 1 - flip(port_edges,2);
            end

            % 创建Wcli_poly对象
            poly_obj = Wcli_poly(poly_xy_merged, obj.etch_angle, obj.thickness, port_edges);

            % 输出信息
            n_removed = n_total_original - size(poly_xy_merged, 1);
            %             fprintf('波导已转换为多边形:\n');
            %             fprintf('  原始顶点数: %d\n', n_total_original);
            %             fprintf('  合并后顶点数: %d\n', size(poly_xy_merged, 1));
            %             fprintf('  合并的点数: %d (阈值: %.3f nm)\n', n_removed, merge_threshold * 1000);
            %             fprintf('  端口1 (起始端): 顶点 [%d, %d]\n', port_edges(1, 1), port_edges(1, 2));
            %             fprintf('  端口2 (结束端): 顶点 [%d, %d]\n', port_edges(2, 1), port_edges(2, 2));
            %
            %             % 验证端口方向
            %             [~, ~, angle1] = poly_obj.get_port(1);
            %             [~, ~, angle2] = poly_obj.get_port(2);
            %             fprintf('  端口1方向: %.1f°\n', rad2deg(angle1));
            %             fprintf('  端口2方向: %.1f°\n', rad2deg(angle2));

            % 内部函数：合并相邻的近距离点
            function [coords_merged, idx_map] = merge_close_points(coords, threshold)
                % 合并距离小于阈值的相邻点
                % 输入:
                %   coords - [N×2] 坐标矩阵
                %   threshold - 合并阈值 (μm)
                % 输出:
                %   coords_merged - 合并后的坐标
                %   idx_map - 原索引到新索引的映射 [N×1]

                n = size(coords, 1);
                keep_mask = true(n, 1);  % 标记保留的点
                idx_map = zeros(n, 1);   % 索引映射

                % 检查相邻点之间的距离
                for i = 1:n-1
                    if ~keep_mask(i)
                        continue;
                    end

                    % 计算与下一个点的距离
                    dx = coords(i+1, 1) - coords(i, 1);
                    dy = coords(i+1, 2) - coords(i, 2);
                    dist = sqrt(dx^2 + dy^2);

                    % 如果距离小于阈值，标记下一个点为删除
                    if dist < threshold
                        keep_mask(i+1) = false;
                    end
                end

                % 检查首尾点（闭合多边形）
                dx = coords(1, 1) - coords(n, 1);
                dy = coords(1, 2) - coords(n, 2);
                dist = sqrt(dx^2 + dy^2);
                if dist < threshold && keep_mask(1) && keep_mask(n)
                    keep_mask(n) = false;  % 删除最后一个点，保留第一个点
                end

                % 提取保留的点
                coords_merged = coords(keep_mask, :);

                % 建立索引映射
                new_idx = 0;
                for i = 1:n
                    if keep_mask(i)
                        new_idx = new_idx + 1;
                        idx_map(i) = new_idx;
                    else
                        % 被合并的点映射到前一个保留点的索引
                        % 找到前一个保留的点
                        for j = i-1:-1:1
                            if keep_mask(j)
                                idx_map(i) = idx_map(j);
                                break;
                            end
                        end
                        % 如果前面没有保留的点（极端情况），映射到最后一个保留点
                        if idx_map(i) == 0
                            idx_map(i) = sum(keep_mask);
                        end
                    end
                end
            end
        end

    end

    %% 静态方法#################################
    methods (Static)
        %% gds生成
        function generate_multi_gds(waveguide_objs, FileDc, layers_list, cell_names, top_cell_name, lib_name, placements)
            % 将多个独立的 Wcli_wg 对象写入到同一个具有层级结构的 GDS 文件
            %
            % 输入参数:
            %   waveguide_objs - Wcli_wg 对象的元胞数组
            %   FileDc - GDS 文件路径 (字符串)
            %   layers_list - 层号列表，可以是：
            %                 1) 单个层号（所有结构使用同一层）
            %                 2) 与 waveguide_objs 长度相同的向量（每个结构对应一个层号）
            %   cell_names - 结构名称的元胞数组，长度应与 waveguide_objs 相同
            %   top_cell_name - 顶层结构名称
            %   lib_name - 可选，库名称，默认为 'MultiWaveguides'
            %   placements - 可选，放置信息结构体数组，包含以下字段：
            %               .x - X坐标 (默认为0)
            %               .y - Y坐标 (默认为0)
            %               .angle - 旋转角度，以度为单位 (默认为0)
            %               .mirror_x - 是否沿X轴镜像 (默认为false)
            %               .mirror_y - 是否沿Y轴镜像 (默认为false)
            %
            % 示例:
            %   wg1 = Wcli_wg(...);
            %   wg2 = Wcli_wg(...);
            %   placements(1) = struct('x', 0, 'y', 0, 'angle', 0, 'mirror_x', false, 'mirror_y', false);
            %   placements(2) = struct('x', 100, 'y', 50, 'angle', 90, 'mirror_x', false, 'mirror_y', false);
            %   Wcli_wg.generate_multi_gds({wg1, wg2}, 'output.gds', [1, 2], {'WG1', 'WG2'}, 'TOP_CELL', 'MyLib', placements);

            arguments
                waveguide_objs (1, :) cell % Wcli_wg 对象的元胞数组
                FileDc (1, :) char % 文件路径
                layers_list (1, :) double {mustBeInteger, mustBePositive} % 层号列表
                cell_names (1, :) cell % 结构名称的元胞数组
                top_cell_name (1, :) char % 顶层结构名称
                lib_name (1, :) char = 'MultiWaveguides' % 库名称，默认值
                placements = [] % 放置信息，可选
            end

            num_waveguides = length(waveguide_objs);

            % 验证输入参数
            if length(cell_names) ~= num_waveguides
                error('cell_names 的长度必须与 waveguide_objs 的长度相同');
            end

            % 处理层号列表
            if length(layers_list) == 1
                layers_list = repmat(layers_list, 1, num_waveguides);
            elseif length(layers_list) ~= num_waveguides
                error('layers_list 的长度必须为 1 或与 waveguide_objs 的长度相同');
            end

            % 处理放置信息
            if isempty(placements)
                % 创建默认放置信息
                default_placement = struct('x', 0, 'y', 0, 'angle', 0, 'mirror_x', false, 'mirror_y', false);
                placements = repmat(default_placement, 1, num_waveguides);
            elseif length(placements) ~= num_waveguides
                error('placements 的长度必须与 waveguide_objs 的长度相同');
            end

            % 验证所有输入都是 Wcli_wg 对象
            for i = 1:num_waveguides

                if ~isa(waveguide_objs{i}, 'Wcli_wg')
                    error('waveguide_objs{%d} 不是 Wcli_wg 对象', i);
                end

            end

            % 创建文件夹（如果不存在）
            [folder_path, ~, ~] = fileparts(FileDc);

            if ~isempty(folder_path) && ~exist(folder_path, 'dir')
                mkdir(folder_path);
            end

            % 打开文件并写入头部信息
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

                % 首先写入所有子结构
                for wg_idx = 1:num_waveguides
                    obj = waveguide_objs{wg_idx};
                    layer = layers_list(wg_idx);
                    cell_name = cell_names{wg_idx};

                    % 确保结构名称长度为偶数（GDS 格式要求）
                    if mod(length(cell_name), 2) ~= 0
                        cell_name = [cell_name 'E'];
                        cell_names{wg_idx} = cell_name; % 更新名称
                    end

                    % 写入子结构
                    Wcli_wg.write_child_structure(fid, obj, layer, cell_name);
                end

                % 写入顶层结构
                Wcli_wg.write_top_structure(fid, cell_names, top_cell_name, placements);

                % 写入库结束标记
                fprintf(fid, 'ENDLIB \r\n');

            catch ME
                fclose(fid);
                rethrow(ME);
            end

            fclose(fid);

            % 显示成功信息
            fprintf('成功创建包含 %d 个波导结构的层级 GDS 文件: %s\n', num_waveguides, FileDc);
            fprintf('顶层结构: %s\n', top_cell_name);

            for i = 1:num_waveguides
                fprintf('  子结构 %d: %s (层 %d) - 位置: (%.1f, %.1f), 角度: %.1f°\n', ...
                    i, cell_names{i}, layers_list(i), placements(i).x, placements(i).y, placements(i).angle);
            end

        end

        function generate_multi_flatten_gds(waveguide_objs, FileDc, layers_list, cell_name, lib_name, placements)
            % 将多个独立的 Wcli_wg 对象合并写入到同一个扁平化的 GDS 文件中
            % 所有结构都在同一个cell中，没有层级结构
            %
            % 输入参数:
            %   waveguide_objs - Wcli_wg 对象的元胞数组
            %   FileDc - GDS 文件路径 (字符串)
            %   layers_list - 层号列表，可以是：
            %                 1) 单个层号（所有结构使用同一层）
            %                 2) 与 waveguide_objs 长度相同的向量（每个结构对应一个层号）
            %   cell_name - 单一结构名称
            %   lib_name - 可选，库名称，默认为 'FlattenedWaveguides'
            %   placements - 可选，变换信息结构体数组，包含以下字段：
            %               .x - X坐标偏移 (默认为0)
            %               .y - Y坐标偏移 (默认为0)
            %               .angle - 旋转角度，以弧度为单位 (默认为0)
            %               .mirror_x - 是否沿X轴镜像 (默认为false)
            %               .mirror_y - 是否沿Y轴镜像 (默认为false)
            %
            % 示例:
            %   wg1 = Wcli_wg(...);
            %   wg2 = Wcli_wg(...);
            %   placements(1) = struct('x', 0, 'y', 0, 'angle', 0, 'mirror_x', false, 'mirror_y', false);
            %   placements(2) = struct('x', 100, 'y', 50, 'angle', pi/2, 'mirror_x', false, 'mirror_y', false);
            %   Wcli_wg.generate_multi_flatten_gds({wg1, wg2}, 'output.gds', [1, 2], 'FLAT_CELL', 'MyLib', placements);

            arguments
                waveguide_objs (1, :) cell % Wcli_wg 对象的元胞数组
                FileDc (1, :) char % 文件路径
                layers_list (1, :) double {mustBeInteger, mustBePositive} % 层号列表
                cell_name (1, :) char % 单一结构名称
                lib_name (1, :) char = 'FlattenedWaveguides' % 库名称，默认值
                placements = [] % 变换信息，可选
            end

            num_waveguides = length(waveguide_objs);

            % 处理层号列表
            if length(layers_list) == 1
                layers_list = repmat(layers_list, 1, num_waveguides);
            elseif length(layers_list) ~= num_waveguides
                error('layers_list 的长度必须为 1 或与 waveguide_objs 的长度相同');
            end

            % 处理变换信息
            if isempty(placements)
                % 创建默认变换信息
                default_placement = struct('x', 0, 'y', 0, 'angle', 0, 'mirror_x', false, 'mirror_y', false);
                placements = repmat(default_placement, 1, num_waveguides);
            elseif length(placements) ~= num_waveguides
                error('placements 的长度必须与 waveguide_objs 的长度相同');
            end

            % 验证所有输入都是 Wcli_wg 对象
            for i = 1:num_waveguides

                if ~isa(waveguide_objs{i}, 'Wcli_wg')
                    error('waveguide_objs{%d} 不是 Wcli_wg 对象', i);
                end

            end

            % 创建变换后的波导对象并收集所有边界数据
            all_boundary_data = {};
            all_layers = [];

            for wg_idx = 1:num_waveguides
                obj = waveguide_objs{wg_idx};
                layer = layers_list(wg_idx);
                placement = placements(wg_idx);

                % 创建对象副本进行变换
                transformed_obj = obj.copy();

                % 应用变换
                if placement.mirror_x
                    transformed_obj.mirror_translate_shape('x', 0, 0);
                end

                if placement.mirror_y
                    transformed_obj.mirror_translate_shape('y', 0, 0);
                end

                if placement.angle ~= 0
                    transformed_obj.transform_shape(placement.angle, 0, 0);
                end

                if placement.x ~= 0 || placement.y ~= 0
                    transformed_obj.transform_shape(0, placement.x, placement.y);
                end

                % 分段处理变换后的波导对象
                MAX_POINTS = 2040;
                total_points = length(transformed_obj.WOX);
                num_segments = ceil(total_points / MAX_POINTS);

                % 检查最后一段的点数，如果小于2个点就合并到前一段
                if num_segments > 1
                    last_segment_start = (num_segments - 1) * MAX_POINTS + 1;
                    last_segment_points = total_points - last_segment_start + 1;

                    if last_segment_points < 2
                        num_segments = num_segments - 1;
                    end

                end

                % 处理每个分段
                for seg_idx = 1:num_segments
                    start_idx = (seg_idx - 1) * MAX_POINTS + 1;

                    if seg_idx <= num_segments - 1
                        end_idx = seg_idx * MAX_POINTS + 2;
                    else
                        end_idx = total_points;
                    end

                    % 提取当前分段的坐标
                    if transformed_obj.width_mode
                        current_WOX = transformed_obj.WOX_top(start_idx:end_idx);
                        current_WOY = transformed_obj.WOY_top(start_idx:end_idx);
                        current_WIX = transformed_obj.WIX_top(start_idx:end_idx);
                        current_WIY = transformed_obj.WIY_top(start_idx:end_idx);
                    else
                        current_WOX = transformed_obj.WOX(start_idx:end_idx);
                        current_WOY = transformed_obj.WOY(start_idx:end_idx);
                        current_WIX = transformed_obj.WIX(start_idx:end_idx);
                        current_WIY = transformed_obj.WIY(start_idx:end_idx);
                    end

                    % 构造边界数据（外边界 + 翻转的内边界）
                    data_temp = [current_WOX, flip(current_WIX);
                        current_WOY, flip(current_WIY)]';
                    data = round(data_temp * 1e3); % 转换为整数（nm单位）

                    % 收集边界数据和对应的层号
                    all_boundary_data{end + 1} = data;
                    all_layers(end + 1) = layer;
                end

            end

            % 创建文件夹（如果不存在）
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

                % 确保结构名称长度为偶数（GDS 格式要求）
                if mod(length(cell_name), 2) ~= 0
                    cell_name = [cell_name 'E'];
                end

                % 写入结构开始标记
                fprintf(fid, 'BGNSTR 4/20/2021 12:33:18 4/20/2021 12:33:18  \r\n');
                fprintf(fid, 'STRNAME %s\r\n', cell_name);

                % 写入所有收集的边界数据
                for data_idx = 1:length(all_boundary_data)
                    data = all_boundary_data{data_idx};
                    layer = all_layers(data_idx);
                    Wcli_wg.write_boundary(fid, data, layer);
                end

                % 写入结构和库结束标记
                fprintf(fid, 'ENDSTR \r\n');
                fprintf(fid, 'ENDLIB \r\n');

            catch ME
                fclose(fid);
                rethrow(ME);
            end

            fclose(fid);

            % 显示成功信息
            fprintf('成功创建包含 %d 个波导结构的扁平化 GDS 文件: %s\n', num_waveguides, FileDc);
            fprintf('结构名称: %s\n', cell_name);
            fprintf('使用的层号: [%s]\n', num2str(unique(all_layers)));

            % 统计信息
            total_segments = length(all_boundary_data);
            fprintf('总共写入 %d 个边界段\n', total_segments);
        end

        function write_child_structure(fid, obj, layer, cell_name)
            % 写入子结构（包含实际几何数据）

            % 分段处理波导对象
            MAX_POINTS = 2040;
            total_points = length(obj.WOX);
            num_segments = ceil(total_points / MAX_POINTS);

            % 检查最后一段的点数，如果小于2个点就合并到前一段
            if num_segments > 1
                last_segment_start = (num_segments - 1) * MAX_POINTS + 1;
                last_segment_points = total_points - last_segment_start + 1;

                if last_segment_points < 2
                    num_segments = num_segments - 1;
                end

            end

            % 写入结构开始标记
            fprintf(fid, 'BGNSTR 4/20/2021 12:33:18 4/20/2021 12:33:18  \r\n');
            fprintf(fid, 'STRNAME %s\r\n', cell_name);

            % 处理每个分段
            for seg_idx = 1:num_segments
                start_idx = (seg_idx - 1) * MAX_POINTS + 1;

                if seg_idx <= num_segments - 1
                    end_idx = seg_idx * MAX_POINTS + 2;
                else
                    end_idx = total_points;
                end

                % 提取当前分段的坐标
                % 获取需要的多边形坐标（nm单位）
                if obj.width_mode
                    current_WOX = obj.WOX_top(start_idx:end_idx);
                    current_WOY = obj.WOY_top(start_idx:end_idx);
                    current_WIX = obj.WIX_top(start_idx:end_idx);
                    current_WIY = obj.WIY_top(start_idx:end_idx);
                else
                    current_WOX = obj.WOX(start_idx:end_idx);
                    current_WOY = obj.WOY(start_idx:end_idx);
                    current_WIX = obj.WIX(start_idx:end_idx);
                    current_WIY = obj.WIY(start_idx:end_idx);
                end

                % 构造边界数据（外边界 + 翻转的内边界）
                data_temp = [current_WOX, flip(current_WIX);
                    current_WOY, flip(current_WIY)]';
                data = round(data_temp * 1e3); % 转换为整数（nm单位）

                % 写入边界数据
                Wcli_wg.write_boundary(fid, data, layer);
            end

            % 写入结构结束标记
            fprintf(fid, 'ENDSTR \r\n');
        end

        function write_top_structure(fid, cell_names, top_cell_name, placements)
            % 写入顶层结构（包含对子结构的引用）

            % 确保顶层结构名称长度为偶数
            if mod(length(top_cell_name), 2) ~= 0
                top_cell_name = [top_cell_name 'E'];
            end

            % 写入顶层结构开始标记
            fprintf(fid, 'BGNSTR 4/20/2021 12:33:18 4/20/2021 12:33:18  \r\n');
            fprintf(fid, 'STRNAME %s\r\n', top_cell_name);

            % 写入对每个子结构的引用
            for i = 1:length(cell_names)
                placement = placements(i);

                % 写入 SREF 记录
                fprintf(fid, 'SREF \r\n');
                fprintf(fid, 'SNAME %s\r\n', cell_names{i});

                % 处理变换标志
                strans = Wcli_wg.calculate_strans(placement.mirror_x, placement.mirror_y);

                if strans ~= 0
                    fprintf(fid, 'STRANS %d \r\n', strans);
                end

                % 写入角度（如果不为0）
                if placement.angle ~= 0
                    fprintf(fid, 'ANGLE %g \r\n', placement.angle);
                end

                % 写入位置坐标（转换为整数，单位为nm）
                x_coord = round(placement.x * 1e3);
                y_coord = round(placement.y * 1e3);
                fprintf(fid, 'XY %d:%d\r\n', x_coord, y_coord);

                fprintf(fid, 'ENDEL \r\n');
            end

            % 写入顶层结构结束标记
            fprintf(fid, 'ENDSTR \r\n');
        end

        function strans = calculate_strans(mirror_x, mirror_y)
            % 计算 STRANS 标志位
            % STRANS 是一个 16 位整数，位定义如下：
            % 位15 (最高位): X轴镜像
            % 位14: Y轴镜像（在某些实现中）
            % 位13: 绝对角度
            % 其他位: 保留

            strans = 0;

            if mirror_x
                strans = strans + 32768; % 2^15, 设置最高位
            end

            if mirror_y
                strans = strans + 16384; % 2^14, 设置第14位
            end

        end

        %% 波导函数#######################################################
        %############################################################################################
        % 欧拉弯曲相关函数
        function kappa_L = kappa_L_polyf(R_in, R_out, L0, m, x)
            % kappa_L_polyf - 计算给定长度下的曲率
            kappa_in = 1 / R_in;
            kappa_out = 1 / R_out;
            alpha = (kappa_in - kappa_out) / L0 ^ m;
            kappa_L = alpha .* abs((L0 - x) .^ m) + kappa_out;

        end

        function L = L_theta_polyf(R_in, R_out, theta, m)
            % L_theta_polyf - 计算给定广义欧拉弯曲角度下的长度
            kappa_in = 1 / R_in;
            kappa_out = 1 / R_out;
            L = abs(theta) ./ (kappa_in / (m + 1) + kappa_out * m / (m + 1));

        end

        %############################################################################################
        % 二次弯曲相关函数，满足曲率边界条件
        % L0是长度，dkappa_in是曲率变化率，s是位置
        % dkappa_in和L0与dkappa_out满足关系 L0 = 2*(kappa_out-kappa_in)/ (dkappa_in + dkappa_out),只有2个独立分量
        function kappa_s = kappa_L_quadratic(kappa_in, kappa_out, dkappa_in, s)
            L0 = s(end); % %长度
            dkappa_out = 2 * (kappa_out - kappa_in) / L0 - dkappa_in; % %曲率变化率
            kappa_s = kappa_in + dkappa_in * s + (dkappa_out - dkappa_in) / (2 * L0) * s .^ 2; % %quadratic_taper
        end

        function theta_L = theta_L_quadratic(kappa_in, kappa_out, dkappa_in, L0)
            dkappa_out = 2 * (kappa_out - kappa_in) / L0 - dkappa_in; % %曲率变化率
            theta_L = kappa_in * L0 + (2 * dkappa_out + dkappa_in) / 6 * L0 ^ 2; % %quadratic_taper
        end

        function theta_s = theta_s_quadratic(kappa_in, kappa_out, dkappa_in, s)
            L0 = s(end); % %长度
            dkappa_out = 2 * (kappa_out - kappa_in) / L0 - dkappa_in; % %曲率变化率
            theta_s = kappa_in * s +dkappa_in / 2 * s .^ 2 + (dkappa_out - dkappa_in) / (6 * L0) * s .^ 3; % %quadratic_taper
        end

        %############################################################################################
        % 三次弯曲相关函数，满足曲率边界条件，广义TOPIC弯曲
        % L0是长度，dkappa_in是入射曲率变化率，s是位置
        % 有3个独立分量，dkappa_in,dkappa_out和L0
        function kappa_s = kappa_L_cubic(kappa_in, kappa_out, dkappa_in, dkappa_out, s)
            L = s(end); % %长度
            term1 = kappa_in;
            term2 = dkappa_in * s;
            term3 = (3 * (kappa_out - kappa_in) - (2 * dkappa_in + dkappa_out) * L) / L ^ 2 * s .^ 2;
            term4 = ((dkappa_in + dkappa_out) * L - 2 * (kappa_out - kappa_in)) / L ^ 3 * s .^ 3;
            kappa_s = term1 + term2 + term3 + term4;
        end

        function theta_s = theta_s_cubic(kappa_in, kappa_out, dkappa_in, dkappa_out, s)
            % 计算三次曲率变化的角度分布
            % 输入参数:
            %   kappa_in: 初始曲率
            %   kappa_out: 终止曲率
            %   dkappa_in: 初始曲率变化率
            %   dkappa_out: 终止曲率变化率
            %   s: 位置向量
            % 输出参数:
            %   theta_s: 对应位置的角度分布

            L = s(end); % 长度
            % 通过积分kappa_s得到theta_s
            % theta_s = ∫kappa(s)ds

            % 积分term1: kappa_in * s
            term1 = kappa_in * s;

            % 积分term2: dkappa_in * s^2 / 2
            term2 = dkappa_in * s .^ 2/2;

            % 积分term3: [(3*(kappa_out-kappa_in)-(2*dkappa_in+dkappa_out)*L)/L^2] * s^3/3
            coef3 = (3 * (kappa_out - kappa_in) - (2 * dkappa_in + dkappa_out) * L) / L ^ 2;
            term3 = coef3 * s .^ 3/3;

            % 积分term4: [(dkappa_in+dkappa_out)*L-2*(kappa_out-kappa_in)]/L^3 * s^4/4
            coef4 = ((dkappa_in + dkappa_out) * L - 2 * (kappa_out - kappa_in)) / L ^ 3;
            term4 = coef4 * s .^ 4/4;

            % 组合所有项
            theta_s = term1 + term2 + term3 + term4;
        end

        function theta_L = theta_L_cubic(kappa_in, kappa_out, dkappa_in, dkappa_out, L)
            theta_L = (kappa_in + kappa_out) / 2 * L + (dkappa_in - dkappa_out) / 12 * L ^ 2; % %cubic_taper
        end

        %#############################################################################################
        % 宽度变化函数

        function width = Linear_wid_taper(W_in, W_out, L0, x)
            width = W_in + (W_out - W_in) / L0 * x; % %linear_taper
        end

        function width = poly_wid_taper(W_in, W_out, L0, m, x)
            alpha = (W_in - W_out) / L0 ^ m;
            width = alpha .* abs((L0 - x) .^ m) + W_out;

        end

        %#############################################################################################
        % Taper波导相关函数

        function [width_list] = Taper_width_gen(Wc_in, Wc_out, m_wid, taper_list)
            % 生成渐变波导的宽度列表
            % 输入:
            %   Wc_in: 输入波导宽度
            %   Wc_out: 输出波导宽度
            %   m_wid: 渐变阶数
            %   taper_list: 长度或角度列表(要求单调增加或减少)
            % 输出:
            %   width_list: 对应的宽度列表

            arguments
                Wc_in (1, 1) double {mustBePositive} % 输入波导宽度
                Wc_out (1, 1) double {mustBePositive} % 输出波导宽度
                m_wid (1, 1) double {mustBePositive} % 渐变阶数
                taper_list (1, :) double % 长度或角度列表
            end

            % 验证taper_list是否单调
            dx = diff(taper_list);

            if ~(all(dx >= 0) || all(dx <= 0))
                error('taper_list必须是单调增加或单调减少的序列');
            end

            % 归一化处理taper_list
            t_min = min(taper_list);
            t_max = max(taper_list);
            L = t_max - t_min; % 实际长度

            % 归一化到[0, L]范围
            taper_norm = (taper_list - t_min);

            % 向量化计算宽度列表
            width_list = Wcli_wg.poly_wid_taper(Wc_in, Wc_out, L, m_wid, taper_norm);
        end
        function [width_list] = Taper_width_gen_sym(Wc_edge, Wc_mid, m_wid, taper_list)
            % 生成对称渐变波导的宽度列表
            % 输入:
            %   Wc_edge: 两端波导宽度
            %   Wc_mid: 中间波导宽度
            %   m_wid: 渐变阶数
            %   taper_list: 长度或角度列表(要求单调增加或减少)
            % 输出:
            %   width_list: 对应的宽度列表，从Wc_edge渐变到Wc_mid再对称回到Wc_edge

            arguments
                Wc_edge (1, 1) double {mustBePositive} % 两端波导宽度
                Wc_mid (1, 1) double {mustBePositive} % 中间波导宽度
                m_wid (1, 1) double {mustBePositive} % 渐变阶数
                taper_list (1, :) double % 长度或角度列表
            end

            % 验证taper_list是否单调
            dx = diff(taper_list);

            if ~(all(dx >= 0) || all(dx <= 0))
                error('taper_list必须是单调增加或单调减少的序列');
            end

            % 归一化处理taper_list
            t_min = min(taper_list);
            t_max = max(taper_list);
            L_total = t_max - t_min; % 总长度
            L_half = L_total / 2; % 半程长度

            % 归一化到[0, L_total]范围
            taper_norm = (taper_list - t_min);

            % 初始化宽度列表
            width_list = zeros(size(taper_norm));

            % 前半段：从Wc_edge渐变到Wc_mid
            mask_first_half = taper_norm <= L_half;
            width_list(mask_first_half) = Wcli_wg.poly_wid_taper(Wc_edge, Wc_mid, L_half, m_wid, taper_norm(mask_first_half));

            % 后半段：从Wc_mid渐变回Wc_edge（镜像前半段）
            mask_second_half = taper_norm > L_half;
            taper_second = taper_norm(mask_second_half) - L_half; % 重新从0开始
            width_list(mask_second_half) = Wcli_wg.poly_wid_taper(Wc_mid, Wc_edge, L_half, m_wid, taper_second);
        end

        %#############################################################################################
        % 阿基米德螺旋线相关函数

        function L = L_theta_ajmd(theta, A, B) %阿基米德螺旋线的长度和角度关系
            % A是最内弯曲半径 B  = gap/pi
            % theta是弯曲角度单位为rad
            % L是长度单位为um
            theta0 = 0; % %初始角度为0
            L = (B ^ 2 * theta + A * B) / (2 * B ^ 2) .* sqrt(B ^ 2 * theta .^ 2 + 2 * A * B * theta + A ^ 2 + B ^ 2) ...
                +B / 2 * log(abs(B * theta + A + sqrt(B ^ 2 * theta .^ 2 + 2 * A * B * theta + A ^ 2 + B ^ 2)));
            L0 = (B ^ 2 * theta0 + A * B) / (2 * B ^ 2) .* sqrt(B ^ 2 * theta0 ^ 2 + 2 * A * B * theta0 + A ^ 2 + B ^ 2) ...
                +B / 2 * log(abs(B * theta0 + A + sqrt(B ^ 2 * theta0 ^ 2 + 2 * A * B * theta0 + A ^ 2 + B ^ 2)));
            L = L - L0;
        end

        function dkds = ajmd_dkappa(a, b, theta)
            % ARCHIMEDEAN_SPIRAL_CURVATURE_RATE 计算阿基米德螺旋线的曲率变化率 dκ/ds
            %
            % 输入参数：
            %   a : 螺旋线初始半径参数
            %   b : 螺旋线每弧度增加的半径
            %   theta : 极角（弧度），可以是标量或数组
            %
            % 输出参数：
            %   dkds : 曲率变化率 dκ/ds，与 theta 同尺寸
            %
            % 公式：
            %   dκ/ds = -b*(a + bθ)*[(a + bθ)^2 + 4b^2] / [b^2 + (a + bθ)^2]^3
            r = a + b .* theta;
            numerator = -b .* r .* (r .^ 2 + 4 * b ^ 2);
            denominator = (b ^ 2 + r .^ 2) .^ 3;
            dkds = numerator ./ denominator;
        end

        function [x_Euler_list, y_Euler_list, theta_list, L_list] = Euler_trace_gen(R_max, R_min, bend_angle, mk, N_point, initial_angle)
            % 计算欧拉弯曲的轨迹
            arguments
                R_max (1, 1) double % 最大曲率半径
                R_min (1, 1) double % 最小曲率半径
                bend_angle (1, 1) double % 弯曲角度（单位rad）
                mk (1, 1) double % 阶数
                N_point (1, 1) double % 轨迹点数
                initial_angle (1, 1) double = 0 % 初始角度（可选，默认为0）
            end

            L_Euler_coup = Wcli_wg.L_theta_polyf(R_max, R_min, bend_angle, mk);
            %欧拉部分

            total_points = 200000;
            L_sbend_list_full = linspace(0, L_Euler_coup, total_points); % %长度长度均匀分布
            dL_sbend = L_sbend_list_full(2) - L_sbend_list_full(1);
            theta_list_full = zeros(1, total_points); %theta从0开始
            theta_list_full(1) = initial_angle; % 使用初始角度
            x_Euler_list_full = zeros(1, total_points); % %从原点开始
            y_Euler_list_full = zeros(1, total_points);

            for i = 2:1:total_points
                theta_list_full(i) = theta_list_full(i - 1) + Wcli_wg.kappa_L_polyf(R_max, R_min, L_Euler_coup, mk, L_sbend_list_full(i - 1)) * dL_sbend;
                x_Euler_list_full(i) = x_Euler_list_full(i - 1) + cos(theta_list_full(i)) * dL_sbend; % %cos对应x，注意文章的坐标系
                y_Euler_list_full(i) = y_Euler_list_full(i - 1) + sin(theta_list_full(i)) * dL_sbend;
            end

            % 使用插值进行降采样
            t_orig = linspace(0, 1, total_points); % 原始参数空间
            t_new = linspace(0, 1, N_point); % 目标参数空间

            % 使用三次样条插值
            x_Euler_list = interp1(t_orig, x_Euler_list_full, t_new, 'linear');
            y_Euler_list = interp1(t_orig, y_Euler_list_full, t_new, 'linear');
            theta_list = interp1(t_orig, theta_list_full, t_new, 'linear');
            L_list = interp1(t_orig, L_sbend_list_full, t_new, 'linear');
        end

        function [x_Euler_list, y_Euler_list, theta_list] = Euler_trace_gen1(R_max, R_min, bend_angle, N_point, initial_angle)
            %渐变阶数1，纯欧拉弯曲
            [x_Euler_list, y_Euler_list, theta_list] = Euler_trace_gen(R_max, R_min, bend_angle, 1, N_point, initial_angle);
        end

        function [x_trace_list, y_trace_list, theta_trace_list] = Euler_multi_trace_gen(R_list, angle_list, mk_list, N_point, initial_angle)
            % 生成多段欧拉弯曲的轨迹
            % 输入:
            %   R_list: 相邻段之间的半径列表 [R1,R2,...]
            %   angle_list: 每段弯曲的角度列表 [angle1,angle2,...]
            %   mk_list: 每段弯曲的阶数列表 [mk1,mk2,...]
            %   N_point: 每段的采样点数
            %   initial_angle: 初始角度（可选，默认为0）
            % 输出:
            %   x_trace_list: x坐标列表
            %   y_trace_list: y坐标列表
            %   theta_trace_list: 角度列表

            arguments
                R_list (1, :) double % 半径列表
                angle_list (1, :) double % 角度列表
                mk_list (1, :) double % 阶数列表，可以是标量或与angle_list等长的数组
                N_point (1, 1) double % 采样点数
                initial_angle (1, 1) double = 0 % 初始角度
            end

            % 如果mk是标量,扩展为与angle_list等长的数组
            if isscalar(mk_list)
                mk_list = repmat(mk_list, 1, length(angle_list));
            end

            % 检查输入参数长度是否匹配
            if length(R_list) ~= length(angle_list) + 1 || length(angle_list) ~= length(mk_list)
                error('输入参数长度不匹配：R_list长度应比angle_list多1，且angle_list与mk_list长度相等');
            end

            % 初始化输出数组
            segment_count = length(angle_list);
            x_trace_list = zeros(1, N_point * segment_count);
            y_trace_list = zeros(1, N_point * segment_count);
            theta_trace_list = zeros(1, N_point * segment_count);

            % 当前角度，用于跟踪累积角度
            current_angle = initial_angle;

            % 当前位置，用于跟踪累积位置
            current_x = 0;
            current_y = 0;

            % 逐段生成轨迹
            for i = 1:segment_count
                % 计算当前段的轨迹
                [x_temp, y_temp, theta_temp] = Wcli_wg.Euler_trace_gen( ...
                    R_list(i), ... % 起始半径
                    R_list(i + 1), ... % 终止半径
                    angle_list(i), ... % 弯曲角度
                    mk_list(i), ... % 阶数
                    N_point, ... % 采样点数
                    current_angle ... % 初始角度
                    );

                % 更新索引范围
                idx_range = ((i - 1) * N_point + 1):(i * N_point);

                % 存储轨迹，需要加上之前段的累积位置
                x_trace_list(idx_range) = x_temp + current_x;
                y_trace_list(idx_range) = y_temp + current_y;
                theta_trace_list(idx_range) = theta_temp;

                % 更新当前位置和角度，用于下一段
                current_x = x_trace_list(i * N_point);
                current_y = y_trace_list(i * N_point);
                current_angle = theta_trace_list(i * N_point);
            end

        end

        function [dx, dy] = Euler_get_delta(R_in, R_out, bend_angle, mk, initial_angle)
            % 计算欧拉弯曲形成的增量
            %参数验证
            arguments
                R_in (1, 1) double % 最大曲率半径
                R_out (1, 1) double % 最小曲率半径
                bend_angle (1, 1) double % 弯曲角度（单位rad）
                mk (1, 1) double % 阶数
                initial_angle (1, 1) double = 0 % 初始角度（可选，默认为0）
            end

            [x_Euler_list, y_Euler_list, ~] = Wcli_wg.Euler_trace_gen(R_in, R_out, bend_angle, mk, 2000, initial_angle);
            % 计算增量
            dx = x_Euler_list(end) - x_Euler_list(1);
            dy = y_Euler_list(end) - y_Euler_list(1);
        end

        function [dx] = Euler_get_dx(R_max, R_min, bend_angle, mk, initial_angle)
            %参数验证
            arguments
                R_max (1, 1) double % 最大曲率半径
                R_min (1, 1) double % 最小曲率半径
                bend_angle (1, 1) double % 弯曲角度（单位rad）
                mk (1, 1) double % 阶数
                initial_angle (1, 1) double = 0 % 初始角度（可选，默认为0）
            end

            [dx, ~] = Wcli_wg.Euler_get_delta(R_max, R_min, bend_angle, mk, initial_angle);
        end

        function [dy] = Euler_get_dy(R_max, R_min, bend_angle, mk, initial_angle)
            %参数验证
            arguments
                R_max (1, 1) double % 最大曲率半径
                R_min (1, 1) double % 最小曲率半径
                bend_angle (1, 1) double % 弯曲角度（单位rad）
                mk (1, 1) double % 阶数
                initial_angle (1, 1) double = 0 % 初始角度（可选，默认为0）
            end

            [~, dy] = Wcli_wg.Euler_get_delta(R_max, R_min, bend_angle, mk, initial_angle);
        end

        % ...existing code...

        function [dx, dy] = Euler_multi_get_delta(R_list, angle_list, mk_list, initial_angle)
            % 计算多段欧拉弯曲形成的总增量
            arguments
                R_list (1, :) double % 半径列表
                angle_list (1, :) double % 角度列表
                mk_list (1, :) double % 阶数列表或单个值
                initial_angle (1, 1) double = 0 % 初始角度
            end

            % 如果mk是标量,扩展为与angle_list等长的数组
            if isscalar(mk_list)
                mk_list = repmat(mk_list, 1, length(angle_list));
            end

            % 检查输入参数长度
            if length(R_list) ~= length(angle_list) + 1 || length(angle_list) ~= length(mk_list)
                error('输入参数长度不匹配：R_list长度应比angle_list多1，且angle_list与mk_list长度相等');
            end

            % 计算总位移
            dx = 0;
            dy = 0;
            initial_angle_list = initial_angle + cumsum(angle_list); % 初始角度列表
            initial_angle_list = [initial_angle, initial_angle_list]; % 添加初始角度
            % 逐段累加位移
            for i = 1:length(angle_list)
                [dx_i, dy_i] = Wcli_wg.Euler_get_delta(R_list(i), R_list(i + 1), angle_list(i), mk_list(i), initial_angle_list(i));
                dx = dx + dx_i;
                dy = dy + dy_i;

            end

        end

        function [dx] = Euler_multi_get_dx(R_list, angle_list, mk_list, initial_angle)

            arguments
                R_list (1, :) double % 半径列表
                angle_list (1, :) double % 角度列表
                mk_list (1, :) double % 阶数列表或单个值
                initial_angle (1, 1) double = 0 % 初始角度
            end

            [dx, ~] = Wcli_wg.Euler_multi_get_delta(R_list, angle_list, mk_list, initial_angle);
        end

        function [dy] = Euler_multi_get_dy(R_list, angle_list, mk_list, initial_angle)

            arguments
                R_list (1, :) double % 半径列表
                angle_list (1, :) double % 角度列表
                mk_list (1, :) double % 阶数列表或单个值
                initial_angle (1, 1) double = 0 % 初始角度
            end

            [~, dy] = Wcli_wg.Euler_multi_get_delta(R_list, angle_list, mk_list, initial_angle);
        end

        function [x_trace_list, y_trace_list, theta_list] = quadratic_trace_gen(kappa_in, kappa_out, dkappa_in, L, N_point, initial_angle)
            % 计算欧拉弯曲的轨迹
            arguments
                kappa_in (1, 1) double % 初始曲率
                kappa_out (1, 1) double % 终止曲率
                dkappa_in (1, 1) double % 初始曲率变化率
                L (1, 1) double % 弯曲总长度
                N_point (1, 1) double % 轨迹点数
                initial_angle (1, 1) double = 0 % 初始角度（可选，默认为0）
            end

            total_points = 200000;
            s_list = linspace(0, L, total_points); % %长度长度均匀分布

            theta_list_full = Wcli_wg.theta_s_quadratic(kappa_in, kappa_out, dkappa_in, s_list); %theta从0开始
            dL_sbend = s_list(2) - s_list(1);
            theta_list_full = theta_list_full + initial_angle; % 增加初始角度
            x_Euler_list_full = zeros(1, total_points); % %从原点开始
            y_Euler_list_full = zeros(1, total_points);

            for i = 2:1:total_points
                x_Euler_list_full(i) = x_Euler_list_full(i - 1) + cos(theta_list_full(i)) * dL_sbend; % %cos对应x，注意文章的坐标系
                y_Euler_list_full(i) = y_Euler_list_full(i - 1) + sin(theta_list_full(i)) * dL_sbend;
            end

            % 使用插值进行降采样
            t_orig = linspace(0, 1, total_points); % 原始参数空间
            t_new = linspace(0, 1, N_point); % 目标参数空间

            % 使用三次样条插值
            x_trace_list = interp1(t_orig, x_Euler_list_full, t_new, 'linear');
            y_trace_list = interp1(t_orig, y_Euler_list_full, t_new, 'linear');
            theta_list = interp1(t_orig, theta_list_full, t_new, 'linear');
        end

        function delta_xy = quadratic_get_delta(kappa_in, kappa_out, dkappa_in, L, initial_angle)
            % 计算二次曲率变化形成的增量
            arguments
                kappa_in (1, 1) double % 初始曲率
                kappa_out (1, 1) double % 终止曲率
                dkappa_in (1, 1) double % 初始曲率变化率
                L (1, 1) double % 总长度
                initial_angle (1, 1) double = 0 % 初始角度（可选，默认为0）
            end

            [x_trace_list, y_trace_list, ~] = Wcli_wg.quadratic_trace_gen(kappa_in, kappa_out, dkappa_in, L, 2000, initial_angle);
            % 计算增量
            dx = x_trace_list(end) - x_trace_list(1);
            dy = y_trace_list(end) - y_trace_list(1);
            delta_xy = [dx, dy]; % 返回增量
        end

        function [dx] = quadratic_get_dx(kappa_in, kappa_out, dkappa_in, L, initial_angle)
            % 计算二次曲率变化形成的x方向增量
            arguments
                kappa_in (1, 1) double % 初始曲率
                kappa_out (1, 1) double % 终止曲率
                dkappa_in (1, 1) double % 初始曲率变化率
                L (1, 1) double % 总长度
                initial_angle (1, 1) double = 0 % 初始角度（可选，默认为0）
            end

            delta_xy = Wcli_wg.quadratic_get_delta(kappa_in, kappa_out, dkappa_in, L, initial_angle);
            dx = delta_xy(1); % 提取x方向增量
        end

        function [dy] = quadratic_get_dy(kappa_in, kappa_out, dkappa_in, L, initial_angle)
            % 计算二次曲率变化形成的y方向增量
            arguments
                kappa_in (1, 1) double % 初始曲率
                kappa_out (1, 1) double % 终止曲率
                dkappa_in (1, 1) double % 初始曲率变化率
                L (1, 1) double % 总长度
                initial_angle (1, 1) double = 0 % 初始角度（可选，默认为0）
            end

            delta_xy = Wcli_wg.quadratic_get_delta(kappa_in, kappa_out, dkappa_in, L, initial_angle);
            dy = delta_xy(2); % 提取y方向增量
        end

        function [x_trace_list, y_trace_list, theta_list] = cubic_trace_gen(kappa_in, kappa_out, dkappa_in, dkappa_out, L, N_point, initial_angle)
            % 计算三次曲率变化的轨迹
            arguments
                kappa_in (1, 1) double % 初始曲率
                kappa_out (1, 1) double % 终止曲率
                dkappa_in (1, 1) double % 初始曲率变化率
                dkappa_out (1, 1) double % 终止曲率变化率
                L (1, 1) double % 弯曲总长度
                N_point (1, 1) double % 轨迹点数
                initial_angle (1, 1) double = 0 % 初始角度（可选，默认为0）
            end

            total_points = 200000;
            s_list = linspace(0, L, total_points); % 长度均匀分布

            theta_list_full = Wcli_wg.theta_s_cubic(kappa_in, kappa_out, dkappa_in, dkappa_out, s_list); % theta从0开始
            dL_sbend = s_list(2) - s_list(1);
            theta_list_full = theta_list_full + initial_angle; % 增加初始角度
            x_Euler_list_full = zeros(1, total_points); % 从原点开始
            y_Euler_list_full = zeros(1, total_points);

            % 通过积分得到轨迹
            for i = 2:1:total_points
                x_Euler_list_full(i) = x_Euler_list_full(i - 1) + cos(theta_list_full(i)) * dL_sbend; % cos对应x，注意文章的坐标系
                y_Euler_list_full(i) = y_Euler_list_full(i - 1) + sin(theta_list_full(i)) * dL_sbend;
            end

            % 使用插值进行降采样
            t_orig = linspace(0, 1, total_points); % 原始参数空间
            t_new = linspace(0, 1, N_point); % 目标参数空间

            % 使用线性插值
            x_trace_list = interp1(t_orig, x_Euler_list_full, t_new, 'linear');
            y_trace_list = interp1(t_orig, y_Euler_list_full, t_new, 'linear');
            theta_list = interp1(t_orig, theta_list_full, t_new, 'linear');
        end

        function delta_xy = cubic_get_delta(kappa_in, kappa_out, dkappa_in, dkappa_out, L, initial_angle)
            % 计算三次曲率变化形成的增量
            arguments
                kappa_in (1, 1) double % 初始曲率
                kappa_out (1, 1) double % 终止曲率
                dkappa_in (1, 1) double % 初始曲率变化率
                dkappa_out (1, 1) double % 终止曲率变化率
                L (1, 1) double % 总长度
                initial_angle (1, 1) double = 0 % 初始角度（可选，默认为0）
            end

            [x_trace_list, y_trace_list, ~] = Wcli_wg.cubic_trace_gen(kappa_in, kappa_out, dkappa_in, dkappa_out, L, 3e3 + 1, initial_angle);
            % 计算增量
            dx = x_trace_list(end) - x_trace_list(1);
            dy = y_trace_list(end) - y_trace_list(1);
            delta_xy = [dx, dy]; % 返回增量
        end

        function [dx] = cubic_get_dx(kappa_in, kappa_out, dkappa_in, dkappa_out, L, initial_angle)
            % 计算三次曲率变化形成的x方向增量
            arguments
                kappa_in (1, 1) double % 初始曲率
                kappa_out (1, 1) double % 终止曲率
                dkappa_in (1, 1) double % 初始曲率变化率
                dkappa_out (1, 1) double % 终止曲率变化率
                L (1, 1) double % 总长度
                initial_angle (1, 1) double = 0 % 初始角度（可选，默认为0）
            end

            delta_xy = Wcli_wg.cubic_get_delta(kappa_in, kappa_out, dkappa_in, dkappa_out, L, initial_angle);
            dx = delta_xy(1); % 提取x方向增量
        end

        function [dy] = cubic_get_dy(kappa_in, kappa_out, dkappa_in, dkappa_out, L, initial_angle)
            % 计算三次曲率变化形成的y方向增量
            arguments
                kappa_in (1, 1) double % 初始曲率
                kappa_out (1, 1) double % 终止曲率
                dkappa_in (1, 1) double % 初始曲率变化率
                dkappa_out (1, 1) double % 终止曲率变化率
                L (1, 1) double % 总长度
                initial_angle (1, 1) double = 0 % 初始角度（可选，默认为0）
            end

            delta_xy = Wcli_wg.cubic_get_delta(kappa_in, kappa_out, dkappa_in, dkappa_out, L, initial_angle);
            dy = delta_xy(2); % 提取y方向增量
        end
        %% 欧拉波导对象
        %         function
        function [Euler_bend_handle, R_out] = find_Euler_bend_Rout_dx(R_in, bend_angle, initial_angle, dx, N_point, Wid_in, Wid_out, etch_angle, h_wg)
            mk = 1;
            R_out = fzero(@(R_out) Wcli_wg.Euler_get_dx(R_in, R_out, bend_angle, mk, initial_angle) - dx, dx / bend_angle * 2);
            [x_Euler_list_1, y_Euler_list_1, theta_list_1, L_list_1] = Wcli_wg.Euler_trace_gen(R_in, R_out, bend_angle, mk, N_point, initial_angle);
            m_wid = 1;
            %默认用L_list作为taper
            width_list_1 = Wcli_wg.Taper_width_gen(Wid_in, Wid_out, m_wid, L_list_1);
            Euler_bend_handle = Wcli_wg(x_Euler_list_1, y_Euler_list_1, theta_list_1, width_list_1, etch_angle, h_wg);
        end

        function [Euler_90_bend, R_min_calculated] = Euler_90_bend_sym_Rmid_dxy(R_max, target_displacement, N_point, Wid_in, Wid_out, etch_angle, h_wg, initial_angle)
            % 生成90度欧拉弯曲波导，由两个对称的45度欧拉弯曲组成
            % 输入参数:
            %   R_max - 最大弯曲半径,也是输入输出半径
            %   target_displacement - 目标位移 (dx或dy，因为90度弯曲dx=dy)
            %   N_point - 每段的生成点数
            %   Wid_in - 输入波导宽度
            %   Wid_out - 输出波导宽度
            %   etch_angle - 刻蚀角度
            %   h_wg - 波导高度
            %   initial_angle - 初始角度（可选，默认为0）
            % 输出:
            %   Euler_90_bend - 生成的90度弯曲波导对象
            %   R_min_calculated - 计算得到的最小弯曲半径

            arguments
                R_max (1, 1) double {mustBePositive} = 2000 % 最大弯曲半径
                target_displacement (1, 1) double {mustBePositive} = 500 % 目标位移
                N_point (1, 1) double {mustBePositive} = 501 % 生成点数
                Wid_in (1, 1) double {mustBePositive} = 1 % 输入波导宽度
                Wid_out (1, 1) double {mustBePositive} = 3 % 输出波导宽度
                etch_angle (1, 1) double = 83 % 刻蚀角度
                h_wg (1, 1) double {mustBePositive} = 0.22 % 波导高度
                initial_angle (1, 1) double = 0 % 初始角度（默认为0）
            end

            % 45度弯曲角度
            bend_45_deg = pi / 4; % 45度 = π/4 弧度

            % 计算中间宽度（用于两段之间的连接）
            Wid_mid = (Wid_in + Wid_out) / 2;

            mk = 1;
            options = optimset( ...
                'Display', 'iter', ... % 显示迭代过程
                'TolX', 1e-12, ... % x的容差（相当于fsolve的FunctionTolerance）
                'MaxIter', 1000, ... % 最大迭代次数
                'MaxFunEvals', 2000 ... % 最大函数求值次数
                );
            R_min_calculated = fzero(@(R_min_calculated) Wcli_wg.Euler_get_dx(R_max, R_min_calculated, bend_45_deg, mk, initial_angle) ...
                +Wcli_wg.Euler_get_dy(R_max, R_min_calculated, bend_45_deg, mk, initial_angle) - target_displacement, ...
                target_displacement / bend_45_deg * 2, options);

            % 生成第1个45度弯曲（对称的）
            Euler_bend_1 = Wcli_wg.Euler_wg_gen( ...
                R_max, ... % 最小半径（第二段的起始半径）
                R_min_calculated, ... % 最大半径（第二段的结束半径）
                bend_45_deg, ... % 45度弯曲角度
                initial_angle, ... % 初始角度加上第一段的角度
                N_point, ... % 点数
                Wid_in, ... % 中间宽度
                Wid_mid, ... % 输出宽度
                etch_angle, ... % 刻蚀角度
                h_wg ... % 波导高度
                );
            % 生成第2个45度弯曲（对称的）
            Euler_bend_2 = Euler_bend_1.copy(); % 创建第一段的副本
            Euler_bend_2.mirror_translate_shape('y');
            width_list = Wcli_wg.Taper_width_gen(Wid_mid, Wid_out, mk, Euler_bend_2.L_list);
            Euler_bend_2.set_width_list(width_list); % 设置宽度列表
            Euler_bend_2.transform_shape(bend_45_deg * 2);

            % 生成第二个45度弯曲（对称的）

            % 拼接两个45度弯曲成为完整的90度弯曲
            % 第二段的第一个点与第一段的最后一个点重合，所以要移除第二段的第一个点
            Euler_90_bend = Euler_bend_1.copy(); % 创建第一段的副本
            Euler_90_bend.merge_and_translate(0, 0, 1, Euler_bend_2); % 拼接第二段

            % 验证结果：检查最终的dx和dy是否接近目标值
            final_dx = Euler_90_bend.WTX(end) - Euler_90_bend.WTX(1);
            final_dy = Euler_90_bend.WTY(end) - Euler_90_bend.WTY(1);

            % 可选：显示验证信息
            if nargout == 0 % 如果没有输出参数，显示信息
                fprintf('90度欧拉弯曲生成完成:\n');
                fprintf('  计算的最小半径: %.3f μm\n', R_min_calculated);
                fprintf('  目标位移: %.3f μm\n', target_displacement);
                fprintf('  实际dx: %.3f μm\n', final_dx);
                fprintf('  实际dy: %.3f μm\n', final_dy);
                fprintf('  dx误差: %.6f μm\n', abs(final_dx - target_displacement));
                fprintf('  dy误差: %.6f μm\n', abs(final_dy - target_displacement));
                figure(11);
                Euler_90_bend.plot_wg_pos;
                figure(12);
                %                 Euler_90_bend.plot_R_all;
                Euler_90_bend.plot_kappa_all;
                figure(13);
                Euler_90_bend.plot_theta_all;
            end

        end

        function symmetric_bend = Euler_sym_bend_gen(R_max, R_min, total_angle, N_point, Wid_in, Wid_out, etch_angle, h_wg, initial_angle)
            % 生成任意角度的对称欧拉弯曲波导
            % 输入参数:
            %   R_max - 最大弯曲半径
            %   R_min - 最小弯曲半径
            %   total_angle - 总弯曲角度 (弧度)
            %   N_point - 每段的生成点数
            %   Wid_in - 输入波导宽度
            %   Wid_out - 输出波导宽度
            %   etch_angle - 刻蚀角度
            %   h_wg - 波导高度
            %   initial_angle - 初始角度（可选，默认为0）
            % 输出:
            %   symmetric_bend - 生成的对称弯曲波导对象

            arguments
                R_max (1, 1) double {mustBePositive} = 20000 % 最大弯曲半径
                R_min (1, 1) double {mustBePositive} = 200 % 最小弯曲半径
                total_angle (1, 1) double {mustBePositive} = pi / 2 % 总弯曲角度
                N_point (1, 1) double {mustBePositive} = 501 % 生成点数
                Wid_in (1, 1) double {mustBePositive} = 2.8 % 输入波导宽度
                Wid_out (1, 1) double {mustBePositive} = 2.8 % 输出波导宽度
                etch_angle (1, 1) double = 83 % 刻蚀角度
                h_wg (1, 1) double {mustBePositive} = 0.22 % 波导高度
                initial_angle (1, 1) double = 0 % 初始角度（默认为0）
            end

            % 计算每段的弯曲角度（总角度的一半）
            half_angle = total_angle / 2;

            % 计算中间宽度
            Wid_mid = (Wid_in + Wid_out) / 2;
            mk = 1;

            % 生成第1段弯曲（R_max → R_min，角度为 +half_angle）
            Euler_bend_1 = Wcli_wg.Euler_wg_gen( ...
                R_max, ... % 起始半径（最大）
                R_min, ... % 结束半径（最小）
                half_angle, ... % 弯曲角度（半角）
                initial_angle, ... % 初始角度
                N_point, ... % 点数
                Wid_in, ... % 输入宽度
                Wid_mid, ... % 中间宽度
                etch_angle, ... % 刻蚀角度
                h_wg ... % 波导高度
                );

            % 生成第1段的镜像复制（用于创建对称的第2段）
            Euler_bend_1_half = Euler_bend_1.copy();

            % 对第2段进行镜像变换和旋转变换
            Euler_bend_1_half.mirror_translate_shape('y'); % 沿y轴镜像
            Euler_bend_1_half.transform_shape(total_angle); % 旋转总角度

            % 拼接两段形成完整的对称弯曲
            symmetric_bend = Euler_bend_1.copy();
            symmetric_bend.merge_and_translate(0, 0, 1, Euler_bend_1_half);

            % 设置第2段的宽度渐变（从中间宽度到输出宽度）
            width_list_2 = Wcli_wg.Taper_width_gen(Wid_in, Wid_out, mk, symmetric_bend.L_list);
            symmetric_bend.set_width_list(width_list_2);

            % 验证结果
            final_dx = symmetric_bend.WTX(end) - symmetric_bend.WTX(1);
            final_dy = symmetric_bend.WTY(end) - symmetric_bend.WTY(1);
            final_theta = symmetric_bend.theta_list(end) - symmetric_bend.theta_list(1);

            % 可选：显示验证信息
            if nargout == 0
                fprintf('对称欧拉弯曲生成完成:\n');
                fprintf('  总弯曲角度: %.1f°\n', rad2deg(total_angle));
                fprintf('  每段角度: %.1f°\n', rad2deg(half_angle));
                fprintf('  最大半径: %.1f μm\n', R_max);
                fprintf('  最小半径: %.1f μm\n', R_min);
                fprintf('  实际dx: %.3f μm\n', final_dx);
                fprintf('  实际dy: %.3f μm\n', final_dy);
                fprintf('  实际总角度: %.3f° (目标: %.1f°)\n', rad2deg(final_theta), rad2deg(total_angle));
                fprintf('  角度误差: %.6f°\n', rad2deg(abs(final_theta - total_angle)));

                % 绘制结果
                close all;
                figure;
                symmetric_bend.plot_wg_pos;
                title(sprintf('对称欧拉弯曲 (%.1f°) - 位置轨迹', rad2deg(total_angle)));
                axis equal;

                figure;
                symmetric_bend.plot_R_all;
                title('对称欧拉弯曲 - 曲率半径');

                figure;
                symmetric_bend.plot_kappa_all;
                title('对称欧拉弯曲 - 曲率分布');

                figure;
                symmetric_bend.plot_theta_all;
                title('对称欧拉弯曲 - 角度分布');
            end

        end

        function euler_arc_bend = Euler_Arc_bend_gen( ...
                R_max, ... % 最大弯曲半径（欧拉段起始半径）
                R_arc, ... % 圆弧段半径
                total_angle, ... % 总弯曲角度 (弧度)
                Euler_angle, ... % 欧拉段角度 (弧度)，范围(0, total_angle)
                N_point, ... % 每段的生成点数
                Wid_in, ... % 输入波导宽度
                Wid_out, ... % 输出波导宽度
                etch_angle, ... % 刻蚀角度
                h_wg, ... % 波导高度
                initial_angle ... % 初始角度
                )
            % 生成欧拉-圆弧组合弯曲波导
            % 结构：欧拉段1 + 圆弧段 + 欧拉段2
            % 输入参数:
            %   R_max - 最大弯曲半径（欧拉段起始半径）
            %   R_arc - 圆弧段半径
            %   total_angle - 总弯曲角度 (弧度)
            %   Euler_angle - 欧拉段角度 (弧度)，范围(0, total_angle)
            %   N_point - 每段的生成点数
            %   Wid_in - 输入波导宽度
            %   Wid_out - 输出波导宽度
            %   etch_angle - 刻蚀角度
            %   h_wg - 波导高度
            %   initial_angle - 初始角度（可选，默认为0）
            % 输出:
            %   euler_arc_bend - 生成的组合弯曲波导对象

            arguments
                R_max (1, 1) double {mustBePositive} = 2000 % 最大弯曲半径
                R_arc (1, 1) double {mustBePositive} = 200 % 圆弧段半径
                total_angle (1, 1) double {mustBePositive} = pi / 2 % 总弯曲角度
                Euler_angle (1, 1) double {mustBePositive} = pi / 6 % 欧拉段角度
                N_point (1, 1) double {mustBePositive} = 501 % 每段生成点数
                Wid_in (1, 1) double {mustBePositive} = 2.8 % 输入波导宽度
                Wid_out (1, 1) double {mustBePositive} = 2.8 % 输出波导宽度
                etch_angle (1, 1) double = 83 % 刻蚀角度
                h_wg (1, 1) double {mustBePositive} = 0.22 % 波导高度
                initial_angle (1, 1) double = 0 % 初始角度（默认为0）
            end

            % 参数验证
            if Euler_angle >= total_angle
                error('Euler_angle必须小于total_angle');
            end

            if Euler_angle <= 0
                error('Euler_angle必须大于0');
            end

            % 计算各段角度
            euler_angle_1 = Euler_angle / 2; % 第一个欧拉段角度
            arc_angle = total_angle - Euler_angle; % 圆弧段角度

            % 计算中间宽度
            Wid_mid = Wid_in + (Wid_out - Wid_in) / 2; % 第一个过渡宽度

            mk = 1; % 欧拉弯曲阶数

            % 生成第1段欧拉弯曲（R_max → R_arc）
            Euler_bend_1 = Wcli_wg.Euler_wg_gen( ...
                R_max, ... % 起始半径（最大）
                R_arc, ... % 结束半径（圆弧半径）
                euler_angle_1, ... % 弯曲角度
                0, ... % 初始角度
                N_point, ... % 点数
                Wid_in, ... % 输入宽度
                Wid_mid, ... % 中间宽度1
                etch_angle, ... % 刻蚀角度
                h_wg ... % 波导高度
                );

            % 获取第一段的结束角度和位置
            end_angle_1 = Euler_bend_1.theta_list(end);

            % 生成圆弧段
            Arc_bend = Wcli_wg.Arc_wg_gen( ...
                R_arc, ... % 圆弧半径
                arc_angle, ... % 圆弧角度
                end_angle_1, ... % 起始角度（与第一段结束角度相同）
                N_point, ... % 点数
                Wid_mid, ... % 输入宽度
                Wid_mid, ... % 输出宽度
                etch_angle, ... % 刻蚀角度
                h_wg ... % 波导高度
                );
            euler_arc_bend_1 = Euler_bend_1.copy();
            %             euler_arc_bend_1.merge_and_translate(0, 0, 1, Arc_bend); % 拼接第一段欧拉弯曲和圆弧段
            euler_arc_bend_2 = euler_arc_bend_1.copy(); % 创建第一段的副本
            euler_arc_bend_2.mirror_translate_shape('y'); % 沿y轴镜像
            euler_arc_bend_2.transform_shape(total_angle); % 旋转到第二段的结束角度

            euler_arc_bend = euler_arc_bend_1.copy(); % 创建第一段的副本
            euler_arc_bend.merge_and_translate(0, 0, 1, Arc_bend,euler_arc_bend_2); % 拼接第二段欧拉弯曲
            euler_arc_bend.transform_shape(initial_angle); % 应用初始角度

            % 验证结果
            final_dx = euler_arc_bend.WTX(end) - euler_arc_bend.WTX(1);
            final_dy = euler_arc_bend.WTY(end) - euler_arc_bend.WTY(1);
            final_theta = euler_arc_bend.theta_list(end) - euler_arc_bend.theta_list(1);

            % 可选：显示验证信息
            if nargout == 0
                fprintf('欧拉-圆弧组合弯曲生成完成:\n');
                fprintf('  总弯曲角度: %.1f°\n', rad2deg(total_angle));
                fprintf('  欧拉段角度: %.1f°\n', rad2deg(Euler_angle));
                fprintf('  圆弧段角度: %.1f°\n', rad2deg(arc_angle));
                fprintf('  最大半径: %.1f μm\n', R_max);
                fprintf('  圆弧半径: %.1f μm\n', R_arc);
                fprintf('  实际dx: %.3f μm\n', final_dx);
                fprintf('  实际dy: %.3f μm\n', final_dy);
                fprintf('  实际总角度: %.3f° (目标: %.1f°)\n', rad2deg(final_theta), rad2deg(total_angle));
                fprintf('  角度误差: %.6f°\n', rad2deg(abs(final_theta - total_angle)));

                % 绘制结果
                close all;
                figure;
                euler_arc_bend.plot_wg_pos;
                title(sprintf('欧拉-圆弧组合弯曲 (%.1f°) - 位置轨迹', rad2deg(total_angle)));
                axis equal;

                figure;
                euler_arc_bend.plot_R_all;
                title('欧拉-圆弧组合弯曲 - 曲率半径');

                figure;
                euler_arc_bend.plot_kappa_all;
                title('欧拉-圆弧组合弯曲 - 曲率分布');

                figure;
                euler_arc_bend.plot_theta_all;
                title('欧拉-圆弧组合弯曲 - 角度分布');
            end

        end

        function Euler_arc_90_bend = Euler_arc_bend_90( ...
                R_max, ... % 最大弯曲半径（欧拉段起始半径）
                R_arc, ... % 圆弧段半径
                Euler_angle, ... % 欧拉段角度 (弧度)，范围(0, π/2)
                N_point, ... % 每段的生成点数
                Wid_in, ... % 输入波导宽度
                Wid_out, ... % 输出波导宽度
                etch_angle, ... % 刻蚀角度
                h_wg, ... % 波导高度
                initial_angle ... % 初始角度
                )
            % 生成90度欧拉-圆弧组合弯曲波导（对Euler_Arc_bend_gen的包装）
            % 输入参数:
            %   R_max - 最大弯曲半径（欧拉段起始半径）
            %   R_arc - 圆弧段半径
            %   Euler_angle - 欧拉段角度 (弧度)，范围(0, π/2)
            %   N_point - 每段的生成点数
            %   Wid_in - 输入波导宽度
            %   Wid_out - 输出波导宽度
            %   etch_angle - 刻蚀角度
            %   h_wg - 波导高度
            %   initial_angle - 初始角度（可选，默认为0）
            % 输出:
            %   Euler_arc_90_bend - 生成的90度组合弯曲波导对象

            arguments
                R_max (1, 1) double {mustBePositive} = 2000 % 最大弯曲半径
                R_arc (1, 1) double {mustBePositive} = 200 % 圆弧段半径
                Euler_angle (1, 1) double {mustBePositive} = pi / 6 % 欧拉段角度
                N_point (1, 1) double {mustBePositive} = 501 % 每段生成点数
                Wid_in (1, 1) double {mustBePositive} = 2.8 % 输入波导宽度
                Wid_out (1, 1) double {mustBePositive} = 2.8 % 输出波导宽度
                etch_angle (1, 1) double = 83 % 刻蚀角度
                h_wg (1, 1) double {mustBePositive} = 0.22 % 波导高度
                initial_angle (1, 1) double = 0 % 初始角度（默认为0）
            end

            % 直接调用现有的 Euler_Arc_bend_gen 函数，固定总角度为90度
            Euler_arc_90_bend = Wcli_wg.Euler_Arc_bend_gen( ...
                R_max, ... % 最大弯曲半径
                R_arc, ... % 圆弧段半径
                pi / 2, ... % 总弯曲角度（固定为90度）
                Euler_angle, ... % 欧拉段角度
                N_point, ... % 每段的生成点数
                Wid_in, ... % 输入波导宽度
                Wid_out, ... % 输出波导宽度
                etch_angle, ... % 刻蚀角度
                h_wg, ... % 波导高度
                initial_angle ... % 初始角度
                );
        end

        function [euler_arc_bend, R_arc_calculated] = Euler_arc_bend_Rmid_dy( ...
                R_max, ... % 最大弯曲半径（欧拉段起始半径）
                target_dy, ... % 目标侧向位移 (dy)
                total_angle, ... % 总弯曲角度 (弧度)
                Euler_angle, ... % 欧拉段角度 (弧度)，范围(0, total_angle)
                N_point, ... % 每段的生成点数
                Wid_in, ... % 输入波导宽度
                Wid_out, ... % 输出波导宽度
                etch_angle, ... % 刻蚀角度
                h_wg, ... % 波导高度
                initial_angle ... % 初始角度
                )
            % 通过优化圆弧半径满足侧向位移要求的欧拉-圆弧组合弯曲
            % 输入参数:
            %   R_max - 最大弯曲半径（欧拉段起始半径）
            %   target_dy - 目标侧向位移 (dy)
            %   total_angle - 总弯曲角度 (弧度)
            %   Euler_angle - 欧拉段角度 (弧度)，范围(0, total_angle)
            %   N_point - 每段的生成点数
            %   Wid_in - 输入波导宽度
            %   Wid_out - 输出波导宽度
            %   etch_angle - 刻蚀角度
            %   h_wg - 波导高度
            %   initial_angle - 初始角度
            % 输出:
            %   euler_arc_bend - 生成的组合弯曲波导对象
            %   R_arc_calculated - 计算得到的圆弧半径

            arguments
                R_max (1, 1) double {mustBePositive} = 2000 % 最大弯曲半径
                target_dy (1, 1) double {mustBePositive} = 150 % 目标侧向位移
                total_angle (1, 1) double {mustBePositive} = pi / 2 * 3 % 总弯曲角度
                Euler_angle (1, 1) double {mustBePositive} = pi / 6 % 欧拉段角度
                N_point (1, 1) double {mustBePositive} = 501 % 每段生成点数
                Wid_in (1, 1) double {mustBePositive} = 2.8 % 输入波导宽度
                Wid_out (1, 1) double {mustBePositive} = 2.8 % 输出波导宽度
                etch_angle (1, 1) double = 83 % 刻蚀角度
                h_wg (1, 1) double {mustBePositive} = 0.22 % 波导高度
                initial_angle (1, 1) double = 0 % 初始角度（默认为0）
            end

            % 参数验证
            if Euler_angle >= total_angle
                error('Euler_angle必须小于total_angle');
            end

            if Euler_angle <= 0
                error('Euler_angle必须大于0');
            end

            % 设置fzero选项
            options = optimset( ...
                'Display', 'off', ...
                'TolX', 1e-12, ...
                'MaxIter', 1000, ...
                'MaxFunEvals', 2000 ...
                );

            % 使用fzero求解R_arc，使得欧拉-圆弧组合弯曲的dy等于目标位移
            R_arc_calculated = fzero(@(R_arc) calculate_bend_dy(R_arc) - target_dy, ...
                target_dy * 2, options);

            % 生成最终的欧拉-圆弧组合弯曲
            euler_arc_bend = Wcli_wg.Euler_Arc_bend_gen( ...
                R_max, ... % 最大弯曲半径
                R_arc_calculated, ... % 计算得到的圆弧半径
                total_angle, ... % 总弯曲角度
                Euler_angle, ... % 欧拉段角度
                N_point, ... % 每段的生成点数
                Wid_in, ... % 输入波导宽度
                Wid_out, ... % 输出波导宽度
                etch_angle, ... % 刻蚀角度
                h_wg, ... % 波导高度
                initial_angle ... % 初始角度
                );

            % 验证结果
            final_dx = euler_arc_bend.WTX(end) - euler_arc_bend.WTX(1);
            final_dy = euler_arc_bend.WTY(end) - euler_arc_bend.WTY(1);
            final_theta = euler_arc_bend.theta_list(end) - euler_arc_bend.theta_list(1);

            % 显示验证信息
            if nargout == 0
                fprintf('欧拉-圆弧组合弯曲生成完成 (优化dy):\n');
                fprintf('  计算的圆弧半径: %.3f μm\n', R_arc_calculated);
                fprintf('  欧拉段角度: %.1f°\n', rad2deg(Euler_angle));
                fprintf('  总弯曲角度: %.1f°\n', rad2deg(total_angle));
                fprintf('  目标dy: %.3f μm\n', target_dy);
                fprintf('  实际dx: %.3f μm\n', final_dx);
                fprintf('  实际dy: %.3f μm\n', final_dy);
                fprintf('  实际总角度: %.3f° (目标: %.1f°)\n', rad2deg(final_theta), rad2deg(total_angle));
                fprintf('  dy误差: %.6f μm\n', abs(final_dy - target_dy));
                fprintf('  角度误差: %.6f°\n', rad2deg(abs(final_theta - total_angle)));

                % 绘制结果
                close all;
                figure(61);
                euler_arc_bend.plot_wg_pos;
                title(sprintf('欧拉-圆弧组合弯曲 (优化dy=%.1fμm)', target_dy));
                axis equal;
                grid on;

                figure(62);
                euler_arc_bend.plot_R_all;
                title('欧拉-圆弧组合弯曲 - 曲率半径');

                figure(63);
                euler_arc_bend.plot_kappa_all;
                title('欧拉-圆弧组合弯曲 - 曲率');

                figure(64);
                euler_arc_bend.plot_theta_all;
                title('欧拉-圆弧组合弯曲 - 角度分布');

                figure(65);
                euler_arc_bend.plot_width_all;
                title('欧拉-圆弧组合弯曲 - 宽度分布');
            end

            % 内部函数：计算弯曲的dy
            function dy = calculate_bend_dy(R_arc)

                try
                    % 生成临时的欧拉-圆弧组合弯曲来计算dy
                    temp_bend = Wcli_wg.Euler_Arc_bend_gen( ...
                        R_max, R_arc, total_angle, Euler_angle, N_point, ...
                        Wid_in, Wid_in, etch_angle, h_wg, initial_angle);

                    % 计算dy
                    dy = temp_bend.WTY(end) - temp_bend.WTY(1);
                catch
                    dy = 1e6; % 如果计算失败，返回很大的值
                end

            end

        end

        function arc_bend = Arc_wg_gen( ...
                R_arc, ... % 圆弧半径
                arc_angle, ... % 圆弧角度
                initial_angle, ... % 初始角度
                N_point, ... % 生成点数
                Wid_in, ... % 输入宽度
                Wid_out, ... % 输出宽度
                etch_angle, ... % 刻蚀角度
                h_wg ... % 波导高度
                )
            % 生成圆弧波导段
            % 输入参数:
            %   R_arc - 圆弧半径
            %   arc_angle - 圆弧角度 (弧度)
            %   initial_angle - 初始角度 (弧度)
            %   N_point - 生成点数
            %   Wid_in - 输入宽度
            %   Wid_out - 输出宽度
            %   etch_angle - 刻蚀角度
            %   h_wg - 波导高度
            % 输出:
            %   arc_bend - 生成的圆弧波导对象

            arguments
                R_arc (1, 1) double {mustBePositive} = 200 % 圆弧半径，必须为正数
                arc_angle (1, 1) double = pi/2 % 圆弧角度（弧度），默认90度
                initial_angle (1, 1) double = 0 % 初始角度（弧度），默认0
                N_point (1, 1) double {mustBeInteger, mustBePositive} = 501 % 生成点数，必须为正整数
                Wid_in (1, 1) double {mustBePositive} = 2.8 % 输入宽度，必须为正数
                Wid_out (1, 1) double {mustBePositive} = 2.8 % 输出宽度，必须为正数
                etch_angle (1, 1) double = 60 % 刻蚀角度
                h_wg (1, 1) double {mustBePositive} = 0.25 % 波导高度，必须为正数
            end

            % 生成角度列表
            theta_list = linspace(initial_angle, initial_angle + arc_angle, N_point);

            % 计算弧长列表
            s_list = R_arc * (theta_list - initial_angle);

            % 计算圆弧轨迹
            % 圆弧中心在垂直于初始方向的位置
            center_x = -R_arc * sin(initial_angle);
            center_y = R_arc * cos(initial_angle);

            % 圆弧上的点坐标
            x_list = center_x + R_arc * sin(theta_list);
            y_list = center_y - R_arc * cos(theta_list);

            % 生成宽度渐变列表
            mk_wid = 1;
            width_list = Wcli_wg.Taper_width_gen(Wid_in, Wid_out, mk_wid, s_list);

            % 创建波导结构对象
            arc_bend = Wcli_wg(x_list, y_list, theta_list, width_list, etch_angle, h_wg);
        end

        function arc_bend = arc_wg_gen(options)
            % 生成圆弧波导段（使用名称-值参数）
            %
            % 名称-值参数:
            %   R_arc         - 圆弧半径 (μm)，默认 200
            %   angle         - 圆弧角度 (弧度)，默认 π/2 (90度)
            %   initial_angle - 初始角度 (弧度)，默认 0
            %   N_point       - 生成点数，默认 501
            %   Wid_in        - 输入宽度 (μm)，默认 2.8
            %   Wid_out       - 输出宽度 (μm)，默认 2.8
            %   etch_angle    - 刻蚀角度 (度)，默认 83
            %   h_wg          - 波导高度 (μm)，默认 0.22
            %   show_info     - 是否显示生成信息，默认 false
            %
            % 输出:
            %   arc_bend - 生成的圆弧波导对象

            arguments
                options.R_arc (1, 1) double {mustBePositive} = 200        % 圆弧半径
                options.angle (1, 1) double = pi/2                        % 圆弧角度
                options.initial_angle (1, 1) double = 0                   % 初始角度
                options.N_point (1, 1) double {mustBeInteger, mustBePositive} = 501 % 点数
                options.Wid_in (1, 1) double {mustBePositive} = 1.5       % 输入宽度
                options.Wid_out (1, 1) double {mustBePositive} = 1.5      % 输出宽度
                options.etch_angle (1, 1) double = 83                     % 刻蚀角度
                options.h_wg (1, 1) double {mustBePositive} = 0.22        % 波导高度
                options.show_info (1, 1) logical = false                  % 是否显示信息
            end

            % 生成角度列表
            theta_list = linspace(options.initial_angle, options.initial_angle + options.angle, options.N_point);

            % 计算弧长列表
            s_list = options.R_arc * (theta_list - options.initial_angle);

            % 计算圆弧轨迹 (圆弧中心在垂直于初始方向的位置)
            center_x = -options.R_arc * sin(options.initial_angle);
            center_y = options.R_arc * cos(options.initial_angle);

            % 圆弧上的点坐标
            x_list = center_x + options.R_arc * sin(theta_list);
            y_list = center_y - options.R_arc * cos(theta_list);

            % 生成宽度渐变列表 (默认线性渐变阶数 mk=1)
            mk_wid = 1;
            width_list = Wcli_wg.Taper_width_gen(options.Wid_in, options.Wid_out, mk_wid, s_list);

            % 创建波导结构对象
            arc_bend = Wcli_wg(x_list, y_list, theta_list, width_list, options.etch_angle, options.h_wg);

            % 可选：显示信息
            if options.show_info
                fprintf('圆弧波导生成完成:\n');
                fprintf('  半径: %.3f μm, 角度: %.1f°\n', options.R_arc, rad2deg(options.angle));
                fprintf('  宽度: %.3f -> %.3f μm\n', options.Wid_in, options.Wid_out);
                fprintf('  总长度: %.3f μm\n', arc_bend.trace_length);
            end
        end

        function [Euler_180_bend, R_min_calculated] = Euler_180_bend_sym_Rmid_dy(R_max, target_displacement, N_point, Wid_in, Wid_out, etch_angle, h_wg, initial_angle)
            % 生成180度欧拉弯曲波导U型弯，由两个对称的90度欧拉弯曲组成
            % 输入参数:
            %   R_max - 最大弯曲半径,也是输入输出半径
            %   target_displacement - 目标位移 (dy，因为180度弯曲dx=0, dy为侧向位移)
            %   N_point - 每段的生成点数
            %   Wid_in - 输入波导宽度
            %   Wid_out - 输出波导宽度
            %   etch_angle - 刻蚀角度
            %   h_wg - 波导高度
            %   initial_angle - 初始角度（可选，默认为0）
            % 输出:
            %   Euler_180_bend - 生成的180度弯曲波导对象
            %   R_min_calculated - 计算得到的最小弯曲半径

            arguments
                R_max (1, 1) double {mustBePositive} = 2000 % 最大弯曲半径
                target_displacement (1, 1) double {mustBePositive} = 300 % 目标位移
                N_point (1, 1) double {mustBePositive} = 501 % 生成点数
                Wid_in (1, 1) double {mustBePositive} = 1 % 输入波导宽度
                Wid_out (1, 1) double {mustBePositive} = 5 % 输出波导宽度
                etch_angle (1, 1) double = 83 % 刻蚀角度
                h_wg (1, 1) double {mustBePositive} = 0.22 % 波导高度
                initial_angle (1, 1) double = 0 % 初始角度（默认为0）
            end

            % 90度弯曲角度
            bend_90_deg = pi / 2; % 90度 = π/2 弧度

            % 计算中间宽度（用于两段之间的连接）
            Wid_mid = (Wid_in + Wid_out) / 2;

            mk = 1;

            % 设置fzero的选项
            options = optimset( ...
                'Display', 'off', ... % 显示迭代过程
                'TolX', 1e-12, ... % x的容差
                'MaxIter', 1000, ... % 最大迭代次数
                'MaxFunEvals', 2000 ... % 最大函数求值次数
                );

            % 使用fzero求解R_min，使得两个90度弯曲的dy之和等于目标位移
            % 对于180度U型弯，总的dy = 2 * 单个90度弯的dy
            R_min_calculated = fzero(@(R_min_calculated) ...
                2 * Wcli_wg.Euler_get_dy(R_max, R_min_calculated, bend_90_deg, mk, initial_angle) - target_displacement, ...
                target_displacement / bend_90_deg * 2, options);

            % 生成第1个90度弯曲
            Euler_bend_1 = Wcli_wg.Euler_wg_gen( ...
                R_max, ... % 最大半径（第一段的起始半径）
                R_min_calculated, ... % 最小半径（第一段的结束半径）
                bend_90_deg, ... % 90度弯曲角度
                initial_angle, ... % 初始角度
                N_point, ... % 点数
                Wid_in, ... % 输入宽度
                Wid_mid, ... % 中间宽度
                etch_angle, ... % 刻蚀角度
                h_wg ... % 波导高度
                );

            % 生成第2个90度弯曲（对称的）
            Euler_bend_2 = Euler_bend_1.copy(); % 创建第一段的副本
            Euler_bend_2.mirror_translate_shape('x'); % 沿x轴镜像
            width_list = Wcli_wg.Taper_width_gen(Wid_mid, Wid_out, mk, Euler_bend_2.L_list);
            Euler_bend_2.set_width_list(width_list); % 重新设置宽度列表

            % 拼接两个90度弯曲成为完整的180度U型弯
            % 第二段的第一个点与第一段的最后一个点重合，所以要移除第二段的第一个点
            Euler_180_bend = Euler_bend_1.copy(); % 创建第一段的副本
            Euler_180_bend.merge_and_translate(0, 0, 1, Euler_bend_2); % 拼接第二段

            % 验证结果：检查最终的dx和dy是否接近目标值
            final_dx = Euler_180_bend.WTX(end) - Euler_180_bend.WTX(1);
            final_dy = Euler_180_bend.WTY(end) - Euler_180_bend.WTY(1);
            final_theta = Euler_180_bend.theta_list(end) - Euler_180_bend.theta_list(1);

            % 可选：显示验证信息
            if nargout == 0 % 如果没有输出参数，显示信息
                fprintf('180度欧拉U型弯生成完成:\n');
                fprintf('  计算的最小半径: %.3f μm\n', R_min_calculated);
                fprintf('  目标侧向位移: %.3f μm\n', target_displacement);
                fprintf('  实际dx: %.6f μm (应接近0)\n', final_dx);
                fprintf('  实际dy: %.3f μm\n', final_dy);
                fprintf('  实际总角度: %.3f° (应接近180°)\n', rad2deg(final_theta));
                fprintf('  dx误差: %.6f μm\n', abs(final_dx));
                fprintf('  dy误差: %.6f μm\n', abs(final_dy - target_displacement));

                % 绘制结果
                figure(21);
                Euler_180_bend.plot_wg_pos;
                title('180° U型弯 - 波导位置');

                figure(22);
                Euler_180_bend.plot_R_all;
                title('180° U型弯 - 曲率半径');

                figure(23);
                Euler_180_bend.plot_kappa_all;
                title('180° U型弯 - 曲率');

                figure(24);
                Euler_180_bend.plot_theta_all;
                title('180° U型弯 - 角度分布');
            end

        end

        function [Euler_arc_180_bend, R_min_calculated] = Euler_arc_bend_180_Rmid_dy( ...
                R_max, ... % 最大弯曲半径
                target_displacement, ... % 目标侧向位移 (dy)
                Euler_angle, ... % 欧拉段角度 (弧度)
                N_point, ... % 每段的生成点数
                Wid_in, ... % 输入波导宽度
                Wid_out, ... % 输出波导宽度
                etch_angle, ... % 刻蚀角度
                h_wg, ... % 波导高度
                initial_angle ... % 初始角度
                )
            % 生成180度欧拉-圆弧组合U型弯，由两个对称的90度组合弯曲组成
            % 输入参数:
            %   R_max - 最大弯曲半径
            %   target_displacement - 目标侧向位移 (dy)
            %   Euler_angle - 欧拉段角度 (弧度)
            %   N_point - 每段的生成点数
            %   Wid_in - 输入波导宽度
            %   Wid_out - 输出波导宽度
            %   etch_angle - 刻蚀角度
            %   h_wg - 波导高度
            %   initial_angle - 初始角度
            % 输出:
            %   Euler_arc_180_bend - 生成的180度组合弯曲波导对象
            %   R_min_calculated - 计算得到的圆弧半径

            arguments
                R_max (1, 1) double {mustBePositive} = 2000 % 最大弯曲半径
                target_displacement (1, 1) double {mustBePositive} = 300 % 目标位移
                Euler_angle (1, 1) double {mustBePositive} = pi / 6 % 欧拉段角度
                N_point (1, 1) double {mustBePositive} = 501 % 生成点数
                Wid_in (1, 1) double {mustBePositive} = 1 % 输入波导宽度
                Wid_out (1, 1) double {mustBePositive} = 5 % 输出波导宽度
                etch_angle (1, 1) double = 83 % 刻蚀角度
                h_wg (1, 1) double {mustBePositive} = 0.22 % 波导高度
                initial_angle (1, 1) double = 0 % 初始角度
            end

            % 设置fzero选项
            options = optimset( ...
                'Display', 'off', ...
                'TolX', 1e-12, ...
                'MaxIter', 1000, ...
                'MaxFunEvals', 2000 ...
                );

            % 使用fzero求解R_arc，使得两个90度组合弯曲的dy之和等于目标位移
            R_min_calculated = fzero(@(R_arc) calculate_total_dy(R_arc) - target_displacement, ...
                target_displacement / 2, options);

            Euler_arc_180_bend = Wcli_wg.Euler_Arc_bend_gen( ...
                R_max, ... % 最大弯曲半径
                R_min_calculated, ... % 计算得到的圆弧半径
                pi, ... % 总弯曲角度（180度）
                Euler_angle, ... % 欧拉段角度
                N_point, ... % 每段的生成点数
                Wid_in, ... % 输入波导宽度
                Wid_out, ... % 输出波导宽度
                etch_angle, ... % 刻蚀角度
                h_wg, ... % 波导高度
                initial_angle ... % 初始角度
                );

            % 验证结果
            final_dx = Euler_arc_180_bend.WTX(end) - Euler_arc_180_bend.WTX(1);
            final_dy = Euler_arc_180_bend.WTY(end) - Euler_arc_180_bend.WTY(1);
            final_theta = Euler_arc_180_bend.theta_list(end) - Euler_arc_180_bend.theta_list(1);

            % 显示验证信息
            if nargout == 0
                fprintf('180度欧拉-圆弧组合U型弯生成完成:\n');
                fprintf('  计算的圆弧半径: %.3f μm\n', R_min_calculated);
                fprintf('  欧拉段角度: %.1f°\n', rad2deg(Euler_angle));
                fprintf('  目标侧向位移: %.3f μm\n', target_displacement);
                fprintf('  实际dx: %.6f μm (应接近0)\n', final_dx);
                fprintf('  实际dy: %.3f μm\n', final_dy);
                fprintf('  实际总角度: %.3f° (应接近180°)\n', rad2deg(final_theta));
                fprintf('  dx误差: %.6f μm\n', abs(final_dx));
                fprintf('  dy误差: %.6f μm\n', abs(final_dy - target_displacement));

                % 绘制结果
                close all;
                figure(41);
                Euler_arc_180_bend.plot_wg_pos;
                title('180° 欧拉-圆弧组合U型弯 - 波导位置');
                axis equal;

                figure(42);
                Euler_arc_180_bend.plot_R_all;
                title('180° 欧拉-圆弧组合U型弯 - 曲率半径');

                figure(43);
                Euler_arc_180_bend.plot_kappa_all;
                title('180° 欧拉-圆弧组合U型弯 - 曲率');

                figure(44);
                Euler_arc_180_bend.plot_theta_all;
                title('180° 欧拉-圆弧组合U型弯 - 角度分布');
            end

            % 内部函数：计算总dy
            function total_dy = calculate_total_dy(R_arc)

                try
                    % 生成临时的90度组合弯曲来计算dy
                    temp_bend = Wcli_wg.Euler_Arc_bend_gen( ...
                        R_max, R_arc, pi, Euler_angle, N_point, ...
                        Wid_in, Wid_in, etch_angle, h_wg, initial_angle);
                    total_dy = temp_bend.WTY(end) - temp_bend.WTY(1);
                catch
                    total_dy = 1e6; % 如果计算失败，返回很大的值
                end

            end

        end

        function [Euler_arc_90_bend, R_min_calculated] = Euler_arc_bend_90_Rmid_dy( ...
                R_max, ... % 最大弯曲半径
                target_displacement, ... % 目标位移 (dx + dy，因为90度弯曲dx≈dy)
                Euler_angle, ... % 欧拉段角度 (弧度)
                N_point, ... % 每段的生成点数
                Wid_in, ... % 输入波导宽度
                Wid_out, ... % 输出波导宽度
                etch_angle, ... % 刻蚀角度
                h_wg, ... % 波导高度
                initial_angle ... % 初始角度
                )
            % 生成90度欧拉-圆弧组合弯曲，通过优化圆弧半径满足位移要求
            % 输入参数:
            %   R_max - 最大弯曲半径
            %   target_displacement - 目标位移 (90度弯曲的dx或dy)
            %   Euler_angle - 欧拉段角度 (弧度)
            %   N_point - 每段的生成点数
            %   Wid_in - 输入波导宽度
            %   Wid_out - 输出波导宽度
            %   etch_angle - 刻蚀角度
            %   h_wg - 波导高度
            %   initial_angle - 初始角度
            % 输出:
            %   Euler_arc_90_bend - 生成的90度组合弯曲波导对象
            %   R_min_calculated - 计算得到的圆弧半径

            arguments
                R_max (1, 1) double {mustBePositive} = 2000 % 最大弯曲半径
                target_displacement (1, 1) double {mustBePositive} = 150 % 目标位移
                Euler_angle (1, 1) double {mustBePositive} = pi / 6 % 欧拉段角度
                N_point (1, 1) double {mustBePositive} = 501 % 生成点数
                Wid_in (1, 1) double {mustBePositive} = 1 % 输入波导宽度
                Wid_out (1, 1) double {mustBePositive} = 6 % 输出波导宽度
                etch_angle (1, 1) double = 83 % 刻蚀角度
                h_wg (1, 1) double {mustBePositive} = 0.22 % 波导高度
                initial_angle (1, 1) double = 0 % 初始角度
            end

            % 参数验证
            if Euler_angle >= pi / 2
                error('对于90度弯曲，Euler_angle必须小于π/2');
            end

            % 设置fzero选项
            options = optimset( ...
                'Display', 'off', ...
                'TolX', 1e-12, ...
                'MaxIter', 1000, ...
                'MaxFunEvals', 2000 ...
                );

            % 使用fzero求解R_arc，使得90度组合弯曲的位移等于目标位移
            % 对于90度弯曲，我们可以选择优化dx或dy（它们应该接近相等）
            R_min_calculated = fzero(@(R_arc) calculate_90deg_displacement(R_arc) - target_displacement, ...
                target_displacement / (pi / 2) * 2, options);

            % 生成最终的90度欧拉-圆弧组合弯曲
            Euler_arc_90_bend = Wcli_wg.Euler_Arc_bend_gen( ...
                R_max, ... % 最大弯曲半径
                R_min_calculated, ... % 计算得到的圆弧半径
                pi / 2, ... % 总弯曲角度（90度）
                Euler_angle, ... % 欧拉段角度
                N_point, ... % 每段的生成点数
                Wid_in, ... % 输入波导宽度
                Wid_out, ... % 输出波导宽度
                etch_angle, ... % 刻蚀角度
                h_wg, ... % 波导高度
                initial_angle ... % 初始角度
                );

            % 验证结果
            final_dx = Euler_arc_90_bend.WTX(end) - Euler_arc_90_bend.WTX(1);
            final_dy = Euler_arc_90_bend.WTY(end) - Euler_arc_90_bend.WTY(1);
            final_theta = Euler_arc_90_bend.theta_list(end) - Euler_arc_90_bend.theta_list(1);
            actual_displacement = sqrt(final_dx ^ 2 + final_dy ^ 2); % 总位移

            % 显示验证信息
            if nargout == 0
                fprintf('90度欧拉-圆弧组合弯曲生成完成:\n');
                fprintf('  计算的圆弧半径: %.3f μm\n', R_min_calculated);
                fprintf('  欧拉段角度: %.1f°\n', rad2deg(Euler_angle));
                fprintf('  目标位移: %.3f μm\n', target_displacement);
                fprintf('  实际dx: %.3f μm\n', final_dx);
                fprintf('  实际dy: %.3f μm\n', final_dy);
                fprintf('  实际总位移: %.3f μm\n', actual_displacement);
                fprintf('  实际总角度: %.3f° (应接近90°)\n', rad2deg(final_theta));
                fprintf('  位移误差: %.6f μm\n', abs(actual_displacement - target_displacement));
                fprintf('  角度误差: %.6f°\n', rad2deg(abs(final_theta - pi / 2)));

                % 绘制结果
                close all;
                figure(51);
                Euler_arc_90_bend.plot_wg_pos;
                title('90° 欧拉-圆弧组合弯曲 - 波导位置');
                axis equal;
                grid on;

                figure(52);
                Euler_arc_90_bend.plot_R_all;
                title('90° 欧拉-圆弧组合弯曲 - 曲率半径');

                figure(53);
                Euler_arc_90_bend.plot_kappa_all;
                title('90° 欧拉-圆弧组合弯曲 - 曲率');

                figure(54);
                Euler_arc_90_bend.plot_theta_all;
                title('90° 欧拉-圆弧组合弯曲 - 角度分布');
            end

            % 内部函数：计算90度弯曲的位移
            function displacement = calculate_90deg_displacement(R_arc)

                try
                    % 生成临时的90度组合弯曲来计算位移
                    temp_bend = Wcli_wg.Euler_Arc_bend_gen( ...
                        R_max, R_arc, pi / 2, Euler_angle, N_point, ...
                        Wid_in, Wid_in, etch_angle, h_wg, initial_angle);

                    % 计算dx和dy
                    temp_dx = temp_bend.WTX(end) - temp_bend.WTX(1);
                    temp_dy = temp_bend.WTY(end) - temp_bend.WTY(1);

                    % 对于90度弯曲，可以选择不同的位移度量
                    % 选项1: 使用dx（适用于初始角度为0的情况）
                    % displacement = temp_dx;

                    % 选项2: 使用dy（适用于需要侧向位移的情况）
                    displacement = temp_dy;

                    % 选项3: 使用总位移（欧几里得距离）
                    % displacement = sqrt(temp_dx^2 + temp_dy^2);

                catch
                    displacement = 1e6; % 如果计算失败，返回很大的值
                end

            end

        end

        function Sbend = Euler_Sbend_wg_gen(R_max, R_min, bend_angle, N_point, Wid_in, Wid_out, etch_angle, h_wg, initial_angle)
            % 生成S弯波导，由两段反对称的欧拉弯曲组成
            % 输入参数:
            %   R_max - 最大弯曲半径,也是输入输出半径
            %   R_min - 最小弯曲半径
            %   bend_angle - 每段的弯曲角度 (弧度，通常为π/4或π/2)
            %   N_point - 每段的生成点数
            %   Wid_in - 输入波导宽度
            %   Wid_out - 输出波导宽度
            %   etch_angle - 刻蚀角度
            %   h_wg - 波导高度
            %   initial_angle - 初始角度（可选，默认为0）
            % 输出:
            %   Sbend - 生成的S弯波导对象
            %   R_min_calculated - 计算得到的最小弯曲半径

            arguments
                R_max (1, 1) double {mustBePositive} = 200000 % 最大弯曲半径
                R_min (1, 1) double = 200 % 最小弯曲半径（可选，-1表示自动计算）
                bend_angle (1, 1) double {mustBePositive} = 10/180 * pi % 弯曲角度
                N_point (1, 1) double {mustBePositive} = 501 % 生成点数
                Wid_in (1, 1) double {mustBePositive} = 1 % 输入波导宽度
                Wid_out (1, 1) double {mustBePositive} = 1 % 输出波导宽度
                etch_angle (1, 1) double = 83 % 刻蚀角度
                h_wg (1, 1) double {mustBePositive} = 0.22 % 波导高度
                initial_angle (1, 1) double = 0 % 初始角度（默认为0）

            end

            % 计算中间宽度（用于两段之间的连接）
            Wid_mid = (Wid_in + Wid_out) / 2;
            mk = 1;

            % 生成第1段弯曲（正向弯曲）
            Euler_bend_1 = Wcli_wg.Euler_wg_gen( ...
                R_max, ... % 最大半径（第一段的起始半径）
                R_min, ... % 最小半径（第一段的中间半径）
                bend_angle / 2, ... % 弯曲角度
                initial_angle, ... % 初始角度
                N_point, ... % 点数
                Wid_in, ... % 输入宽度
                Wid_mid, ... % 中间宽度
                etch_angle, ... % 刻蚀角度
                h_wg ... % 波导高度
                );
            Euler_bend_1_half = Euler_bend_1.copy();
            Euler_bend_1_half.mirror_translate_shape('y');
            Euler_bend_1_half.transform_shape(bend_angle);
            Euler_bend_1.merge_and_translate(0, 0, 1, Euler_bend_1_half);

            Euler_bend_2 = Euler_bend_1.copy();
            Euler_bend_2.mirror_translate_shape('xy');

            % 拼接两段弯曲成为完整的S弯
            % 第二段的第一个点与第一段的最后一个点重合，所以要移除第二段的第一个点
            Sbend = Euler_bend_1.copy(); % 创建第一段的副本
            Sbend.merge_and_translate(0, 0, 1, Euler_bend_2); % 拼接第二段
            width_list = Wcli_wg.Taper_width_gen(Wid_in, Wid_out, mk, Sbend.L_list);
            Sbend.set_width_list(width_list); % 设置宽度列表

            % 验证结果：检查最终的dx和dy是否符合S弯特性
            final_dx = Sbend.WTX(end) - Sbend.WTX(1);
            final_dy = Sbend.WTY(end) - Sbend.WTY(1);
            final_theta = Sbend.theta_list(end) - Sbend.theta_list(1);

            % 可选：显示验证信息
            if nargout == 0 % 如果没有输出参数，显示信息
                fprintf('S弯波导生成完成:\n');
                fprintf('  弯曲角度: ±%.1f°\n', rad2deg(bend_angle));
                fprintf('  实际dx: %.6f μm \n', final_dx);
                fprintf('  实际dy: %.3f μm\n', final_dy);
                fprintf('  实际总角度: %.6f° (应接近0°)\n', rad2deg(final_theta));
                fprintf('  角度误差: %.6f°\n', rad2deg(abs(final_theta)));

                % 绘制结果
                close all;
                figure(31);
                Sbend.plot_wg_pos;
                title('S弯波导 - 位置轨迹');
                axis equal;

                figure(32);
                Sbend.plot_R_all;
                title('S弯波导 - 曲率半径');

                figure(33);
                Sbend.plot_kappa_all;
                title('S弯波导 - 曲率分布');

                figure(34);
                Sbend.plot_theta_all;
                title('S弯波导 - 角度分布');
            end

        end

        function Sbend_with_straight = Euler_Sbend_stwg_gen(R_max, R_min, bend_angle, straight_length, N_point_bend, Wid_in, Wid_out, etch_angle, h_wg, initial_angle)
            % 生成中间带直波导的S弯波导
            % 输入参数:
            %   R_max - 最大弯曲半径
            %   R_min - 最小弯曲半径
            %   bend_angle - 每段的弯曲角度 (弧度)
            %   straight_length - 中间直波导段长度
            %   N_point_bend - 每个弯曲段的生成点数
            %   Wid_in - 输入波导宽度
            %   Wid_out - 输出波导宽度
            %   etch_angle - 刻蚀角度
            %   h_wg - 波导高度
            %   initial_angle - 初始角度（可选，默认为0）
            % 输出:
            %   Sbend_with_straight - 生成的带直波导的S弯波导对象

            arguments
                R_max (1, 1) double {mustBePositive} = 200000 % 最大弯曲半径
                R_min (1, 1) double {mustBePositive} = 200 % 最小弯曲半径
                bend_angle (1, 1) double {mustBePositive} = 10/180 * pi % 弯曲角度
                straight_length (1, 1) double {mustBePositive} = 100 % 直波导长度
                N_point_bend (1, 1) double {mustBePositive} = 501 % 弯曲段点数
                Wid_in (1, 1) double {mustBePositive} = 1 % 输入波导宽度
                Wid_out (1, 1) double {mustBePositive} = 1 % 输出波导宽度
                etch_angle (1, 1) double = 83 % 刻蚀角度
                h_wg (1, 1) double {mustBePositive} = 0.22 % 波导高度
                initial_angle (1, 1) double = 0 % 初始角度（默认为0）
            end

            % 计算中间宽度
            Wid_mid = (Wid_in + Wid_out) / 2;

            % 生成第1段弯曲（正向弯曲）
            Euler_bend_1 = Wcli_wg.Euler_sym_bend_gen( ...
                R_max, ... % 最大半径（第一段的起始半径）
                R_min, ... % 最小半径（第一段的结束半径）
                bend_angle, ... % 弯曲角度
                N_point_bend, ... % 点数
                Wid_in, ... % 输入宽度
                Wid_mid, ... % 中间宽度
                etch_angle, ... % 刻蚀角度
                h_wg, ... % 波导高度
                initial_angle ... % 初始角度
                );

            % 获取第一段的结束角度
            end_angle_1 = Euler_bend_1.theta_list(end);

            % 生成中间直波导段
            Straight_wg = Wcli_wg.Straight_wg_gen( ...
                straight_length, ... % 直波导长度
                end_angle_1, ... % 传播方向（与第一段结束角度相同）
                Wid_mid, ... % 波导宽度（保持中间宽度）
                etch_angle, ... % 刻蚀角度
                h_wg ... % 波导高度
                );

            % 生成第2段弯曲（反向弯曲）
            Euler_bend_2 = Euler_bend_1.copy(); % 创建第一段的副本
            Euler_bend_2.mirror_translate_shape('xy'); % 沿xy中心对称翻转

            % 拼接三段：第一段弯曲 + 直波导 + 第二段弯曲
            Sbend_with_straight = Euler_bend_1.copy();
            Sbend_with_straight.merge_and_translate(0, 0, 1, Straight_wg);
            Sbend_with_straight.merge_and_translate(0, 0, 1, Euler_bend_2);
            mk = 1;
            width_list = Wcli_wg.Taper_width_gen(Wid_in, Wid_out, mk, Sbend_with_straight.L_list);
            Sbend_with_straight.set_width_list(width_list); % 设置宽度列表

            % 验证结果
            final_dx = Sbend_with_straight.WTX(end) - Sbend_with_straight.WTX(1);
            final_dy = Sbend_with_straight.WTY(end) - Sbend_with_straight.WTY(1);
            final_theta = Sbend_with_straight.theta_list(end) - Sbend_with_straight.theta_list(1);

            % 可选：显示验证信息
            if nargout == 0
                fprintf('带直波导的S弯生成完成:\n');
                fprintf('  弯曲角度: ±%.1f°\n', rad2deg(bend_angle));
                fprintf('  直波导长度: %.3f μm\n', straight_length);
                fprintf('  实际dx: %.6f μm\n', final_dx);
                fprintf('  实际dy: %.3f μm\n', final_dy);
                fprintf('  实际总角度: %.6f° (应接近0°)\n', rad2deg(final_theta));
                fprintf('  总长度: %.3f μm\n', Sbend_with_straight.calc_trace_length());

                % 绘制结果
                close all;
                figure;
                Sbend_with_straight.plot_wg_pos;
                title('带直波导的S弯 - 位置轨迹');
                axis equal;

                figure;
                Sbend_with_straight.plot_R_all;
                title('带直波导的S弯 - 曲率半径');

                figure;
                Sbend_with_straight.plot_kappa_all;
                title('带直波导的S弯 - 曲率分布');

                figure;
                Sbend_with_straight.plot_theta_all;
                title('带直波导的S弯 - 角度分布');
            end

        end

        function [Sbend_optimized, straight_length_opt] = Euler_Sbend_stwg_optimize_length( ...
                target_dy, ... % 目标侧向位移
                bend_angle, ... % 固定弯曲角度 (弧度)
                R_max, ... % 最大弯曲半径
                R_min, ... % 最小弯曲半径
                N_point_bend, ... % 弯曲段点数
                Wid_in, ... % 输入波导宽度
                Wid_out, ... % 输出波导宽度
                etch_angle, ... % 刻蚀角度
                h_wg, ... % 波导高度
                initial_angle ... % 初始角度
                )
            % 固定弯曲角度，优化直波导长度以满足dy要求
            arguments
                target_dy (1, 1) double {mustBePositive} = 200 % 目标侧向位移
                bend_angle (1, 1) double {mustBePositive} = 20 * pi / 180 % 固定弯曲角度
                R_max (1, 1) double {mustBePositive} = 200000 % 最大弯曲半径
                R_min (1, 1) double {mustBePositive} = 200 % 最小弯曲半径
                N_point_bend (1, 1) double {mustBePositive} = 501 % 弯曲段点数
                Wid_in (1, 1) double {mustBePositive} = 1 % 输入波导宽度
                Wid_out (1, 1) double {mustBePositive} = 1 % 输出波导宽度
                etch_angle (1, 1) double = 83 % 刻蚀角度
                h_wg (1, 1) double {mustBePositive} = 0.22 % 波导高度
                initial_angle (1, 1) double = 0 % 初始角度
            end

            % 设置fzero选项
            %             options = optimset( ...
            %                 'Display', 'iter', ...
            %                 'TolX', 1e-12, ...
            %                 'MaxIter', 1000, ...
            %                 'MaxFunEvals', 2000 ...
            %                 );
            options = optimset( ...%不显示进度
                'TolX', 1e-12, ...
                'MaxIter', 1000, ...
                'MaxFunEvals', 2000 ...
                );

            % 定义dy方程：实际dy - 目标dy = 0
            dy_equation = @(straight_length) ...
                2 * Wcli_wg.Euler_get_dy(R_max, R_min, bend_angle / 2, 1, initial_angle) + ...
                2 * Wcli_wg.Euler_get_dy(R_min, R_max, bend_angle / 2, 1, bend_angle / 2) + ...
                straight_length * sin(bend_angle) - target_dy;

            % 使用fzero求解直波导长度
            straight_length_opt = fzero(dy_equation, target_dy / 2, options);

            % 生成优化后的S弯
            Sbend_optimized = Wcli_wg.Euler_Sbend_stwg_gen( ...
                R_max, R_min, bend_angle, straight_length_opt, N_point_bend, ...
                Wid_in, Wid_out, etch_angle, h_wg, initial_angle);

            % 显示结果
            if nargout == 0
                final_dx = Sbend_optimized.WTX(end) - Sbend_optimized.WTX(1);
                final_dy = Sbend_optimized.WTY(end) - Sbend_optimized.WTY(1);

                fprintf('S弯优化完成 (固定角度):\n');
                fprintf('  目标dy: %.3f μm\n', target_dy);
                fprintf('  固定角度: %.2f°\n', rad2deg(bend_angle));
                fprintf('  优化长度: %.3f μm\n', straight_length_opt);
                fprintf('  实际dx: %.6f μm\n', final_dx);
                fprintf('  实际dy: %.3f μm\n', final_dy);
                fprintf('  dy误差: %.6f μm\n', abs(final_dy - target_dy));

                close all;
                figure;
                Sbend_optimized.plot_wg_pos;
                title(sprintf('优化S弯 (固定角度%.1f°)', rad2deg(bend_angle)));
                axis equal;
                figure;
                Sbend_optimized.plot_R_all;
                title('优化S弯 - 曲率半径');
                figure;
                Sbend_optimized.plot_kappa_all;
                title('优化S弯 - 曲率分布');
                figure;
                Sbend_optimized.plot_theta_all;
                title('优化S弯 - 角度分布');
            end

        end

        function [Sbend_optimized, bend_angle_opt] = Euler_Sbend_stwg_optimize_angle( ...
                target_dy, ... % 目标侧向位移
                straight_length, ... % 固定直波导长度
                R_max, ... % 最大弯曲半径
                R_min, ... % 最小弯曲半径
                N_point_bend, ... % 弯曲段点数
                Wid_in, ... % 输入波导宽度
                Wid_out, ... % 输出波导宽度
                etch_angle, ... % 刻蚀角度
                h_wg, ... % 波导高度
                initial_angle ... % 初始角度
                )
            % 固定直波导长度，优化弯曲角度以满足dy要求
            arguments
                target_dy (1, 1) double {mustBePositive} = 500 % 目标侧向位移
                straight_length (1, 1) double {mustBePositive} = 100 % 固定直波导长度
                R_max (1, 1) double {mustBePositive} = 200000 % 最大弯曲半径
                R_min (1, 1) double {mustBePositive} = 200 % 最小弯曲半径
                N_point_bend (1, 1) double {mustBePositive} = 501 % 弯曲段点数
                Wid_in (1, 1) double {mustBePositive} = 1 % 输入波导宽度
                Wid_out (1, 1) double {mustBePositive} = 1 % 输出波导宽度
                etch_angle (1, 1) double = 83 % 刻蚀角度
                h_wg (1, 1) double {mustBePositive} = 0.22 % 波导高度
                initial_angle (1, 1) double = 0 % 初始角度
            end

            % 设置fzero选项
            options = optimset( ...
                'Display', 'off', ...
                'TolX', 1e-12, ...
                'MaxIter', 1000, ...
                'MaxFunEvals', 2000 ...
                );

            % 定义dy方程：实际dy - 目标dy = 0
            dy_equation = @(bend_angle) ...
                2 * Wcli_wg.Euler_get_dy(R_max, R_min, bend_angle / 2, 1, initial_angle) + ...
                2 * Wcli_wg.Euler_get_dy(R_min, R_max, bend_angle / 2, 1, bend_angle / 2) + ...
                straight_length * sin(bend_angle) - target_dy;

            % 使用fzero求解弯曲角度
            bend_angle_opt = fzero(dy_equation, pi / 2, options);

            % 生成优化后的S弯
            Sbend_optimized = Wcli_wg.Euler_Sbend_stwg_gen( ...
                R_max, R_min, bend_angle_opt, straight_length, N_point_bend, ...
                Wid_in, Wid_out, etch_angle, h_wg, initial_angle);

            % 显示结果
            if nargout == 0
                final_dx = Sbend_optimized.WTX(end) - Sbend_optimized.WTX(1);
                final_dy = Sbend_optimized.WTY(end) - Sbend_optimized.WTY(1);

                fprintf('S弯优化完成 (固定长度):\n');
                fprintf('  目标dy: %.3f μm\n', target_dy);
                fprintf('  固定长度: %.3f μm\n', straight_length);
                fprintf('  优化角度: %.2f°\n', rad2deg(bend_angle_opt));
                fprintf('  实际dx: %.6f μm\n', final_dx);
                fprintf('  实际dy: %.3f μm\n', final_dy);
                fprintf('  dy误差: %.6f μm\n', abs(final_dy - target_dy));

                close all;
                figure;
                Sbend_optimized.plot_wg_pos;
                title(sprintf('优化S弯 (固定长度%.1f°)', straight_length));
                axis equal;
                figure;
                Sbend_optimized.plot_R_all;
                title('优化S弯 - 曲率半径');
                figure;
                Sbend_optimized.plot_kappa_all;
                title('优化S弯 - 曲率分布');
                figure;
                Sbend_optimized.plot_theta_all;
                title('优化S弯 - 角度分布');
            end

        end
        function Sbend = euler_s_wg_gen(options)
            % 生成S弯波导的参数化函数（使用名称-值参数）
            % 由两段反对称的欧拉弯曲组成
            % 
            % 名称-值参数:
            %   R_max        - 最大弯曲半径 (μm)，默认 200000
            %   R_min        - 最小弯曲半径 (μm)，默认 200
            %   bend_angle   - 每段的弯曲角度 (弧度)，默认 π/18 (10°)
            %   N_point      - 每段的生成点数，默认 501
            %   Wid_in       - 输入波导宽度 (μm)，默认 1
            %   Wid_out      - 输出波导宽度 (μm)，默认 1
            %   etch_angle   - 刻蚀角度 (度)，默认 83
            %   h_wg         - 波导高度 (μm)，默认 0.22
            %   initial_angle - 初始角度 (弧度)，默认 0
            %   show_info    - 是否显示生成信息，默认 false
            %   show_plot    - 是否绘制结果图，默认 false
            %
            % 输出:
            %   Sbend - 生成的S弯波导对象
            %
            % 示例:
            %   % 基本用法（使用默认参数）
            %   sbend = Wcli_wg.euler_s_wg_gen();
            %
            %   % 自定义弯曲角度和半径
            %   sbend = Wcli_wg.euler_s_wg_gen('R_max', 20000, 'R_min', 150, ...
            %                                  'bend_angle', pi/6);
            %
            %   % 指定宽度渐变
            %   sbend = Wcli_wg.euler_s_wg_gen('Wid_in', 2.5, 'Wid_out', 3.5, ...
            %                                  'bend_angle', pi/4);
            %
            %   % 显示信息和绘图
            %   sbend = Wcli_wg.euler_s_wg_gen('R_max', 10000, 'R_min', 200, ...
            %                                  'show_info', true, 'show_plot', true);
        
            arguments
                options.R_max (1,1) double {mustBePositive} = 200000      % 最大弯曲半径
                options.R_min (1,1) double {mustBePositive} = 200         % 最小弯曲半径
                options.bend_angle (1,1) double {mustBePositive} = 10/180*pi  % 弯曲角度
                options.N_point (1,1) double {mustBePositive} = 501       % 生成点数
                options.Wid_in (1,1) double {mustBePositive} = 1          % 输入波导宽度
                options.Wid_out (1,1) double {mustBePositive} = 1         % 输出波导宽度
                options.etch_angle (1,1) double {mustBeInRange(options.etch_angle, 0, 90)} = 83  % 刻蚀角度
                options.h_wg (1,1) double {mustBePositive} = 0.22         % 波导高度
                options.initial_angle (1,1) double = 0                    % 初始角度
                options.show_info (1,1) logical = false                   % 是否显示信息
                options.show_plot (1,1) logical = false                   % 是否绘制结果
            end
        
            % 计算中间宽度（用于两段之间的连接）
            Wid_mid = (options.Wid_in + options.Wid_out) / 2;
            mk = 1;  % 欧拉弯曲阶数
        
            % 生成第1段弯曲（正向弯曲）
            Euler_bend_1 = Wcli_wg.euler_wg_gen( ...
                'R_in', options.R_max, ...         % 输入半径（第一段的起始半径）
                'R_out', options.R_min, ...        % 输出半径（第一段的中间半径）
                'angle', options.bend_angle / 2, ... % 弯曲角度
                'initial_angle', options.initial_angle, ... % 初始角度
                'N_point', options.N_point, ...    % 点数
                'Wid_start', options.Wid_in, ...   % 起始宽度
                'Wid_end', Wid_mid, ...            % 结束宽度
                'etch_angle', options.etch_angle, ... % 刻蚀角度
                'h_wg', options.h_wg ...           % 波导高度
            );
            
            % 生成第1段的镜像（用于对称）
            Euler_bend_1_half = Euler_bend_1.copy();
            Euler_bend_1_half.mirror_translate_shape('y');
            Euler_bend_1_half.transform_shape(options.bend_angle);
            Euler_bend_1.merge_and_translate(0, 0, 1, Euler_bend_1_half);
        
            % 生成第2段（对称的反向弯曲）
            Euler_bend_2 = Euler_bend_1.copy();
            Euler_bend_2.mirror_translate_shape('xy');
        
            % 拼接两段弯曲成为完整的S弯
            Sbend = Euler_bend_1.copy();
            Sbend.merge_and_translate(0, 0, 1, Euler_bend_2);
            
            % 设置宽度列表（从输入宽度到输出宽度的渐变）
            width_list = Wcli_wg.Taper_width_gen(options.Wid_in, options.Wid_out, mk, Sbend.L_list);
            Sbend.set_width_list(width_list);
        
            % 验证结果：检查最终的dx和dy是否符合S弯特性
            final_dx = Sbend.WTX(end) - Sbend.WTX(1);
            final_dy = Sbend.WTY(end) - Sbend.WTY(1);
            final_theta = Sbend.theta_list(end) - Sbend.theta_list(1);
        
            % 可选：显示验证信息
            if options.show_info
                fprintf('S弯波导生成完成:\n');
                fprintf('  最大半径: %.1f μm\n', options.R_max);
                fprintf('  最小半径: %.1f μm\n', options.R_min);
                fprintf('  弯曲角度: ±%.1f°\n', rad2deg(options.bend_angle));
                fprintf('  输入宽度: %.3f μm\n', options.Wid_in);
                fprintf('  输出宽度: %.3f μm\n', options.Wid_out);
                fprintf('  实际dx: %.6f μm\n', final_dx);
                fprintf('  实际dy: %.3f μm\n', final_dy);
                fprintf('  实际总角度: %.6f° (应接近0°)\n', rad2deg(final_theta));
                fprintf('  角度误差: %.6f°\n', rad2deg(abs(final_theta)));
                fprintf('  总长度: %.3f μm\n', Sbend.calc_trace_length());
            end
        
            % 可选：绘制结果
            if options.show_plot
                figure('Name', 'S弯波导生成结果', 'NumberTitle', 'off');
                
                subplot(2,2,1);
                Sbend.plot_wg_pos;
                title('S弯波导 - 位置轨迹');
                axis equal;
                grid on;
        
                subplot(2,2,2);
                Sbend.plot_R_all;
                title('S弯波导 - 曲率半径');
                grid on;
        
                subplot(2,2,3);
                Sbend.plot_kappa_all;
                title('S弯波导 - 曲率分布');
                grid on;
        
                subplot(2,2,4);
                Sbend.plot_theta_all;
                title('S弯波导 - 角度分布');
                grid on;
            end
        end
        function Sbend_with_straight = euler_s_stwg_gen(options)
            % 生成中间带直波导的S弯波导（使用名称-值参数）
            % 调用euler_sym_wg_gen生成对称弯曲段
            % 由两段对称的欧拉弯曲和中间直波导段组成
            % 
            % 名称-值参数:
            %   R_max           - 最大弯曲半径 (μm)，默认 200000
            %   R_min           - 最小弯曲半径 (μm)，默认 200
            %   total_angle     - 每段对称弯曲的总弯曲角度 (弧度)，默认 π/9 (20°)
            %   straight_length - 中间直波导段长度 (μm)，默认 100
            %   N_point         - 每段的生成点数，默认 501
            %   Wid_in          - 输入波导宽度 (μm)，默认 1
            %   Wid_out         - 输出波导宽度 (μm)，默认 1
            %   etch_angle      - 刻蚀角度 (度)，默认 83
            %   h_wg            - 波导高度 (μm)，默认 0.22
            %   initial_angle   - 初始角度 (弧度)，默认 0
            %   show_info       - 是否显示生成信息，默认 false
            %   show_plot       - 是否绘制结果图，默认 false
            %
            % 输出:
            %   Sbend_with_straight - 生成的带直波导的S弯波导对象

            arguments
                options.R_max (1,1) double {mustBePositive} = 200000      % 最大弯曲半径
                options.R_min (1,1) double {mustBePositive} = 200         % 最小弯曲半径
                options.total_angle (1,1) double {mustBePositive} = 20/180*pi  % 总弯曲角度（每段）
                options.straight_length (1,1) double {mustBePositive} = 100  % 直波导长度
                options.N_point (1,1) double {mustBePositive} = 501       % 生成点数
                options.Wid_in (1,1) double {mustBePositive} = 1          % 输入波导宽度
                options.Wid_out (1,1) double {mustBePositive} = 1         % 输出波导宽度
                options.etch_angle (1,1) double {mustBeInRange(options.etch_angle, 0, 90)} = 83  % 刻蚀角度
                options.h_wg (1,1) double {mustBePositive} = 0.22         % 波导高度
                options.initial_angle (1,1) double = 0                    % 初始角度
                options.show_info (1,1) logical = false                   % 是否显示信息
                options.show_plot (1,1) logical = false                   % 是否绘制结果
            end
        
            % 计算中间宽度（用于两段之间的连接）
            Wid_mid = (options.Wid_in + options.Wid_out) / 2;
            mk = 1;  % 欧拉弯曲阶数
        
            % 生成第1段对称弯曲（使用euler_sym_wg_gen）
            Sym_bend_1 = Wcli_wg.euler_sym_wg_gen( ...
                'R_max', options.R_max, ...                  % 最大半径
                'R_min', options.R_min, ...                  % 最小半径
                'total_angle', options.total_angle, ...      % 总弯曲角度
                'N_point', options.N_point, ...              % 点数
                'Wid_in', options.Wid_in, ...                % 输入宽度
                'Wid_out', Wid_mid, ...                      % 输出宽度（中间宽度）
                'etch_angle', options.etch_angle, ...        % 刻蚀角度
                'h_wg', options.h_wg, ...                    % 波导高度
                'initial_angle', options.initial_angle ...   % 初始角度
            );
            
            % 获取第一段对称弯曲的结束角度
            end_angle_1 = Sym_bend_1.theta_list(end);
            
            % 生成中间直波导段
            Straight_wg = Wcli_wg.Straight_wg_gen( ...
                options.straight_length, ...  % 直波导长度
                end_angle_1, ...              % 传播方向
                Wid_mid, ...                  % 波导宽度
                options.etch_angle, ...       % 刻蚀角度
                options.h_wg ...              % 波导高度
            );
            
            % 生成第2段对称弯曲（第1段的镜像翻转）
            Sym_bend_2 = Sym_bend_1.copy();
            Sym_bend_2.mirror_translate_shape('xy');
            
            % 拼接三段：第一段对称弯曲 + 直波导 + 第二段对称弯曲
            Sbend_with_straight = Sym_bend_1.copy();
            Sbend_with_straight.merge_and_translate(0, 0, 1, Straight_wg);
            Sbend_with_straight.merge_and_translate(0, 0, 1, Sym_bend_2);
            
            % 设置宽度列表（从输入宽度到输出宽度的渐变）
            width_list = Wcli_wg.Taper_width_gen(options.Wid_in, options.Wid_out, mk, Sbend_with_straight.L_list);
            Sbend_with_straight.set_width_list(width_list);
        
            % 验证结果
            final_dx = Sbend_with_straight.WTX(end) - Sbend_with_straight.WTX(1);
            final_dy = Sbend_with_straight.WTY(end) - Sbend_with_straight.WTY(1);
            final_theta = Sbend_with_straight.theta_list(end) - Sbend_with_straight.theta_list(1);
        
            % 可选：显示验证信息
            if options.show_info
                fprintf('带直波导的S弯波导生成完成:\n');
                fprintf('  最大半径: %.1f μm\n', options.R_max);
                fprintf('  最小半径: %.1f μm\n', options.R_min);
                fprintf('  每段对称弯曲角度: %.1f°\n', rad2deg(options.total_angle));
                fprintf('  直波导长度: %.3f μm\n', options.straight_length);
                fprintf('  实际dx: %.6f μm\n', final_dx);
                fprintf('  实际dy: %.3f μm\n', final_dy);
                fprintf('  角度误差: %.6f°\n', rad2deg(abs(final_theta)));
                fprintf('  总长度: %.3f μm\n', Sbend_with_straight.calc_trace_length());
            end
        
            % 可选：绘制结果
            if options.show_plot
                figure('Name', '带直波导的S弯波导生成结果', 'NumberTitle', 'off');
                
                subplot(2,2,1);
                Sbend_with_straight.plot_wg_pos;
                title('带直波导的S弯波导 - 位置轨迹');
                axis equal;
                grid on;
        
                subplot(2,2,2);
                Sbend_with_straight.plot_R_all;
                title('带直波导的S弯波导 - 曲率半径');
                grid on;
        
                subplot(2,2,3);
                Sbend_with_straight.plot_kappa_all;
                title('带直波导的S弯波导 - 曲率分布');
                grid on;
        
                subplot(2,2,4);
                Sbend_with_straight.plot_theta_all;
                title('带直波导的S弯波导 - 角度分布');
                grid on;
            end
        end
        function symmetric_bend = euler_sym_wg_gen(options)
            % 生成任意角度的对称欧拉弯曲波导（使用名称-值参数）
        
            arguments
                options.R_max (1,1) double {mustBePositive} = 600       % 最大弯曲半径
                options.R_min (1,1) double {mustBePositive} = 15         % 最小弯曲半径
                options.total_angle (1,1) double {mustBePositive} = pi  % 总弯曲角度
                options.N_point (1,1) double {mustBePositive} = 501       % 生成点数
                options.Wid_in (1,1) double {mustBePositive} = 1.5        % 输入波导宽度
                options.Wid_out (1,1) double {mustBePositive} = 1.5       % 输出波导宽度
                options.etch_angle (1,1) double {mustBeInRange(options.etch_angle, 0, 90)} = 83  % 刻蚀角度
                options.h_wg (1,1) double {mustBePositive} = 0.22         % 波导高度
                options.initial_angle (1,1) double = 0                    % 初始角度
                options.show_info (1,1) logical = false                   % 是否显示信息
                options.show_plot (1,1) logical = false                   % 是否绘制结果
            end
        
            % 计算每段的弯曲角度（总角度的一半）
            half_angle = options.total_angle / 2;
        
            % 计算中间宽度
            Wid_mid = (options.Wid_in + options.Wid_out) / 2;
            mk = 1;  % 欧拉弯曲阶数
        
            % 生成第1段弯曲（R_max → R_min，角度为 +half_angle）
            Euler_bend_1 = Wcli_wg.Euler_wg_gen( ...
                options.R_max, ...        % 起始半径（最大）
                options.R_min, ...        % 结束半径（最小）
                half_angle, ...           % 弯曲角度（半角）
                options.initial_angle, ... % 初始角度
                options.N_point, ...      % 点数
                options.Wid_in, ...       % 输入宽度
                Wid_mid, ...              % 中间宽度
                options.etch_angle, ...   % 刻蚀角度
                options.h_wg ...          % 波导高度
            );
        
            % 生成第1段的镜像复制（用于创建对称的第2段）
            Euler_bend_1_half = Euler_bend_1.copy();
        
            % 对第2段进行镜像变换和旋转变换
            Euler_bend_1_half.mir_wg('axis', 'y');           % 沿y轴镜像
            Euler_bend_1_half.transform_shape(options.total_angle); % 旋转总角度
        
            % 拼接两段形成完整的对称弯曲
            symmetric_bend = Euler_bend_1.copy();
            symmetric_bend.merge_wg(Euler_bend_1_half);
        
            % 设置第2段的宽度渐变（从输入宽度到输出宽度）
            width_list_2 = Wcli_wg.Taper_width_gen(options.Wid_in, options.Wid_out, mk, symmetric_bend.L_list);
            symmetric_bend.set_width_list(width_list_2);
        
            % 验证结果
            final_dx = symmetric_bend.WTX(end) - symmetric_bend.WTX(1);
            final_dy = symmetric_bend.WTY(end) - symmetric_bend.WTY(1);
            final_theta = symmetric_bend.theta_list(end) - symmetric_bend.theta_list(1);
        
            % 可选：显示验证信息
            if options.show_info
                fprintf('对称欧拉弯曲生成完成:\n');
                fprintf('  总弯曲角度: %.1f°\n', rad2deg(options.total_angle));
                fprintf('  每段角度: %.1f°\n', rad2deg(half_angle));
                fprintf('  最大半径: %.1f μm\n', options.R_max);
                fprintf('  最小半径: %.1f μm\n', options.R_min);
                fprintf('  输入宽度: %.3f μm\n', options.Wid_in);
                fprintf('  输出宽度: %.3f μm\n', options.Wid_out);
                fprintf('  实际dx: %.3f μm\n', final_dx);
                fprintf('  实际dy: %.3f μm\n', final_dy);
                fprintf('  实际总角度: %.3f° (目标: %.1f°)\n', rad2deg(final_theta), rad2deg(options.total_angle));
                fprintf('  角度误差: %.6f°\n', rad2deg(abs(final_theta - options.total_angle)));
                fprintf('  总长度: %.3f μm\n', symmetric_bend.calc_trace_length());
            end
        
            % 可选：绘制结果
            if options.show_plot
                figure('Name', sprintf('对称欧拉弯曲 (%.1f°)', rad2deg(options.total_angle)), 'NumberTitle', 'off');
                
                subplot(2,2,1);
                symmetric_bend.plot_wg_pos;
                title(sprintf('对称欧拉弯曲 (%.1f°) - 位置轨迹', rad2deg(options.total_angle)));
                axis equal;
                grid on;
        
                subplot(2,2,2);
                symmetric_bend.plot_R_all;
                title('对称欧拉弯曲 - 曲率半径');
                grid on;
        
                subplot(2,2,3);
                symmetric_bend.plot_kappa_all;
                title('对称欧拉弯曲 - 曲率分布');
                grid on;
        
                subplot(2,2,4);
                symmetric_bend.plot_theta_all;
                title('对称欧拉弯曲 - 角度分布');
                grid on;
            end
        end
        function euler_arc_bend = euler_arc_bend_gen(options)
            % 生成欧拉-圆弧-欧拉组合弯曲波导（使用名称-值参数）
            % 结构：欧拉段1 + 圆弧段 + 欧拉段2
        
            arguments
                options.R_max (1,1) double {mustBePositive} = 2000        % 最大弯曲半径
                options.R_arc (1,1) double {mustBePositive} = 200         % 圆弧段半径
                options.total_angle (1,1) double {mustBePositive} = pi  % 总弯曲角度
                options.Euler_angle (1,1) double {mustBePositive} = pi/2  % 欧拉段总角度
                options.N_point (1,1) double {mustBePositive} = 501       % 每段生成点数
                options.Wid_in (1,1) double {mustBePositive} = 1.5        % 输入宽度
                options.Wid_out (1,1) double {mustBePositive} = 1.5       % 输出宽度
                options.mk (1,1) double {mustBePositive} = 1              % 弯曲阶数
                options.mw (1,1) double {mustBePositive} = 1              % 宽度渐变阶数
                options.etch_angle (1,1) double = 83                      % 刻蚀角度
                options.h_wg (1,1) double {mustBePositive} = 0.22         % 波导高度
                options.initial_angle (1,1) double = 0                    % 初始角度
                options.show_info (1,1) logical = false                   % 是否显示信息
            end
        
            % 参数验证
            if options.Euler_angle >= options.total_angle
                error('Euler_angle 必须小于 total_angle');
            end
        
            % 计算各段角度
            euler_angle_half = options.Euler_angle / 2;
            arc_angle = options.total_angle - options.Euler_angle;
            wid_mid = (options.Wid_in + options.Wid_out) / 2;
        
            % 1. 生成第一段欧拉弯曲 (R_max -> R_arc)
            eb1 = Wcli_wg.euler_wg_gen(...
                'R_in', options.R_max, 'R_out', options.R_arc, ...
                'angle', euler_angle_half, 'initial_angle', 0, ...
                'N_point', options.N_point, 'Wid_start', options.Wid_in, 'Wid_end', wid_mid, ...
                'mk', options.mk, 'm_wid', options.mw, ...
                'etch_angle', options.etch_angle, 'h_wg', options.h_wg);
        
            % 2. 生成圆弧段
            ab = Wcli_wg.Arc_wg_gen(...
                options.R_arc, arc_angle, eb1.theta_list(end), ...
                options.N_point, wid_mid, wid_mid, ...
                options.etch_angle, options.h_wg);
        
            % 3. 生成第二段欧拉弯曲 (镜像第一段并调整宽度)
            eb2 = eb1.copy();
            eb2.mir_wg('axis', 'y');
            % 更新第二段的宽度渐变 (mid -> out)
            w_list2 = Wcli_wg.Taper_width_gen(wid_mid, options.Wid_out, options.mw, eb2.L_list);
            eb2.set_width_list(w_list2);
            eb2.transform_shape(options.total_angle);
        
            % 4. 拼接并应用初始角度
            euler_arc_bend = eb1.copy();
            euler_arc_bend.merge_wg({ab, eb2});
            euler_arc_bend.transform_shape(options.initial_angle);
        
            % 显示信息
            if options.show_info
                fprintf('欧拉-圆弧组合弯曲生成完成:\n');
                fprintf('  总角度: %.2f°, 欧拉段占比: %.2f°\n', rad2deg(options.total_angle), rad2deg(options.Euler_angle));
                fprintf('  R_max: %.1f, R_arc: %.1f\n', options.R_max, options.R_arc);
                fprintf('  mk: %.1f, mw: %.1f\n', options.mk, options.mw);
                fprintf('  总长度: %.3f μm\n', euler_arc_bend.trace_length);
            end
        end
        function euler_arc_sym_bend = euler_arc_sym_bend_gen(options)
            % 对称 Euler-Arc-Euler 弯曲
            % 宽度策略:
            %   - 输入/输出宽度相同: W_inout
            %   - 中间圆弧宽度固定: W_mid
            %   - 两侧欧拉段执行宽度渐变
        
            arguments
                options.R_max (1,1) double {mustBePositive} = 2000          % 欧拉段外侧大半径
                options.R_arc (1,1) double {mustBePositive} = 200           % 中间圆弧半径
                options.total_angle (1,1) double {mustBePositive} = pi      % 总弯曲角度
                options.arc_angle (1,1) double {mustBePositive} = pi/2    % 两段欧拉角度总和
                options.N_point (1,1) double {mustBeInteger,mustBePositive} = 501
                options.W_inout (1,1) double {mustBePositive} = 1.5         % 输入/输出宽度
                options.W_mid (1,1) double {mustBePositive} = 1.8           % 中间圆弧固定宽度
                options.mk (1,1) double {mustBePositive} = 1                % 欧拉曲率阶数
                options.mw (1,1) double {mustBePositive} = 1                % 宽度渐变阶数
                options.etch_angle (1,1) double = 83
                options.h_wg (1,1) double {mustBePositive} = 0.22
                options.initial_angle (1,1) double = 0
                options.show_info (1,1) logical = false
            end
        
            % 基本检查
            if options.arc_angle >= options.total_angle
                error('arc_angle 必须小于 total_angle');
            end
        
            euler_half = options.total_angle / 2 - options.arc_angle / 2; % 每段欧拉的角度
        
            % 1) 左侧欧拉段: W_inout -> W_mid
            eb1 = Wcli_wg.euler_wg_gen( ...
                'R_in', options.R_max, ...
                'R_out', options.R_arc, ...
                'angle', euler_half, ...
                'initial_angle', 0, ...
                'N_point', options.N_point, ...
                'Wid_start', options.W_inout, ...
                'Wid_end', options.W_mid, ...
                'mk', options.mk, ...
                'm_wid', options.mw, ...
                'etch_angle', options.etch_angle, ...
                'h_wg', options.h_wg);
        
            % 2) 中间圆弧: 固定 W_mid
            ab = Wcli_wg.arc_wg_gen( ...
                'R_arc', options.R_arc, ...
                'angle', options.arc_angle/2, ...
                'initial_angle', eb1.theta_list(end), ...
                'N_point', options.N_point, ...
                'Wid_in', options.W_mid, ...
                'Wid_out', options.W_mid, ...
                'etch_angle', options.etch_angle, ...
                'h_wg', options.h_wg);
        
            % 3) 右侧欧拉段: 几何镜像 + 宽度 W_mid -> W_inout
            eb1.merge_wg(ab); % 先合并以获取正确的末端角度和位置
            eb2 = eb1.copy();
            eb2.mir_wg('axis', 'y');
            % w_list2 = Wcli_wg.Taper_width_gen(options.W_mid, options.W_inout, options.mw, eb2.L_list);
            % eb2.set_width_list(w_list2);
            eb2.transform_shape(options.total_angle);
        
            % 4) 拼接 + 旋转初始角
            euler_arc_sym_bend = eb1.copy();
            euler_arc_sym_bend.merge_wg(eb2);
            euler_arc_sym_bend.transform_shape(options.initial_angle);
            euler_arc_sym_bend.resample_by_length( options.N_point);
        
            if options.show_info
                final_dx = euler_arc_sym_bend.WTX(end) - euler_arc_sym_bend.WTX(1);
                final_dy = euler_arc_sym_bend.WTY(end) - euler_arc_sym_bend.WTY(1);
                final_theta = euler_arc_sym_bend.theta_list(end) - euler_arc_sym_bend.theta_list(1);
        
                fprintf('euler_arc_sym_bend_gen 生成完成:\n');
                fprintf('  total_angle = %.3f deg\n', rad2deg(options.total_angle));
                fprintf('  Euler_angle = %.3f deg\n', rad2deg(options.Euler_angle));
                fprintf('  R_max = %.3f, R_arc = %.3f\n', options.R_max, options.R_arc);
                fprintf('  W_inout = %.3f, W_mid = %.3f\n', options.W_inout, options.W_mid);
                fprintf('  dx = %.3f, dy = %.3f\n', final_dx, final_dy);
                fprintf('  final theta = %.6f deg\n', rad2deg(final_theta));
                fprintf('  trace length = %.3f um\n', euler_arc_sym_bend.calc_trace_length());
            end
        end
        %% 纯欧拉生成
        function waveguide_obj = Euler_wg_gen(R_in, R_out, angle, initial_angle, N_point, Wid_start, Wid_end, etch_angle, h_wg)
            % 生成欧拉弯曲波导的参数化函数
            % 输入参数:
            %   R_min - 最小弯曲半径,输入半径
            %   R_max - 最大弯曲半径，输出半径
            %   angle - 弯曲角度 (弧度)
            %   mk - 欧拉弯曲的阶数
            mk = 1;
            %   N_point - 生成点数
            %   Wid_start - 起始波导宽度
            %   Wid_end - 结束波导宽度
            %   m_wid - 宽度渐变阶数
            m_wid = 1;
            %   etch_angle - 刻蚀角度
            %   h_wg - 波导高度
            %   initial_angle - 初始角度 (可选，默认为0)
            % 输出:
            %   waveguide_obj - 生成的波导对象

            % 生成欧拉弯曲轨迹
            [x_Euler_list, y_Euler_list, theta_list, L_list] = ...
                Wcli_wg.Euler_trace_gen(R_in, R_out, angle, mk, N_point, initial_angle);

            % 生成宽度渐变列表
            width_list = Wcli_wg.Taper_width_gen(Wid_start, Wid_end, m_wid, L_list);

            % 创建波导结构对象
            waveguide_obj = Wcli_wg(x_Euler_list, y_Euler_list, theta_list, width_list, etch_angle, h_wg);
        end


        function waveguide_obj = euler_wg_gen(options)
        
            arguments
                options.R_in (1,1) double {mustBePositive} = 20000         % 输入半径
                options.R_out (1,1) double {mustBePositive} = 200          % 输出半径
                options.angle (1,1) double {mustBePositive} = pi/2         % 弯曲角度
                options.initial_angle (1,1) double = 0                     % 初始角度
                options.N_point (1,1) double {mustBePositive} = 501        % 生成点数
                options.Wid_start (1,1) double {mustBePositive} = 1.5      % 起始宽度
                options.Wid_end (1,1) double {mustBePositive} = 1.5        % 结束宽度
                options.mk (1,1) double {mustBePositive} = 1               % 弯曲阶数 (新增)
                options.m_wid (1,1) double {mustBePositive} = 1            % 宽度渐变阶数 (新增)
                options.etch_angle (1,1) double {mustBeInRange(options.etch_angle, 0, 90)} = 83  % 刻蚀角度
                options.h_wg (1,1) double {mustBePositive} = 0.22          % 波导高度
                options.show_info (1,1) logical = false                    % 是否显示信息
                options.show_plot (1,1) logical = false                    % 是否绘制结果
            end
        
            % 使用指定的阶数参数
            mk = options.mk;
            m_wid = options.m_wid;
        
            % 生成欧拉弯曲轨迹
            [x_Euler_list, y_Euler_list, theta_list, L_list] = ...
                Wcli_wg.Euler_trace_gen(options.R_in, options.R_out, options.angle, ...
                                        mk, options.N_point, options.initial_angle);
        
            % 生成宽度渐变列表
            width_list = Wcli_wg.Taper_width_gen(options.Wid_start, options.Wid_end, ...
                                                    m_wid, L_list);
        
            % 创建波导结构对象
            waveguide_obj = Wcli_wg(x_Euler_list, y_Euler_list, theta_list, ...
                                    width_list, options.etch_angle, options.h_wg);
        
            % 可选：显示信息
            if options.show_info
                fprintf('欧拉弯曲波导生成完成:\n');
                fprintf('  输入半径: %.1f μm\n', options.R_in);
                fprintf('  输出半径: %.1f μm\n', options.R_out);
                fprintf('  弯曲角度: %.1f°\n', rad2deg(options.angle));
                fprintf('  弯曲阶数(mk): %.1f\n', mk);
                fprintf('  宽度阶数(m_wid): %.1f\n', m_wid);
                fprintf('  起始宽度: %.3f μm\n', options.Wid_start);
                fprintf('  结束宽度: %.3f μm\n', options.Wid_end);
                fprintf('  生成点数: %d\n', options.N_point);
                fprintf('  总长度: %.3f μm\n', waveguide_obj.calc_trace_length());
                
                % 计算位移
                dx = waveguide_obj.WTX(end) - waveguide_obj.WTX(1);
                dy = waveguide_obj.WTY(end) - waveguide_obj.WTY(1);
                fprintf('  dx: %.3f μm\n', dx);
                fprintf('  dy: %.3f μm\n', dy);
            end
        
            % 可选：绘制结果
            if options.show_plot
                figure('Name', sprintf('欧拉弯曲结果 (mk=%.1f, mw=%.1f)', mk, m_wid), 'NumberTitle', 'off');
                subplot(2,2,1);
                waveguide_obj.plot_wg_pos;
                title('欧拉弯曲 - 位置轨迹');
                axis equal;
                grid on;
        
                subplot(2,2,2);
                waveguide_obj.plot_R_all;
                title('欧拉弯曲 - 曲率半径');
                grid on;
        
                subplot(2,2,3);
                waveguide_obj.plot_kappa_all;
                title('欧拉弯曲 - 曲率分布');
                grid on;
        
                subplot(2,2,4);
                waveguide_obj.plot_theta_all;
                title('欧拉弯曲 - 角度分布');
                grid on;
            end
        end

        function [Sbend_inner, solve_result] = find_Cubic_bend_ajmd_inner(R_max_inner, ajmd_angle_inner, dkappa_in_set, r0, N_point, Wid_in, Wid_out, etch_angle, h_wg)
            % 生成基于三次样条优化的弯曲波导
            % 优化目标是dx，优化自变量是dkappa_out,弯曲角度
            % 输入参数:
            %   R_max_inner - 最大ajmd弯曲半径
            %   ajmd_angle_inner - 内圈切线角度 (弧度)
            %   dkappa_inner - 内圈曲率变化率
            %   r0 - 目标位移距离
            %   N_point - 生成点数
            %   Wid_in - 输入波导宽度
            %   Wid_out - 输出波导宽度
            %   m_wid - 宽度渐变阶数
            m_wid = 1;
            %   etch_angle - 刻蚀角度
            %   h_wg - 波导高度
            %   solver_options - 求解器选项 (可选)
            % 输出:
            %   Sbend_inner - 生成的内圈S弯曲波导对象
            %   solve_result - 求解结果结构体

            solver_options = optimoptions('fsolve', 'Display', 'off', ...
                'FunctionTolerance', 1e-12, 'MaxFunctionEvaluations', 1000);
            % 计算比例因子
            scaling_factor = 1 / R_max_inner / (abs(ajmd_angle_inner) * R_max_inner);

            % 定义非线性方程组
            equations = @(x) [
                Wcli_wg.cubic_get_delta(0, 1 / R_max_inner, x(1) * scaling_factor, dkappa_in_set, x(3), x(2)) - [r0, 0], ... % 位移约束（2个方程）
                Wcli_wg.theta_L_cubic(0, 1 / R_max_inner, x(1) * scaling_factor, dkappa_in_set, x(3)) - (ajmd_angle_inner - x(2)); % 角度约束（1个方程）
                ];

            % 设置初始值 [dkappa_out_scaled, initial_angle, L]
            x0 = [0, -ajmd_angle_inner, abs(ajmd_angle_inner) * r0];

            % 求解非线性方程组
            [x, fval, exitflag] = fsolve(equations, x0, solver_options);

            % 生成三次样条轨迹
            [x_Euler_list, y_Euler_list, theta_list] = ...
                Wcli_wg.cubic_trace_gen(0, 1 / R_max_inner, x(1) * scaling_factor, dkappa_in_set, x(3), N_point, x(2));

            % 计算弧长列表用于宽度渐变
            L_Euler_list = [0, cumsum(sqrt(diff(x_Euler_list) .^ 2 + diff(y_Euler_list) .^ 2))];

            % 生成宽度渐变列表
            width_list = Wcli_wg.Taper_width_gen(Wid_in, Wid_out, m_wid, L_Euler_list);

            % 创建波导结构对象
            Sbend_inner = Wcli_wg(x_Euler_list, y_Euler_list, theta_list, width_list, etch_angle, h_wg);

            % 保存求解结果
            solve_result.x = x;
            solve_result.fval = fval;
            solve_result.exitflag = exitflag;
            solve_result.scaling_factor = scaling_factor;
            solve_result.dkappa_in_set = dkappa_in_set;
            solve_result.dkappa_out_scaled = x(1) * scaling_factor;
            solve_result.initial_angle = x(2);
            solve_result.L = x(3);
        end

        function [Sbend_outer, result_info] = Cubic_bend_ajmd_out_fsolve(R_max_outer, Rp_out_next, bend_out_angle, N_point, Wid_out2, etch_angle, h_wg, ajmd_angle_outer, x_trace, y_trace, Xp_out_next, Yp_out_next)
            % 三次样条fsolve求解方法
            % 希望达到的目标位移
            target_dy = Yp_out_next - y_trace(end); % 挪到最上方输出
            target_dx = Xp_out_next - x_trace(end); % 挪到0位置

            % 算出比例因子方便求解器求解
            scaling_factor = 1 / R_max_outer / (abs(bend_out_angle) * Rp_out_next);

            % 直接定义非线性方程组（使用匿名函数）
            equations = @(x) [
                Wcli_wg.cubic_get_delta(1 / R_max_outer, 0, x(1) * scaling_factor, x(2) * scaling_factor, x(3), ajmd_angle_outer) - [target_dx, target_dy], ... % 位移约束（2个方程）
                (Wcli_wg.theta_L_cubic(1 / R_max_outer, 0, x(1) * scaling_factor, x(2) * scaling_factor, x(3)) - bend_out_angle), ... % 角度约束（1个方程）
                ];

            x0 = [0, 0, bend_out_angle * Rp_out_next * 1]; % 初始值
            options = optimoptions('fsolve', 'Display', 'off', 'FunctionTolerance', 1e-6, 'MaxFunctionEvaluations', 2000, 'MaxIterations', 1000, 'Algorithm', 'trust-region-dogleg');
            [x, fval, exitflag] = fsolve(equations, x0, options);

            [x_Euler_list, y_Euler_list, theta_list] = ...
                Wcli_wg.cubic_trace_gen(1 / R_max_outer, 0, x(1) * scaling_factor, x(2) * scaling_factor, x(3), N_point, ajmd_angle_outer);
            Sbend_outer = Wcli_wg(x_Euler_list, y_Euler_list, theta_list, Wid_out2, etch_angle, h_wg);

            % 计算等效系数 a0 a1 a2 a3
            kappa_in = 1 / R_max_outer;
            kappa_out = 0;
            dkappa_in = x(1) * scaling_factor;
            dkappa_out = x(2) * scaling_factor;
            L = x(3);

            cubic_a0 = 1 / R_max_outer;
            cubic_a1 = x(1) * scaling_factor;
            cubic_a2 = (3 * (kappa_out - kappa_in) - (2 * dkappa_in + dkappa_out) * L) / L ^ 2;
            cubic_a3 = ((dkappa_in + dkappa_out) * L - 2 * (kappa_out - kappa_in)) / L ^ 3;

            result_info.method = 'cubic_fsolve';
            result_info.optimization_result = x;
            result_info.fval = fval;
            result_info.exitflag = exitflag;
            result_info.scaling_factor = scaling_factor;
            result_info.target_displacement = [target_dx, target_dy];
            result_info.cubic_coefficients = [cubic_a0, cubic_a1, cubic_a2, cubic_a3];
            result_info.curvature_params = struct('kappa_in', kappa_in, 'kappa_out', kappa_out, 'dkappa_in', dkappa_in, 'dkappa_out', dkappa_out, 'L', L);
        end
        %% 直波导生成
        function waveguide_obj = Straight_wg_gen(wg_length, direction_angle, Wid, etch_angle, h_wg)
            % 生成直波导的参数化函数
            % 输入参数:
            %   length - 直波导长度
            %   direction_angle - 传播方向角度 (弧度，默认为0即x方向)
            %   N_point - 生成点数
            %   Wid_start - 起始波导宽度
            %   Wid_end - 结束波导宽度 (如果与起始宽度不同则为锥形波导)
            %   etch_angle - 刻蚀角度
            %   h_wg - 波导高度
            %   start_pos - 起始位置 [x0, y0] (可选，默认为[0,0])
            % 输出:
            %   waveguide_obj - 生成的波导对象

            arguments
                wg_length (1, 1) double {mustBePositive} = 10 % 波导长度
                direction_angle (1, 1) double = 0 % 传播方向角度（默认为0）
                Wid (1, 1) double {mustBePositive} = 3 % 起始宽度
                etch_angle (1, 1) double = 83 % 刻蚀角度
                h_wg (1, 1) double {mustBePositive} = 0.22 % 波导高度
            end

            x_list = [0, wg_length * cos(direction_angle)]; % x坐标列表
            y_list = [0, wg_length * sin(direction_angle)]; % y坐标列表

            % 角度列表（直波导角度恒定）
            theta_list = repmat(direction_angle, size(x_list));

            % 创建波导结构对象
            waveguide_obj = Wcli_wg(x_list, y_list, theta_list, Wid, etch_angle, h_wg);

            if nargout == 0 % 如果没有输出参数，显示信息
                fprintf('直波导生成完成:\n');
                fprintf('  长度: %.3f μm\n', wg_length);
                fprintf('  方向角度: %.1f°\n', rad2deg(direction_angle));
                fprintf('  波导宽度: %.3f μm\n', Wid);
                close all; % 关闭所有图形窗口
                figure;
                waveguide_obj.plot_wg_pos;
                title('直波导 - 位置轨迹');
                axis equal;
                figure;
                waveguide_obj.plot_R_all;
                title('直波导 - 曲率半径');
                figure;
                waveguide_obj.plot_kappa_all;
                title('直波导 - 曲率分布');
                figure;
                waveguide_obj.plot_theta_all;
                title('直波导 - 角度分布');
            end

        end

        function waveguide_obj = st_wg_gen(options)
            % 生成直波导的参数化函数（使用名称-值参数）
            % 
            % 名称-值参数:
            %   wg_length    - 波导长度 (μm)，默认 10
            %   direction    - 传播方向角度 (弧度)，默认 0 (沿x方向)
            %   Wid          - 波导宽度 (μm)，默认 3
            %   etch_angle   - 刻蚀角度 (度)，默认 83
            %   h_wg         - 波导高度 (μm)，默认 0.22
            %   start_pos    - 起始位置 [x0, y0] (μm)，默认 [0, 0]
            %   show_info    - 是否显示生成信息，默认 false
            %   show_plot    - 是否绘制结果图，默认 false
            %
            % 输出:
            %   waveguide_obj - 生成的波导对象
            %
            % 示例:
            %   % 基本用法（使用默认参数）
            %   wg = Wcli_wg.st_wg_gen();
            %
            %   % 自定义长度和宽度
            %   wg = Wcli_wg.st_wg_gen('wg_length', 100, 'Wid', 2.5);
            %
            %   % 指定起始位置和角度
            %   wg = Wcli_wg.st_wg_gen('wg_length', 50, 'direction', pi/4, ...
            %                          'start_pos', [10, 20]);
            %
            %   % 显示信息和绘图
            %   wg = Wcli_wg.st_wg_gen('wg_length', 100, 'Wid', 3, ...
            %                          'show_info', true, 'show_plot', true);
        
            arguments
                options.len (1,1) double {mustBePositive} = 10      % 波导长度
                options.dir (1,1) double = 0                        % 传播方向角度（弧度）
                options.Wid (1,1) double {mustBePositive} = 3             % 波导宽度
                options.etch_angle (1,1) double {mustBeInRange(options.etch_angle, 0, 90)} = 83  % 刻蚀角度
                options.h_wg (1,1) double {mustBePositive} = 0.22         % 波导高度
                options.start_pos (1,2) double = [0, 0]                   % 起始位置 [x0, y0]
                options.show_info (1,1) logical = false                   % 是否显示信息
                options.show_plot (1,1) logical = false                   % 是否绘制结果
            end
        
            % 计算终点坐标
            x_start = options.start_pos(1);
            y_start = options.start_pos(2);
            x_end = x_start + options.len * cos(options.dir);
            y_end = y_start + options.len * sin(options.dir);
            
            % 构造坐标列表
            x_list = [x_start, x_end];
            y_list = [y_start, y_end];
            
            % 角度列表（直波导角度恒定）
            theta_list = repmat(options.dir, size(x_list));
            
            % 创建波导结构对象
            waveguide_obj = Wcli_wg(x_list, y_list, theta_list, options.Wid, ...
                                   options.etch_angle, options.h_wg);
            
            % 可选：显示信息
            if options.show_info
                fprintf('直波导生成完成:\n');
                fprintf('  长度: %.3f μm\n', options.len);
                fprintf('  方向角度: %.1f°\n', rad2deg(options.dir));
                fprintf('  波导宽度: %.3f μm\n', options.Wid);
                fprintf('  起始位置: (%.3f, %.3f) μm\n', x_start, y_start);
                fprintf('  终止位置: (%.3f, %.3f) μm\n', x_end, y_end);
                fprintf('  刻蚀角度: %.1f°\n', options.etch_angle);
                fprintf('  波导高度: %.3f μm\n', options.h_wg);
            end
            
            % 可选：绘制结果
            if options.show_plot
                figure('Name', '直波导生成结果', 'NumberTitle', 'off');
                
                subplot(2,2,1);
                waveguide_obj.plot_wg_pos;
                title('直波导 - 位置轨迹');
                axis equal;
                grid on;
                
                subplot(2,2,2);
                waveguide_obj.plot_R_all;
                title('直波导 - 曲率半径');
                grid on;
                
                subplot(2,2,3);
                waveguide_obj.plot_kappa_all;
                title('直波导 - 曲率分布');
                grid on;
                
                subplot(2,2,4);
                waveguide_obj.plot_theta_all;
                title('直波导 - 角度分布');
                grid on;
            end
        end

        function taper_waveguide = taper_waveguide_gen( ...
                wg_length, ... % 锥形波导长度
                direction_angle, ... % 传播方向角度 (弧度)
                Wid_in, ... % 输入波导宽度
                Wid_out, ... % 输出波导宽度
                m_wid, ... % 宽度渐变阶数
                N_point, ... % 生成点数
                etch_angle, ... % 刻蚀角度
                h_wg ... % 波导高度
                )
            % 生成锥形波导的参数化函数
            % 输入参数:
            %   wg_length - 锥形波导长度 (μm)
            %   direction_angle - 传播方向角度 (弧度，默认为0即x方向)
            %   Wid_in - 输入波导宽度 (μm)
            %   Wid_out - 输出波导宽度 (μm)
            %   m_wid - 宽度渐变阶数 (默认为1，线性渐变)
            %   N_point - 生成点数 (默认为101)
            %   etch_angle - 刻蚀角度 (度)
            %   h_wg - 波导高度 (μm)
            % 输出:
            %   taper_waveguide - 生成的锥形波导对象

            arguments
                wg_length (1, 1) double {mustBePositive} = 100 % 锥形波导长度
                direction_angle (1, 1) double = 0 % 传播方向角度（默认为0）
                Wid_in (1, 1) double {mustBePositive} = 2.8 % 输入宽度
                Wid_out (1, 1) double {mustBePositive} = 6.0 % 输出宽度
                m_wid (1, 1) double {mustBePositive} = 1 % 宽度渐变阶数
                N_point (1, 1) double {mustBePositive} = 101 % 生成点数
                etch_angle (1, 1) double = 60 % 刻蚀角度
                h_wg (1, 1) double {mustBePositive} = 0.25 % 波导高度
            end

            % 生成位置坐标列表
            x_list = linspace(0, wg_length * cos(direction_angle), N_point);
            y_list = linspace(0, wg_length * sin(direction_angle), N_point);

            % 角度列表（锥形波导角度恒定）
            theta_list = repmat(direction_angle, size(x_list));

            % 计算弧长列表（用于宽度渐变）
            s_list = sqrt((x_list - x_list(1)) .^ 2 + (y_list - y_list(1)) .^ 2);

            % 使用Taper_width_gen函数生成宽度渐变列表
            width_list = Wcli_wg.Taper_width_gen(Wid_in, Wid_out, m_wid, s_list);

            % 创建波导结构对象
            taper_waveguide = Wcli_wg(x_list, y_list, theta_list, width_list, etch_angle, h_wg);

            % 可选：显示验证信息和绘图
            if nargout == 0
                fprintf('锥形波导生成完成:\n');
                fprintf('  长度: %.3f μm\n', wg_length);
                fprintf('  方向角度: %.1f°\n', rad2deg(direction_angle));
                fprintf('  输入宽度: %.3f μm\n', Wid_in);
                fprintf('  输出宽度: %.3f μm\n', Wid_out);
                fprintf('  渐变阶数: %.1f\n', m_wid);
                fprintf('  生成点数: %d\n', N_point);

                % 绘制结果
                close all;
                figure(81);
                taper_waveguide.plot_wg_pos;
                title('锥形波导 - 位置轨迹');
                axis equal;
                grid on;

                figure(82);
                taper_waveguide.plot_width_all;
                title('锥形波导 - 宽度分布');
                xlabel('弧长 (μm)');
                ylabel('宽度 (μm)');
                grid on;

                figure(83);
                taper_waveguide.plot_R_all;
                title('锥形波导 - 曲率半径 (应为无穷大)');

                figure(84);
                taper_waveguide.plot_theta_all;
                title('锥形波导 - 角度分布');
                ylabel('角度 (弧度)');
                grid on;
            end

        end
        function waveguide_obj = taper_wg_gen(options)
            arguments
                options.len (1,1) double {mustBePositive} = 100              % 锥形波导长度
                options.direction_angle (1,1) double = 0                          % 传播方向角度（弧度）
                options.Wid_in (1,1) double {mustBePositive} = 2.8                % 输入宽度
                options.Wid_out (1,1) double {mustBePositive} = 6.0               % 输出宽度
                options.m_wid (1,1) double {mustBePositive} = 1                   % 宽度渐变阶数
                options.N_point (1,1) double {mustBePositive} = 101               % 生成点数
                options.etch_angle (1,1) double {mustBeInRange(options.etch_angle, 0, 90)} = 83  % 刻蚀角度
                options.h_wg (1,1) double {mustBePositive} = 0.22                 % 波导高度
                options.start_pos (1,2) double = [0, 0]                           % 起始位置 [x0, y0]
                options.show_info (1,1) logical = false                           % 是否显示信息
                options.show_plot (1,1) logical = false                           % 是否绘制结果
            end
        
            % 生成相对位置坐标列表
            x_list_rel = linspace(0, options.len * cos(options.direction_angle), options.N_point);
            y_list_rel = linspace(0, options.len * sin(options.direction_angle), options.N_point);
        
            % 转换为实际坐标
            x_start = options.start_pos(1);
            y_start = options.start_pos(2);
            x_list = x_list_rel + x_start;
            y_list = y_list_rel + y_start;
        
            % 角度列表（锥形波导角度恒定）
            theta_list = repmat(options.direction_angle, size(x_list));
        
            % 计算弧长列表（用于宽度渐变）
            s_list = sqrt((x_list_rel - x_list_rel(1)).^2 + (y_list_rel - y_list_rel(1)).^2);
        
            % 使用Taper_width_gen函数生成宽度渐变列表
            width_list = Wcli_wg.Taper_width_gen(options.Wid_in, options.Wid_out, options.m_wid, s_list);
        
            % 创建波导结构对象
            waveguide_obj = Wcli_wg(x_list, y_list, theta_list, width_list, options.etch_angle, options.h_wg);
        
            % 可选：显示信息
            if options.show_info
                fprintf('渐变波导生成完成:\n');
                fprintf('  长度: %.3f μm\n', options.len);
                fprintf('  方向角度: %.1f°\n', rad2deg(options.direction_angle));
                fprintf('  输入宽度: %.3f μm\n', options.Wid_in);
                fprintf('  输出宽度: %.3f μm\n', options.Wid_out);
                fprintf('  渐变阶数: %.1f\n', options.m_wid);
                fprintf('  起始位置: (%.3f, %.3f) μm\n', x_start, y_start);
                fprintf('  终止位置: (%.3f, %.3f) μm\n', x_list(end), y_list(end));
                fprintf('  刻蚀角度: %.1f°\n', options.etch_angle);
                fprintf('  波导高度: %.3f μm\n', options.h_wg);
                fprintf('  生成点数: %d\n', options.N_point);
            end
        
            % 可选：绘制结果
            if options.show_plot
                figure('Name', '渐变波导生成结果', 'NumberTitle', 'off');
                
                subplot(2,2,1);
                waveguide_obj.plot_wg_pos;
                title('渐变波导 - 位置轨迹');
                axis equal;
                grid on;
                
                subplot(2,2,2);
                waveguide_obj.plot_width_all;
                title('渐变波导 - 宽度分布');
                xlabel('弧长 (μm)');
                ylabel('宽度 (μm)');
                grid on;
                
                subplot(2,2,3);
                waveguide_obj.plot_R_all;
                title('渐变波导 - 曲率半径 (应为无穷大)');
                grid on;
                
                subplot(2,2,4);
                waveguide_obj.plot_theta_all;
                title('渐变波导 - 角度分布');
                ylabel('角度 (弧度)');
                grid on;
            end
        end
        %% 单元模块
        function [cross_horiz, para] = cross_wg_gen(opt)
            % 生成光波导交叉结构
            % 用法: [h_cross, v_cross] = Wcli_wg.cross_wg_gen('cross_width', 3.5, 'taper_length', 8)

            arguments
                opt.etch_angle (1,1) double {mustBeInRange(opt.etch_angle, 0, 90)} = 70
                opt.h_wg (1,1) double {mustBePositive} = 0.25
                opt.h_slab (1,1) double {mustBeNonnegative} = 0.25
                opt.Wid_inout (1,1) double {mustBePositive} = 1.2
                opt.input_length (1,1) double {mustBePositive} = 15
                opt.cross_length (1,1) double {mustBePositive} = 23.8
                opt.cross_width (1,1) double {mustBePositive} = 3.2
                opt.taper_length (1,1) double {mustBePositive} = 7
                opt.m_wid (1,1) double {mustBePositive} = 1
                opt.n_points (1,1) double {mustBePositive, mustBeInteger} = 2
            end

            supple_wid = 0.12;%波导线宽补偿
%             opt.Wid_inout = opt.Wid_inout+supple_wid;
            opt.cross_width = opt.cross_width+supple_wid;

            % 生成交叉结构
            % 1. 生成锥形过渡区域
            L_list = linspace(0, opt.taper_length, opt.n_points);
            x_list = L_list;
            y_list = zeros(size(L_list));
            theta_list = zeros(size(L_list));
            width_list = Wcli_wg.Taper_width_gen(opt.Wid_inout, opt.cross_width, opt.m_wid, L_list);

            cross_in = Wcli_wg(x_list, y_list, theta_list, width_list, ...
                opt.etch_angle, opt.h_wg);

            % 2. 生成输入直波导
            in1_wg = Wcli_wg([0, opt.input_length], [0, 0], [0, 0], ...
                [opt.Wid_inout, opt.Wid_inout], opt.etch_angle, opt.h_wg);

            % 3. 构建水平方向的交叉结构
            cross_horiz = in1_wg.copy();
            cross_horiz.merge_and_translate(0, 0, 1, cross_in);

            % 4. 生成输出锥形
            cross_out = cross_horiz.copy();
            cross_out.mirror_translate_shape('y');

            % 5. 合并完整的水平交叉结构
            cross_horiz.merge_and_translate(opt.cross_length, 0, 0, cross_out);

            % 6. 平移到中心位置
            cross_horiz.transform_shape(0, -opt.cross_length / 2 - opt.taper_length - opt.input_length, 0);
            cross_horiz.center_to_position(0, 0);
            para = opt;
            para = rmfield(para, 'n_points');  % 删除 n_points 字段
        end

        function mmi_half = mmi_1x2_half_gen(opt)
            % 生成半个1x2 MMI结构（可选自动扇出连接）
            % 用法: mmi = Wcli_wg.mmi_1x2_half_gen('spac', 4.8, 'len_mmi', 59, 'fanout_spac', 10)

            arguments
                opt.etch_angle (1,1) double {mustBeInRange(opt.etch_angle, 0, 90)} = 70
                opt.h_wg (1,1) double {mustBePositive} = 0.25
                opt.wid_mmi (1,1) double {mustBePositive} = 9
                opt.len_mmi (1,1) double {mustBePositive} = 52.8
                opt.Tin_len (1,1) double {mustBePositive} = 50
                opt.Tout_len (1,1) double {mustBePositive} = 50
                opt.spac (1,1) double {mustBeNonnegative} = 4.8
                opt.Win (1,1) double {mustBePositive} = 1.2
                opt.Wout (1,1) double {mustBePositive} = 1.2
                opt.m_wid (1,1) double {mustBePositive} = 1
                opt.in_len (1,1) double {mustBePositive} = 15
                opt.fanout_spac (1,1) double {mustBeNonnegative} = 0  % 扇出间距，默认0（不连接）
                opt.R_max (1,1) double {mustBePositive} = 2000  % S弯最大曲率半径
                opt.R_min (1,1) double {mustBePositive} = 100     % S弯最小曲率半径
                opt.bend_angle (1,1) double {mustBePositive} = 20/180*pi  % S弯角度
                opt.N_point_bend (1,1) double {mustBePositive} = 201  % S弯采样点数
            end

            supple_wid = 0.12;%波导线宽补偿
%             opt.Win = opt.Win+supple_wid;
%             opt.Wout = opt.Wout+supple_wid;
            opt.wid_mmi = opt.wid_mmi+supple_wid;

            % 参数逻辑验证
            Tin_wid = opt.wid_mmi - opt.spac;
            Tout_wid = opt.wid_mmi - opt.spac;

            assert(opt.spac < opt.wid_mmi, '波导间距必须小于MMI宽度');
            assert(Tin_wid > opt.Win, '输入锥形宽度必须大于输入波导宽度');
            assert(Tout_wid > opt.Wout, '输出锥形宽度必须大于输出波导宽度');

            %% 生成基础 MMI 各段波导结构
            % 1. 输入直波导
            in_wg = Wcli_wg.Straight_wg_gen(...
                opt.in_len, 0, opt.Win, ...
                opt.etch_angle, opt.h_wg);

            % 2. 输入锥形
            mmi_in_taper = Wcli_wg.taper_waveguide_gen(...
                opt.Tin_len, 0, opt.Win, Tin_wid, ...
                opt.m_wid, 2, opt.etch_angle, opt.h_wg);

            % 3. MMI区域
            mmi_section = Wcli_wg.Straight_wg_gen(...
                opt.len_mmi, 0, opt.wid_mmi, ...
                opt.etch_angle, opt.h_wg);

            % 4. 输出锥形
            mmi_out_taper = Wcli_wg.taper_waveguide_gen(...
                opt.Tout_len, 0, Tout_wid, opt.Wout, ...
                opt.m_wid, 2, opt.etch_angle, opt.h_wg);

            % 5. 输出直波导
            out_wg = Wcli_wg.Straight_wg_gen(...
                opt.in_len, 0, opt.Wout, ...
                opt.etch_angle, opt.h_wg);

            %% 组装基础 MMI 结构
            mmi_half = in_wg.copy();
            mmi_half.merge_and_translate(0, 0, 1, mmi_in_taper);           % 输入锥形
            mmi_half.merge_and_translate(0, 0, 0, mmi_section);            % MMI区域
            mmi_half.merge_and_translate(0, opt.spac/2, 0, mmi_out_taper); % 输出锥形（带偏移）
            mmi_half.merge_and_translate(0, 0, 1, out_wg);                 % 输出直波导

            %% 判断是否需要添加扇出 S 弯
            if opt.fanout_spac > opt.spac
                % 需要添加 S 弯扇出
                target_dy = (opt.fanout_spac - opt.spac) / 2;  % 目标侧向位移

                % 验证参数合理性
                assert(target_dy > 0, '扇出间距必须大于 MMI 输出间距');

                % 生成 S 弯波导
                [Sbend_fanout, straight_length_opt] = Wcli_wg.Euler_Sbend_stwg_optimize_length( ...
                    target_dy, ...           % 目标侧向位移
                    opt.bend_angle, ...      % 固定弯曲角度
                    opt.R_max, ...           % 最大弯曲半径
                    opt.R_min, ...           % 最小弯曲半径
                    opt.N_point_bend, ...    % 弯曲段点数
                    opt.Wout, ...            % 输入波导宽度
                    opt.Wout, ...            % 输出波导宽度
                    opt.etch_angle, ...      % 刻蚀角度
                    opt.h_wg, ...            % 波导高度
                    0 ...                    % 初始角度
                    );

                % 连接 S 弯到 MMI 输出端
                mmi_half.merge_and_translate(0, 0, 1, Sbend_fanout);
            else
                if opt.fanout_spac > 0 && opt.fanout_spac <= opt.spac
                    warning('扇出间距 (%.2f μm) 小于或等于 MMI 输出间距 (%.2f μm)，不添加扇出结构', ...
                        opt.fanout_spac, opt.spac);
                end
            end
        end
        %% AJMD螺旋线相关函数
        function [spiral_complete, spiral_half, spiral_result] = generate_ajmd_spiral(params)
            % 生成AJMD螺旋的完整函数
            % 输入参数: params - 包含所有参数的结构体
            % 输出参数: spiral_result - 包含所有生成结果的结构体

            % 设置默认参数
            default_params = struct( ...
                'mk', 1, ... % 欧拉弯曲的阶数
                'm_wid', 1, ... % 弯曲宽度渐变的阶数
                'Wid_out', 2.8, ... % 输出Sbend输出波导宽度
                'Wid_out2', 6, ... % 进一步展宽的宽度
                'Wid_in', 2.8, ... % 输入Sbend输入波导宽度
                'Wid_port', 2.8, ... % 输入输出端口宽度
                'r0', 800, ... % ajmd内圈弯曲半径
                'angle0', 0, ... % 起始角度
                'gap', 16, ... % 波导gap
                'end_angle', 6 * pi, ... % 螺旋线角度，默认转3圈
                'Euler_seg', 0, ... % 是否分段欧拉
                'Side_out', 0, ... % 是否同侧输出ajmd
                'etch_angle', 83, ... % 刻蚀角度
                'h_wg', 0.22, ... % 波导高度
                'n_point_per_loop', 1000, ... % 一个loop的点数
                'R_offset', 0, ...
                'N_point', 501 ... % 欧拉弯曲生成点数
                );

            % 合并用户参数和默认参数
            params = Wcli_wg.merge_structs(default_params, params);

            % 提取参数到局部变量（可选，为了代码可读性）
            mk = params.mk;
            m_wid = params.m_wid;
            Wid_out = params.Wid_out;
            Wid_out2 = params.Wid_out2;
            Wid_in = params.Wid_in;
            Wid_port = params.Wid_port;
            r0 = params.r0;
            angle0 = params.angle0;
            gap = params.gap;
            end_angle = params.end_angle;
            Euler_seg = params.Euler_seg;
            etch_angle = params.etch_angle;
            h_wg = params.h_wg;
            n_point_per_loop = params.n_point_per_loop;
            N_point = params.N_point;
            R_offset = params.R_offset;

            % 计算派生参数
            A = r0; % 转化为ajmd螺旋线参数
            B = gap / (1 * pi); % 转化为ajmd螺旋线参数
            Wid_mid = (Wid_out + Wid_in) / 2;

            %% 生成螺旋线轨迹
            % 找对应的theta值
            %             end_angle = fzero(@(theta) Wcli_wg.L_theta_ajmd(theta, A, B) * 2 - L_spiral, [2 * pi, L_spiral]) + pi;
            n_loop = round(end_angle / (pi / 2)) + 1;
            n_half_pi = n_loop * (pi / 2);
            n_point_spiral = n_loop * n_point_per_loop + 1;
            angle_list = linspace(angle0, angle0 + end_angle, n_point_spiral);

            % 计算螺旋线参数
            rp = A + B * angle_list; % 极坐标半径list
            phi_list = atan(rp ./ B) + angle_list; % 切向角度
            r_list = (B ^ 2 + rp .^ 2) .^ (3/2) ./ (rp .^ 2 + 2 * B ^ 2); % 曲率半径
            x_trace = rp .* cos(angle_list); % ajmd螺旋线的trace
            y_trace = rp .* sin(angle_list);

            % 关键参数提取
            ajmd_angle_inner = phi_list(1);
            ajmd_angle_outer = phi_list(end);
            R_max_inner = r_list(1);
            dkappa_inner = Wcli_wg.ajmd_dkappa(A, B, 0);
            dkappa_outer = Wcli_wg.ajmd_dkappa(A, B, end_angle);
            R_max_outer = r_list(end);
            Rp_max_outer = rp(end);

            Rp_out_next = A + B * n_half_pi + R_offset;
            Xp_out_next = Rp_out_next * cos(n_half_pi);
            Yp_out_next = Rp_out_next * sin(n_half_pi);
            phi_out_next = round(ajmd_angle_outer / (pi / 2) + 1) * (pi / 2);

            %% 生成内圈S弯曲
            if Euler_seg % 分段欧拉
                % 生成内圈Sbend的一半
                [Sbend_inner_1, R_min_inner] = Wcli_wg.find_Euler_bend_Rout_dx(R_max_inner, ajmd_angle_inner, -ajmd_angle_inner, r0 / 2, N_point, Wid_in, Wid_mid, etch_angle, h_wg);
                Sbend_inner_2 = Wcli_wg.Euler_wg_gen(R_min_inner, R_max_inner, ajmd_angle_inner, 0, N_point, Wid_mid, Wid_out, etch_angle, h_wg);
                Sbend_inner_1.merge_and_translate(0, 0, 1, Sbend_inner_2);
                dkappa_in_set = 1 / R_max_inner * 2;
            else
                dkappa_in_set = dkappa_inner;
                [Sbend_inner_1, ~] = Wcli_wg.find_Cubic_bend_ajmd_inner(R_max_inner, ajmd_angle_inner, dkappa_in_set, r0, N_point, Wid_in, Wid_out, etch_angle, h_wg);
            end

            %% 生成ajmd螺旋线
            Wid_ajmd_list = Wcli_wg.wid_seg_sym(Wid_out, Wid_out2, 4 * pi, angle_list); %分段宽度渐变，大于某个角度的时候为固定值
            Spiral_1 = Wcli_wg(x_trace, y_trace, phi_list, Wid_ajmd_list, etch_angle, h_wg);

            %% 连接内圈和螺旋线
            Spiral_1_connect0 = Sbend_inner_1.copy;
            Spiral_1_connect0.merge_and_translate(0, 0, 1, Spiral_1);

            %% 生成外圈弯曲
            bend_out_angle = phi_out_next - ajmd_angle_outer;
            [Sbend_outer_1, result_info] = Wcli_wg.Cubic_bend_ajmd_out_fsolve(R_max_outer, Rp_out_next, bend_out_angle, N_point, Wid_port, etch_angle, ...
                h_wg, ajmd_angle_outer, x_trace, y_trace, Xp_out_next, Yp_out_next);

            %% 最终连接
            Spiral_1_connect0.merge_and_translate(0, 0, 1, Sbend_outer_1);

            %% 对称拼接成完整的spiral
            Spiral_2_connect0 = Spiral_1_connect0.copy;
            Spiral_1_connect0.mirror_translate_shape('xy');
            Spiral_1_connect0.merge_and_translate(0, 0, 1, Spiral_2_connect0);

            %% 返回结果结构体
            spiral_result = struct();

            % 主要结果
            spiral_complete = Spiral_1_connect0; % 完整的螺旋结构
            spiral_half = Spiral_2_connect0; % 半个螺旋结构

            % 几何参数
            spiral_result.geometry = struct( ...
                'x_trace', x_trace, ...
                'y_trace', y_trace, ...
                'phi_list', phi_list, ...
                'r_list', r_list, ...
                'rp', rp, ...
                'angle_list', angle_list, ...
                'end_angle', end_angle ...
                );

            % 关键参数
            spiral_result.key_params = struct( ...
                'ajmd_angle_inner', ajmd_angle_inner, ...
                'ajmd_angle_outer', ajmd_angle_outer, ...
                'R_max_inner', R_max_inner, ...
                'R_max_outer', R_max_outer, ...
                'dkappa_inner', dkappa_inner, ...
                'dkappa_outer', dkappa_outer, ...
                'bend_out_angle', bend_out_angle, ...
                'phi_out_next', phi_out_next, ...
                'Rp_out_next', Rp_out_next, ...
                'Xp_out_next', Xp_out_next, ...
                'Yp_out_next', Yp_out_next ...
                );

            % 输入参数备份
            spiral_result.input_params = params;

            % 外圈弯曲优化结果
            spiral_result.outer_bend_result = result_info;
        end

        function merged = merge_structs(default_struct, user_struct)
            % 合并结构体，用户参数覆盖默认参数
            merged = default_struct;

            if nargin > 1 && isstruct(user_struct)
                fields = fieldnames(user_struct);

                for i = 1:length(fields)
                    merged.(fields{i}) = user_struct.(fields{i});
                end

            end

        end
        %% 宽度渐变函数
        function wid_seg_list = wid_seg(Wid_in, Wid_out, theta_0, theta_list)
            % 宽度分段函数
            wid_seg_list = zeros(size(theta_list));
            wid_seg_list(theta_list < theta_0) = (theta_list(theta_list < theta_0) - theta_0) / theta_0 * (Wid_out - Wid_in) + Wid_out;
            wid_seg_list(theta_list >= theta_0) = Wid_out;
        end

        function wid_seg_list = wid_seg_sym(Wid_in, Wid_out, theta_0, theta_list)
            % 对称宽度分段函数
            % 0到theta_0: 宽度从Wid_in渐变到Wid_out
            % theta_end-theta_0到theta_end: 宽度从Wid_out渐变回Wid_in
            % 中间段: 保持Wid_out

            wid_seg_list = zeros(size(theta_list));
            theta_end = theta_list(end);

            % 前段：0到theta_0，从Wid_in渐变到Wid_out
            mask1 = theta_list <= theta_0;
            wid_seg_list(mask1) = Wid_in + (theta_list(mask1) / theta_0) * (Wid_out - Wid_in);

            % 中间段：theta_0到(theta_end-theta_0)，保持Wid_out
            mask2 = (theta_list > theta_0) & (theta_list < (theta_end - theta_0));
            wid_seg_list(mask2) = Wid_out;

            % 后段：(theta_end-theta_0)到theta_end，从Wid_out渐变回Wid_in
            mask3 = theta_list >= (theta_end - theta_0);
            wid_seg_list(mask3) = Wid_out - ((theta_list(mask3) - (theta_end - theta_0)) / theta_0) * (Wid_out - Wid_in);
        end
        %% 通用旋转变换函数
        % 定义内部函数进行旋转和平移变换
        function [X_new, Y_new] = rotate_translate(X_old, Y_old, theta, T_x, T_y)
            % 对坐标进行旋转和平移变换
            % 输入:
            %   X_old, Y_old: 原始坐标
            %   theta: 旋转角度(弧度), 默认为0
            %   T_x: X方向平移量, 默认为0
            %   T_y: Y方向平移量, 默认为0
            % 输出:
            %   X_new, Y_new: 变换后的坐标

            arguments
                X_old (:,:) double
                Y_old (:,:) double
                theta (1,1) double = 0  % 默认不旋转
                T_x (1,1) double = 0    % 默认不平移
                T_y (1,1) double = 0    % 默认不平移
            end

            cos_theta = cos(theta);
            sin_theta = sin(theta);

            % 进行旋转
            X_rot = X_old * cos_theta - Y_old * sin_theta;
            Y_rot = X_old * sin_theta + Y_old * cos_theta;

            % 进行平移
            X_new = X_rot + T_x;
            Y_new = Y_rot + T_y;
        end

        function [X_new, Y_new] = mirror_translate(X_old, Y_old, axis, T_x, T_y)
            % 内部方法：对X和Y进行镜像和翻转
            % 根据选择的轴进行镜像翻转
            switch axis
                case 'x'
                    X_mirrored = X_old; % X坐标保持不变
                    Y_mirrored = -Y_old; % Y坐标取反
                case 'y'
                    X_mirrored = -X_old; % X坐标取反
                    Y_mirrored = Y_old; % Y坐标保持不变
                case 'xy'
                    X_mirrored = -X_old; % X坐标取反
                    Y_mirrored = -Y_old; % Y坐标取反
                otherwise
                    error('Invalid axis. Choose "x", "y", or "xy".');
            end

            % 进行平移
            X_new = X_mirrored + T_x;
            Y_new = Y_mirrored + T_y;
        end

        %% 其他函数
        function set_fig(fig)

            if nargin < 2
                fig = gcf;
            end

            set(findall(fig, '-property', 'FontName'), 'FontName', 'Arial');
            set(findall(fig, '-property', 'FontSize'), 'FontSize', 16);
            set(findall(fig, '-property', 'Linewidth'), 'Linewidth', 1.5);
            %             set(gca,'Linewidth', 1)
        end
        function [P_interp_mesh, XI, YI] = interp_P_intensity(x, y, P_norm, options)
            % INTERP_P_INTENSITY 将原始数据重塑并插值为均匀网格
            % 采用 Name-Value 形式输入，输出顺序为 [P, X, Y]
            
            arguments
                x (1,:) double              % 原始 x 坐标向量
                y (1,:) double              % 原始 y 坐标向量
                P_norm (:,1) double         % 原始强度数据（列向量或与 x*y 长度一致）
                options.res (1,1) double {mustBePositive} = 0.01 % 默认分辨率 0.1
                options.method (1,1) string {mustBeMember(options.method, ["nearest", "linear", "cubic"])} = "nearest"
            end
        
            % 1. 获取原始尺寸
            x_num = length(x);
            y_num = length(y);
        
            % 2. 重塑为网格状态 (注意：转置以匹配 meshgrid 习惯)
            try
                P_mesh_raw = reshape(P_norm, x_num, y_num);
            catch
                error('P_norm 的长度 (%d) 与 x*y 的乘积 (%d) 不匹配。', length(P_norm), x_num * y_num);
            end
        
            % 3. 生成原始坐标网格
            [Xa, Ya] = meshgrid(x, y);
        
            % 4. 生成均匀的目标坐标网格
            x_interp = min(x) : options.res : max(x);
            y_interp = min(y) : options.res : max(y);
            [XI, YI] = meshgrid(x_interp, y_interp);
        
            % 5. 执行插值
            % 使用 griddata 处理可能存在的非均匀分布
            P_interp_mesh = griddata(Xa, Ya, P_mesh_raw', XI, YI, options.method);
        end
        function [P_interp_mesh, XI, YI] = interp_surf(x, y, P_norm, options)
            % INTERP_P_INTENSITY 将原始数据重塑并插值为均匀网格
            % 采用 Name-Value 形式输入，输出顺序为 [P, X, Y]
            
            arguments
                x (1,:) double              % 原始 x 坐标向量
                y (1,:) double              % 原始 y 坐标向量
                P_norm (:,1) double         % 原始强度数据（列向量或与 x*y 长度一致）
                options.num (1,1) double {mustBePositive} = 800 % 默认分辨率 0.1
                options.method (1,1) string {mustBeMember(options.method, ["nearest", "linear", "cubic"])} = "linear"
            end
        
            % 1. 获取原始尺寸
            x_num = length(x);
            y_num = length(y);
        
            % 2. 重塑为网格状态 (注意：转置以匹配 meshgrid 习惯)
            try
                P_mesh_raw = reshape(P_norm, y_num, x_num);
            catch
                error('P_norm 的长度 (%d) 与 x*y 的乘积 (%d) 不匹配。', length(P_norm), x_num * y_num);
            end
%             keyboard
            % 3. 生成原始坐标网格
            [Xa, Ya] = meshgrid(x, y);
        
            % 4. 生成均匀的目标坐标网格
            x_interp = linspace(min(x), max(x), options.num);
            y_interp = linspace(min(y), max(y), options.num);
            [XI, YI] = meshgrid(x_interp, y_interp);
        
            % 5. 执行插值
            % 使用 griddata 处理可能存在的非均匀分布
            P_interp_mesh = griddata(Xa, Ya, P_mesh_raw, XI, YI, options.method);
        end
        function save_name = generate_save_name(para, prefix)
            % 自动生成save_name
            fields = fieldnames(para);
            save_name = prefix;

            for i = 1:length(fields)
                field_name = fields{i};
                field_value = para.(field_name);
                if isnumeric(field_value) && mod(field_value, 1) == 0
                    % 数值是整数（包括64.00这种情况）
                    save_name = strcat(save_name, '_', field_name, '_', num2str(field_value, '%d'));
                else
                    % 浮点数，使用%g格式自动去除尾随零
                    save_name = strcat(save_name, '_', field_name, '_', num2str(field_value, '%.10g'));
                end
            end

        end

        function C = merge_two_structs(A, B)
            % 合并两个结构体A和B，C包含A和B的所有字段，以A为主

            C = A; % 先复制A的所有字段
            fieldsB = fieldnames(B);

            for i = 1:numel(fieldsB)
                field = fieldsB{i};

                if ~isfield(A, field)
                    C.(field) = B.(field); % 只添加A中没有的字段
                end

            end

        end

        function param_combinations = generate_param_combinations(default_params, sweep_params)
            % 生成参数扫描组合
            % 输入:
            %   default_params - 默认参数结构体
            %   sweep_params - 要扫描的参数结构体
            % 输出:
            %   param_combinations - 参数组合结构体数组

            % 获取所有要扫描的参数名和值
            sweep_names = fieldnames(sweep_params);
            n_params = length(sweep_names);

            if n_params == 0
                % 没有扫描参数，只返回默认参数
                param_combinations = default_params;
                return;
            end

            % 准备ndgrid的输入
            sweep_values = cell(1, n_params);
            for i = 1:n_params
                sweep_values{i} = sweep_params.(sweep_names{i});
            end

            % 生成网格
            grids = cell(1, n_params);
            [grids{:}] = ndgrid(sweep_values{:});

            % 计算总组合数
            total_combinations = numel(grids{1});

            % 初始化输出结构体数组
            param_combinations = repmat(default_params, total_combinations, 1);

            % 填充扫描参数值
            for i = 1:n_params
                param_name = sweep_names{i};
                grid_values = grids{i}(:);  % 转换为列向量
                for j = 1:total_combinations
                    param_combinations(j).(param_name) = grid_values(j);
                end
            end
        end

        function save_params_to_txt(s, save_folder, prefix)
            % 保存结构体中的标量和字符串到txt文件
            if nargin < 3
                prefix = '';
                % 第一次调用时创建文件
                txt_path = fullfile(save_folder, 'parasave.txt');
                fid = fopen(txt_path, 'w');

                if fid == -1
                    error('无法创建文件: %s', txt_path);
                end

                % 使用 try-catch 确保文件一定会被关闭
                try
                    fprintf(fid, 'Generated: %s\n\n', datestr(now));

                    % 递归写入所有字段
                    Wcli_wg.write_struct_fields(fid, s, '');

                catch ME
                    fclose(fid);  % 确保出错时关闭文件
                    rethrow(ME);
                end

                fclose(fid);  % 正常结束时关闭文件
            else
                % 递归调用（不应该到达这里）
                error('save_params_to_txt 只应该被直接调用，不应递归');
            end
        end

        function write_struct_fields(fid, s, prefix)
            % 递归写入结构体字段的辅助函数
            fields = fieldnames(s);
            for i = 1:length(fields)
                name = fields{i};
                value = s.(name);

                if isempty(prefix)
                    full_name = name;
                else
                    full_name = [prefix, '.', name];
                end

                if isstruct(value)
                    % 结构体：递归展开
                    fprintf(fid, '\n--- %s ---\n', full_name);
                    Wcli_wg.write_struct_fields(fid, value, full_name);
                elseif ischar(value) || isstring(value)
                    fprintf(fid, '%s: %s\n', full_name, value);
                elseif isscalar(value) && isnumeric(value)
                    fprintf(fid, '%s: %.6f\n', full_name, value);
                elseif isscalar(value) && islogical(value)
                    fprintf(fid, '%s: %d\n', full_name, value);
                end
            end
        end

        %% HFSS生成
        function put_HFSS(json_data, options)
            % 运行 HFSS 仿真
            % 输入参数:
            %   json_data - 包含仿真数据的结构体
            %   options - 可选参数（名称-值对）:
            %       run_flag - 是否运行仿真 (0: 仅创建, 1: 运行), 默认 1
            %       gui_flag - 是否显示 GUI (0: 无界面, 1: 显示界面), 默认 0
            %       machine_select - 计算机列表, 默认 'noblue:-1:9:90%:1'

            arguments
                json_data struct {mustBeNonempty}
                options.run_flag (1,1) double {mustBeMember(options.run_flag, [0, 1])} = 0
                options.gui_flag (1,1) double {mustBeMember(options.gui_flag, [0, 1])} = 1
                options.machine_select (1,:) char = 'noblue:-1:9:90%:1'
            end
            HFSSpath = """C:\Program Files\ANSYS Inc\v252\AnsysEM\ansysedt.exe""";
            tstr = datestr(now, 'HHMMSS');
            RSM_jobid = tstr(1:5);
            json_str = jsonencode(json_data,"PrettyPrint",true);
            save_folder = json_data.save_folder;
            save_aedt_path = fullfile(save_folder, 'sim_result.aedt');



            fid = fopen('matlab_to_hfss.json', 'w');
            fprintf(fid, '%s', json_str);
            fclose(fid);
            save('para_save.mat', '-struct', "json_data", '-v7.3');

            % 保存参数到文本文件（只保存标量和字符串）

            fid_txt = fopen('parameters.txt', 'w');
            if fid_txt ~= -1
                % 获取所有字段名
                field_names = fieldnames(json_data);

                % 遍历所有字段
                for i = 1:length(field_names)
                    field_name = field_names{i};
                    field_value = json_data.(field_name);

                    % 只保存标量（数值或逻辑值）和字符串
                    if isscalar(field_value) && (isnumeric(field_value) || islogical(field_value))
                        % 数值标量
                        fprintf(fid_txt, '%s = %.6f\n', field_name, field_value);
                    elseif ischar(field_value) || isstring(field_value)
                        % 字符串
                        fprintf(fid_txt, '%s = %s\n', field_name, char(field_value));
                    end
                    % 跳过数组、结构体等复杂类型
                end

                fclose(fid_txt);
            end

            

            if options.run_flag %运行仿真
                system(strcat(HFSSpath, " -RunScriptandExit ", json_data.open_py));%生成仿真副本
                if ~exist(save_folder, 'dir')
                    mkdir(save_folder);
                end
                param_txt_path = fullfile(save_folder, 'parameters.txt');
                copyfile('parameters.txt', param_txt_path);
                param_mat_path = fullfile(save_folder, 'para_save.mat');
                copyfile('para_save.mat', param_mat_path);
                copyfile('sim_result.aedt', save_aedt_path);
                %开始仿真
                if options.gui_flag
                    fprintf("可视化运行\n");
                    cmd = sprintf('%s -jobid RSM_%s -distributed -machinelist list="%s" -auto -monitor -batchsolve "%s"', HFSSpath, RSM_jobid, options.machine_select, save_aedt_path);
                else
                    fprintf("后台运行\n");
                    cmd = sprintf('%s -jobid RSM_%s -distributed -machinelist list="%s" -auto -monitor -ng -batchsolve "%s"', HFSSpath, RSM_jobid, options.machine_select, save_aedt_path);
                end
                system(cmd);
                %提取数据
                fprintf("提取数据\n");
                exp_script = fullfile(json_data.scriptFolder, json_data.extract_py);
                cmd = sprintf('%s -ng -batchextract %s %s', HFSSpath, exp_script, save_aedt_path);
                system(cmd);
            else
                fprintf("暂停中...\n");
                system(strcat(HFSSpath, " -RunScript ", json_data.open_py));%生成仿真副本
                fprintf("结束调试...\n");
            end
        end

        function ext_only_HFSS(json_data) %仅导出数据
            HFSSpath = """C:\Program Files\ANSYS Inc\v252\AnsysEM\ansysedt.exe""";
            save_folder = json_data.save_folder;
            save_aedt_path = fullfile(save_folder, 'sim_result.aedt');
            exp_script = fullfile(json_data.scriptFolder, json_data.extract_py);
            cmd = sprintf('%s -ng -batchextract %s %s', HFSSpath, exp_script, save_aedt_path);
            system(cmd);
        end

        function save_para_file(json_data)
            save(fullfile(json_data.save_folder, 'para_save.mat'), '-struct', "json_data", '-v7.3');

            % 保存参数到文本文件（只保存标量和字符串）
            param_txt_path = fullfile(json_data.save_folder, 'parameters.txt');
            fid_txt = fopen(param_txt_path, 'w');
            if fid_txt ~= -1
                % 获取所有字段名
                field_names = fieldnames(json_data);

                % 遍历所有字段
                for i = 1:length(field_names)
                    field_name = field_names{i};
                    field_value = json_data.(field_name);

                    % 只保存标量（数值或逻辑值）和字符串
                    if isscalar(field_value) && (isnumeric(field_value) || islogical(field_value))
                        % 数值标量
                        fprintf(fid_txt, '%s = %.6f\n', field_name, field_value);
                    elseif ischar(field_value) || isstring(field_value)
                        % 字符串
                        fprintf(fid_txt, '%s = %s\n', field_name, char(field_value));
                    end
                    % 跳过数组、结构体等复杂类型
                end

                fclose(fid_txt);
            end
        end

        function [wg, result] = cubic_pose_bend_gen(mode, pose_1, pose_2, ...
                R_min, N_per_section, width, etch_angle, height)
            % Generate a symmetric cubic single bend or a two-lobe S-bend.
            % Successful generation is silent. If R_min is infeasible, the
            % solver relaxes it and always emits a warning.
            arguments
                mode (1,:) char {mustBeMember(mode, {'single', 'sbend'})}
                pose_1 (1,3) double
                pose_2 (1,3) double
                R_min (1,1) double {mustBePositive} = 40
                N_per_section (1,1) double {mustBeInteger, ...
                    mustBeGreaterThan(N_per_section, 20)} = 401
                width (1,1) double {mustBePositive} = 1.2
                etch_angle (1,1) double = 70
                height (1,1) double {mustBePositive} = 0.25
            end
            [wg, result] = wcli_build_cubic_pose_bend_impl(mode, pose_1, ...
                pose_2, R_min, N_per_section, width, etch_angle, height);
        end

        function [wg, result] = cubic_ratio_sbend_gen(pose_1, pose_2, ...
                R_min, radius_ratio, N_per_section, width, etch_angle, height)
            % Generate two joined symmetric cubic bends with R2/R1 fixed.
            % Successful generation is silent. If R_min is infeasible, the
            % solver relaxes it and always emits a warning.
            arguments
                pose_1 (1,3) double
                pose_2 (1,3) double
                R_min (1,1) double {mustBePositive} = 40
                radius_ratio (1,1) double {mustBePositive} = 1
                N_per_section (1,1) double {mustBeInteger, ...
                    mustBeGreaterThan(N_per_section, 20)} = 401
                width (1,1) double {mustBePositive} = 1.2
                etch_angle (1,1) double = 70
                height (1,1) double {mustBePositive} = 0.25
            end
            [wg, result] = wcli_build_cubic_ratio_sbend_impl(pose_1, ...
                pose_2, R_min, radius_ratio, N_per_section, width, ...
                etch_angle, height);
        end
    end

end
function [wg, result] = wcli_build_cubic_pose_bend_impl(mode, pose_1, pose_2, ...
    R_min, N_per_section, width, etch_angle, height)
%BUILD_CUBIC_POSE_BEND Connect two poses with piecewise cubic curvature.
% Every transition calls Wcli_wg.kappa_L_cubic with zero dkappa at both
% ends. R_min is first imposed as a hard bound. For an infeasible S-bend,
% the bound is progressively relaxed with an explicit warning.

arguments
    mode (1,:) char {mustBeMember(mode, {'single', 'sbend'})}
    pose_1 (1,3) double
    pose_2 (1,3) double
    R_min (1,1) double {mustBePositive}
    N_per_section (1,1) double {mustBeInteger, mustBeGreaterThan(N_per_section, 20)}
    width (1,1) double {mustBePositive}
    etch_angle (1,1) double
    height (1,1) double {mustBePositive}
end

chord = hypot(pose_2(1)-pose_1(1), pose_2(2)-pose_1(2));
kappa_limit = 1/R_min;
requested_R_min = R_min;
effective_R_limit = R_min;
radius_constraint_met = true;
opts = optimoptions('fmincon', 'Display', 'off', 'Algorithm', 'sqp', ...
    'ConstraintTolerance', 1e-10, 'OptimalityTolerance', 1e-10, ...
    'StepTolerance', 1e-12, 'MaxIterations', 1500, ...
    'MaxFunctionEvaluations', 3e4);

if strcmp(mode, 'single')
    dtheta = wrap_pi(pose_2(3)-pose_1(3));
    if abs(dtheta) < 1e-8
        error('A single-direction bend requires theta_2 ~= theta_1.');
    end
    bend_sign = sign(dtheta);
    % As in euler_sym_wg_gen, the second half is the mirror of the first.
    % Therefore the chord must point along the mean of the two port angles.
    chord_angle = atan2(pose_2(2)-pose_1(2), pose_2(1)-pose_1(1));
    symmetry_axis_angle = pose_1(3)+dtheta/2;
    pose_symmetry_error = abs(wrap_pi(chord_angle-symmetry_axis_angle));
    if pose_symmetry_error > 1e-7
        error('Wcli_wg:SingleBendPosesNotSymmetric', [ ...
            'The requested poses cannot be joined by a symmetric single bend.\n', ...
            'Chord angle must equal (theta_1+theta_2)/2. ', ...
            'Current mismatch is %.6f deg.'], rad2deg(pose_symmetry_error));
    end

    % Obtain the scale from a unit-peak symmetric cubic bend. Scaling all
    % lengths by 1/kappa scales x/y by 1/kappa without changing angles.
    unit_half_length = abs(dtheta);
    unit_nodes = [0,bend_sign,0];
    [xu,yu] = trace_from_nodes([unit_half_length,unit_half_length], ...
        unit_nodes,[0,0,pose_1(3)],401);
    unit_chord = hypot(xu(end)-xu(1),yu(end)-yu(1));
    peak_magnitude = unit_chord/chord;
    if peak_magnitude > kappa_limit*(1+1e-10)
        effective_R_limit = 1/peak_magnitude;
        radius_constraint_met = false;
        warning('Wcli_wg:SingleBendRadiusRequirementViolated',[ ...
            '\n*** R_MIN REQUIREMENT VIOLATED ***\n', ...
            'Requested R_min = %.3f um, but the endpoint geometry ', ...
            'requires R_min = %.3f um.\n', ...
            'The smaller radius was used forcibly. This result does NOT ', ...
            'satisfy the requested loss constraint.\n'], ...
            requested_R_min,effective_R_limit);
    end
    half_length = abs(dtheta)/peak_magnitude;
    lengths = [half_length,half_length];
    peaks = bend_sign*peak_magnitude;
    nodes = [0, peaks, 0];
else
    % Try both S orientations. There is no zero-curvature straight section:
    % section 2 and section 3 share one kappa=0 sample directly.
    alpha0 = max(0.08, min(0.8, 2*abs(atan2( ...
        -(pose_2(1)-pose_1(1))*sin(pose_1(3)) + (pose_2(2)-pose_1(2))*cos(pose_1(3)), ...
         (pose_2(1)-pose_1(1))*cos(pose_1(3)) + (pose_2(2)-pose_1(2))*sin(pose_1(3))))));
    best = [];
    % First honor R_min exactly. If infeasible, progressively allow more
    % curvature (smaller radius) and emit a prominent warning afterward.
    relaxation_factors = [1, 1.1, 1.25, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10];
    for relaxation_factor = relaxation_factors
        trial_kappa_limit = relaxation_factor/R_min;
        k0 = min(0.75*trial_kappa_limit, ...
            max(0.2*trial_kappa_limit, 2*alpha0/chord));
        L0 = alpha0/k0;
        trial_best = [];
        for first_sign = [-1, 1]
            for scale = [0.65, 1, 1.5]
                x0 = [L0*scale,L0*scale,L0*scale,L0*scale,k0,k0];
                lb = [repmat(0.005*chord,1,4),1e-6,1e-6];
                ub = [repmat(5*chord,1,4),trial_kappa_limit,trial_kappa_limit];
                objective = @(v) sum(v(1:4))/chord + ...
                    2e-3*((v(1)-v(2))^2+(v(3)-v(4))^2)/chord^2 + ...
                    1e-3*(v(5)-v(6))^2/trial_kappa_limit^2;
                nonlcon = @(v) endpoint_constraint(v, mode, first_sign, pose_1, pose_2);
                [v, fval, exitflag] = fmincon(objective, x0, [], [], [], [], ...
                    lb, ub, nonlcon, opts);
                err = endpoint_error(v, mode, first_sign, pose_1, pose_2);
                score = norm(err) + max(0,-exitflag);
                if isempty(trial_best) || score < trial_best.score
                    trial_best = struct('v',v,'score',score,'fval',fval, ...
                        'exitflag',exitflag,'first_sign',first_sign);
                end
            end
        end
        if trial_best.exitflag > 0 && norm(endpoint_error(trial_best.v, ...
                mode, trial_best.first_sign, pose_1, pose_2)) <= 1e-7
            best = trial_best;
            kappa_limit = trial_kappa_limit;
            effective_R_limit = 1/trial_kappa_limit;
            radius_constraint_met = relaxation_factor == 1;
            break;
        end
    end
    if isempty(best)
        error(['No feasible S-bend was found even after reducing the radius ', ...
            'limit from %.3f um to %.3f um.'], R_min, R_min/relaxation_factors(end));
    end
    if ~radius_constraint_met
        warning('Wcli_wg:SBendRadiusRequirementViolated', [ ...
            '\n*** R_MIN REQUIREMENT VIOLATED ***\n', ...
            'No S-bend solution exists with requested R_min = %.3f um.\n', ...
            'Solver forcibly reduced the radius limit to %.3f um ', ...
            '(allowed curvature increased from %.6f to %.6f 1/um).\n', ...
            'This result does NOT satisfy the requested loss constraint.\n'], ...
            requested_R_min, effective_R_limit, 1/requested_R_min, kappa_limit);
    end
    lengths = best.v(1:4);
    peaks = [best.first_sign*best.v(5), -best.first_sign*best.v(6)];
    nodes = [0, peaks(1), 0, peaks(2), 0];
end

[x,y,theta,kappa,s,middle_index] = trace_from_nodes( ...
    lengths, nodes, pose_1, N_per_section);
wg = Wcli_wg(x, y, theta, width, etch_angle, height);

result.position_error = hypot(x(end)-pose_2(1), y(end)-pose_2(2));
result.angle_error = abs(wrap_pi(theta(end)-pose_2(3)));
result.endpoint_kappa_max = max(abs(kappa([1,end])));
result.peak_curvature = max(abs(kappa));
result.minimum_radius = 1/result.peak_curvature;
result.curvature_sign_changes = count_sign_changes(kappa);
result.kappa = kappa;
result.s = s;
result.lengths = lengths;
result.kappa_peaks = peaks;
result.middle_index = middle_index;
result.middle_kappa_abs = abs(kappa(middle_index));
result.middle_straight_length = 0;
result.requested_R_min = requested_R_min;
result.effective_R_limit = effective_R_limit;
result.radius_constraint_met = radius_constraint_met;
if strcmp(mode,'single')
    result.single_half_length = lengths(1);
    result.single_length_symmetry_error = abs(lengths(1)-lengths(2));
    result.pose_symmetry_error = pose_symmetry_error;
end
end

function [c,ceq] = endpoint_constraint(v, mode, bend_sign, p1, p2)
    c = [];
    ceq = endpoint_error(v, mode, bend_sign, p1, p2);
    if strcmp(mode,'sbend')
        chord = hypot(p2(1)-p1(1),p2(2)-p1(2));
        % Each complete cubic bend has equal curvature-rise and
        % curvature-fall lengths. This prevents a numerically valid but
        % fabrication-unfriendly near-step at either peak.
        ceq = [ceq; (v(1)-v(2))/chord; (v(3)-v(4))/chord];
    end
end

function err = endpoint_error(v, mode, bend_sign, p1, p2)
    if strcmp(mode,'single')
        lengths = v(1:2);
        nodes = [0,bend_sign*v(3),0];
    else
        lengths = v(1:4);
        nodes = [0,bend_sign*v(5),0,-bend_sign*v(6),0];
    end
    % Keep the optimizer integration grid fine enough that the final
    % high-resolution reconstruction does not move the endpoint.
    [x,y,theta] = trace_from_nodes(lengths,nodes,p1,401);
    scale = hypot(p2(1)-p1(1),p2(2)-p1(2));
    err = [(x(end)-p2(1))/scale; (y(end)-p2(2))/scale; ...
        wrap_pi(theta(end)-p2(3))];
end

function [x,y,theta,kappa,s_all,middle_index] = trace_from_nodes(lengths,nodes,p1,n)
    kappa = [];
    s_all = [];
    offset = 0;
    middle_index = 1;
    for i = 1:numel(lengths)
        s = linspace(0,lengths(i),n);
        k = Wcli_wg.kappa_L_cubic(nodes(i),nodes(i+1),0,0,s);
        if i > 1
            s = s(2:end); k = k(2:end);
        end
        kappa = [kappa,k]; %#ok<AGROW>
        s_all = [s_all,offset+s]; %#ok<AGROW>
        offset = offset+lengths(i);
        if i == numel(lengths)/2
            middle_index = numel(kappa);
        end
    end
    theta = p1(3)+cumtrapz(s_all,kappa);
    x = p1(1)+cumtrapz(s_all,cos(theta));
    y = p1(2)+cumtrapz(s_all,sin(theta));
end

function n = count_sign_changes(kappa)
    tol = max(abs(kappa))*1e-5+eps;
    signs = sign(kappa(abs(kappa)>tol));
    n = sum(signs(1:end-1).*signs(2:end)<0);
end

function a = wrap_pi(a)
    a = mod(a+pi,2*pi)-pi;
end

function [wg,result] = wcli_build_cubic_ratio_sbend_impl(pose_1,pose_2,R_min, ...
    radius_ratio,N_per_section,width,etch_angle,height)
%BUILD_CUBIC_RATIO_SBEND Two symmetric cubic single bends with R2/R1 fixed.

arguments
    pose_1 (1,3) double
    pose_2 (1,3) double
    R_min (1,1) double {mustBePositive}
    radius_ratio (1,1) double {mustBePositive}
    N_per_section (1,1) double {mustBeInteger,mustBeGreaterThan(N_per_section,20)}
    width (1,1) double {mustBePositive}
    etch_angle (1,1) double
    height (1,1) double {mustBePositive}
end

chord = hypot(pose_2(1)-pose_1(1),pose_2(2)-pose_1(2));
dtheta = ratio_wrap_pi(pose_2(3)-pose_1(3));
opts = optimoptions('fmincon','Display','off','Algorithm','sqp', ...
    'ConstraintTolerance',1e-10,'OptimalityTolerance',1e-10, ...
    'StepTolerance',1e-12,'MaxIterations',1200,'MaxFunctionEvaluations',2e4);

dx = (pose_2(1)-pose_1(1))*cos(pose_1(3))+(pose_2(2)-pose_1(2))*sin(pose_1(3));
dy = -(pose_2(1)-pose_1(1))*sin(pose_1(3))+(pose_2(2)-pose_1(2))*cos(pose_1(3));
angle_guess = max(0.08,min(1.35,2*abs(atan2(dy,dx))));
requested_R_min = R_min;
effective_R_min = R_min;
radius_constraint_met = true;
best = [];
relaxation_factors = [1,1.1,1.25,1.5,2,2.5,3,4,5,6,8,10,15,20,30,50,100];

for relaxation_factor = relaxation_factors
    trial_R_min = requested_R_min/relaxation_factor;
    trial_best = [];
    radius_starts = unique([trial_R_min,1.5*trial_R_min, ...
        max(trial_R_min,0.5*chord),max(trial_R_min,chord)]);
    angle_starts = unique([0.5*angle_guess,angle_guess,1.5*angle_guess,0.8]);
    for first_sign = [-1,1]
        for R0 = radius_starts
            for a0 = angle_starts
                x0 = [max(trial_R_min,R0),min(pi-0.02,max(0.01,a0))];
                lb = [trial_R_min,1e-4];
                ub = [max(100*requested_R_min,20*chord),pi-1e-3];
                objective = @(v) v(1)/trial_R_min+1e-4*v(2)^2;
                nonlcon = @(v) ratio_constraint(v,first_sign,dtheta, ...
                    radius_ratio,pose_1,pose_2);
                [v,fval,exitflag] = fmincon(objective,x0,[],[],[],[], ...
                    lb,ub,nonlcon,opts);
                err = ratio_endpoint_error(v,first_sign,dtheta, ...
                    radius_ratio,pose_1,pose_2);
                if exitflag > 0 && norm(err) <= 1e-7 && ...
                        (isempty(trial_best) || fval < trial_best.fval)
                    trial_best = struct('v',v,'fval',fval, ...
                        'exitflag',exitflag,'first_sign',first_sign);
                end
            end
        end
    end
    if ~isempty(trial_best)
        best = trial_best;
        effective_R_min = trial_R_min;
        radius_constraint_met = relaxation_factor == 1;
        break;
    end
end

if isempty(best)
    error('Wcli_wg:RatioSBendNoSolution', ...
        ['No ratio S-bend solution after reducing the R1 limit from ', ...
        '%.3f um to %.3f um; R2/R1 = %.6f.'],requested_R_min, ...
        requested_R_min/relaxation_factors(end),radius_ratio);
end

R1 = best.v(1);
R2 = radius_ratio*R1;
if ~radius_constraint_met
    warning('Wcli_wg:RatioSBendRadiusRequirementViolated',[ ...
        '\n*** R_MIN REQUIREMENT VIOLATED ***\n', ...
        'Requested limits: R1 >= %.3f um, R2 >= %.3f um.\n', ...
        'Solver reduced them to R1 >= %.3f um, R2 >= %.3f um.\n', ...
        'Final radii: R1 = %.3f um, R2 = %.3f um.\n', ...
        'This result does NOT satisfy the requested loss constraint.\n'], ...
        requested_R_min,radius_ratio*requested_R_min,effective_R_min, ...
        radius_ratio*effective_R_min,R1,R2);
end
turn_1 = best.first_sign*best.v(2);
turn_2 = dtheta-turn_1;
half_1 = abs(turn_1)*R1;
half_2 = abs(turn_2)*R2;
lengths = [half_1,half_1,half_2,half_2];
peaks = [sign(turn_1)/R1,sign(turn_2)/R2];
[x,y,theta,kappa,s,middle_index] = ratio_trace( ...
    lengths,[0,peaks(1),0,peaks(2),0],pose_1,N_per_section);
wg = Wcli_wg(x,y,theta,width,etch_angle,height);

result.position_error = hypot(x(end)-pose_2(1),y(end)-pose_2(2));
result.angle_error = abs(ratio_wrap_pi(theta(end)-pose_2(3)));
result.R_min_requested = requested_R_min;
result.R1_min_constraint = effective_R_min;
result.R2_min_constraint = radius_ratio*effective_R_min;
result.radius_constraint_met = radius_constraint_met;
result.R1 = R1;
result.R2 = R2;
result.radius_ratio_requested = radius_ratio;
result.radius_ratio_actual = R2/R1;
result.turn_angles = [turn_1,turn_2];
result.half_lengths = [half_1,half_2];
result.section_lengths = lengths;
result.kappa_peaks = peaks;
result.endpoint_kappa_max = max(abs(kappa([1,end])));
result.middle_index = middle_index;
result.middle_kappa_abs = abs(kappa(middle_index));
result.middle_straight_length = 0;
result.kappa = kappa;
result.s = s;
end

function [c,ceq] = ratio_constraint(v,first_sign,dtheta,ratio,p1,p2)
turn_1 = first_sign*v(2);
turn_2 = dtheta-turn_1;
c = first_sign*turn_2+1e-8;
ceq = ratio_endpoint_error(v,first_sign,dtheta,ratio,p1,p2);
end

function err = ratio_endpoint_error(v,first_sign,dtheta,ratio,p1,p2)
R1 = v(1);
R2 = ratio*R1;
turn_1 = first_sign*v(2);
turn_2 = dtheta-turn_1;
lengths = [abs(turn_1)*R1,abs(turn_1)*R1,abs(turn_2)*R2,abs(turn_2)*R2];
nodes = [0,sign(turn_1)/R1,0,sign(turn_2)/R2,0];
[x,y] = ratio_trace(lengths,nodes,p1,401);
scale = hypot(p2(1)-p1(1),p2(2)-p1(2));
err = [(x(end)-p2(1))/scale;(y(end)-p2(2))/scale];
end

function [x,y,theta,kappa,s_all,middle_index] = ratio_trace(lengths,nodes,p1,n)
kappa = [];
s_all = [];
offset = 0;
middle_index = 1;
for i = 1:numel(lengths)
    s = linspace(0,lengths(i),n);
    k = Wcli_wg.kappa_L_cubic(nodes(i),nodes(i+1),0,0,s);
    if i > 1
        s = s(2:end);
        k = k(2:end);
    end
    kappa = [kappa,k]; %#ok<AGROW>
    s_all = [s_all,offset+s]; %#ok<AGROW>
    offset = offset+lengths(i);
    if i == 2
        middle_index = numel(kappa);
    end
end
theta = p1(3)+cumtrapz(s_all,kappa);
x = p1(1)+cumtrapz(s_all,cos(theta));
y = p1(2)+cumtrapz(s_all,sin(theta));
end

function a = ratio_wrap_pi(a)
a = mod(a+pi,2*pi)-pi;
end
