classdef Wcli_fig < handle

    methods (Static)

        function save_fig(path, fig)

            if nargin < 2 || isempty(fig)
                fig = gcf;
            end

            if nargin < 1 || isempty(path)
                error('必须指定保存路径');
            end

            savefig(fig, path);
        end

        function set_fig(fig)

            if nargin < 1 || isempty(fig)
                fig = gcf;
            end

            set(findall(fig, '-property', 'FontName'), 'FontName', 'Arial');
            set(findall(fig, '-property', 'FontSize'), 'FontSize', 16);
            %             set(findall(fig, '-property', 'FontSize'), 'FontSize',13.4);%AI的6pt
            set(findall(fig, '-property', 'Linewidth'), 'Linewidth', 2);
        end

    end

end
