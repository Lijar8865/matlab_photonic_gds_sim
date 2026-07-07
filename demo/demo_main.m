clc;
clear;
close all;

%% 1. Environment setup
if usejava('desktop')
    scriptPath = matlab.desktop.editor.getActiveFilename();
else
    scriptPath = '';
end
if isempty(scriptPath)
    scriptPath = mfilename('fullpath');
end

[scriptFolder, ~, ~] = fileparts(scriptPath);
workspaceRoot = fileparts(scriptFolder);
libFolder = fullfile(workspaceRoot, 'lib');
outputFolder = fullfile(workspaceRoot, 'output', 'demo_output');

addpath(libFolder);
if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end
cd(scriptFolder);

fprintf('Workspace root: %s\n', workspaceRoot);
fprintf('Library path added: %s\n', libFolder);
fprintf('Demo output folder: %s\n', outputFolder);

%% 2. Basic waveguide examples
st_wg = Wcli_wg.Straight_wg_gen(60, 0, 1.2, 70, 0.25);
arc_wg = Wcli_wg.Arc_wg_gen(30, pi/2, 0, 401, 1.2, 1.2, 70, 0.25);
taper_wg = Wcli_wg.taper_waveguide_gen(40, 0, 0.8, 2.0, 1, 201, 70, 0.25);

arc_wg.move_to('cleft', [80, 0]);
taper_wg.move_to('cleft', [160, 0]);

fig1 = figure('Name', 'Waveguide Demo', 'Color', 'w');
hold on;
axis equal;
grid off;
st_wg.plot_2d('face_alpha', 0.2);
arc_wg.plot_2d('face_alpha', 0.2);
taper_wg.plot_2d('face_alpha', 0.2);
title('Basic Waveguide Examples');

%% 3. Polygon and electrode examples
slot_s = Wcli_poly.create_slot_S(10, 40, 50, 0.5, 4, 70, 0.25);
slot_g = Wcli_poly.create_slot_G(10, 40, 100, 0.5, 4, 70, 0.25);
t_rail_s = Wcli_poly.create_T_rail_S(8, 60, 40, 3, 6, 2, 24, 70, 0.25);
rect_poly = Wcli_poly.create_rect('len', 30, 'height', 16, 'cen', [0, 0], 'name', 'demo_rect');

slot_s.move_to('cleft', [0, 0]);
slot_g.move_to('cleft', [0, -90]);
t_rail_s.move_to('cleft', [0, 90]);
rect_poly.move_to('cen', [120, -200]);

fig2 = figure('Name', 'Polygon Demo', 'Color', 'w');
hold on;
axis equal;
grid off;
slot_s.plot_2d('face_alpha', 0.25);
slot_g.plot_2d('face_alpha', 0.25);
t_rail_s.plot_2d('face_alpha', 0.25);
rect_poly.plot_2d('face_alpha', 0.25);
title('Polygon and Electrode Examples');

%% 4. Alignment and merge examples
st_1 = Wcli_wg.Straight_wg_gen(25, 0, 1.0, 70, 0.25);
arc_1 = Wcli_wg.Arc_wg_gen(15, pi/2, 0, 301, 1.0, 1.0, 70, 0.25);
st_2 = Wcli_wg.Straight_wg_gen(25, pi/2, 1.0, 70, 0.25);

merged_wg = st_1.copy();
merged_wg.merge_wg({arc_1, st_2});
merged_wg.transform_shape(0, 0, -180);

poly_a = Wcli_poly.create_rect('len', 18, 'height', 8, 'cen', [0, 0], 'name', 'poly_a');
poly_b = Wcli_poly.create_rect('len', 18, 'height', 8, 'cen', [0, 0], 'name', 'poly_b');
poly_b.transform_shape(pi/8, 9, 0);
merged_poly = poly_a.copy();
merged_poly.merge_polys(poly_b, 0, 0, false);
merged_poly.transform_shape(0, 85, -180);

fig3 = figure('Name', 'Align and Merge Demo', 'Color', 'w');
hold on;
axis equal;
grid on;
merged_wg.plot_2d('face_alpha', 0.2);
merged_poly.plot_2d('face_alpha', 0.25);
title('Alignment and Merge Examples');

%% 5. Circuit packaging example
circuit_cells = {slot_s, slot_g, t_rail_s, rect_poly, merged_wg.to_poly()};
circuit_layers = [10, 11, 12, 13, 20];
demo_circuit = Wcli_circuit(circuit_cells, 'laycells', circuit_layers, 'name', 'demo_circuit');

fig4 = figure('Name', 'Circuit Demo', 'Color', 'w');
demo_circuit.plot_circuit(fig4);
title('Circuit Packaging Example');

%% 6. GDS export example
demoGdsPath = fullfile(outputFolder, 'demo_layout.gds');
demo_circuit.generate_gds(demoGdsPath, 'DEMO_TOP', 'DEMO_LIB');
fprintf('Text GDS exported: %s\n', demoGdsPath);

klayoutExe = Wcli_poly.find_klayout_exe('strm2gds');
if exist(klayoutExe, 'file')
    demoGdsiiPath = fullfile(outputFolder, 'ii_demo_layout.gds');
    Wcli_poly.klayout_gds2gdsii(demoGdsPath, demoGdsiiPath, klayoutExe);
    fprintf('Binary GDSII exported: %s\n', demoGdsiiPath);
else
    fprintf('KLayout not found, skipping GDSII conversion.\n');
end

%% 7. Parameter sweep example
default_params = struct( ...
    'Gap', 7, ...
    'W_T', 3.5, ...
    'period', 72, ...
    'FF', 0.42, ...
    'W_S', 64, ...
    'W_G', 136, ...
    'N_ele', 8);

sweep_params = struct();
sweep_params.FF = [0.36, 0.42, 0.58];
sweep_params.period = [48, 72];

param_combinations = Wcli_wg.generate_param_combinations(default_params, sweep_params);
fprintf('Generated %d parameter combinations.\n', numel(param_combinations));
for idx = 1:min(3, numel(param_combinations))
    save_name = Wcli_wg.generate_save_name(param_combinations(idx), 'demo');
    fprintf('  Example %d: %s\n', idx, save_name);
end

%% 8. Optional HFSS interface template
% hfssFolder = fullfile(workspaceRoot, 'lib', 'hfss');
% json_struct = struct();
% json_struct.save_folder = fullfile(outputFolder, 'hfss_case');
% json_struct.scriptFolder = hfssFolder;
% json_struct.open_py = fullfile(hfssFolder, 'Slot_str.py');
% json_struct.extract_py = 'Export_data.py';
% json_struct.Disp_S = 80;
% json_struct.Disp_G = 160;
% json_struct.T_rail_S = slot_s.postohfss2d;
% json_struct.T_rail_G_R = slot_g.postohfss2d;
% json_struct.T_rail_G_L = slot_g.copy().postohfss2d;
% json_struct.Freq_step = 0.1;
% json_struct.Freq_end = 100;
% Wcli_wg.put_HFSS(json_struct, 'run_flag', 0);

fprintf('Demo finished successfully.\n');
