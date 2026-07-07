clc;
clear;
close all;

%% Asymmetric S-bend made from two symmetric cubic single bends
pose_1 = [10,15,deg2rad(0)];
pose_2 = [125,66,deg2rad(0)];
R_min = 20;                           % lower bound for first bend (um)
radius_ratio = 2;                     % R2/R1: 1=symmetric; 2 means R2=2*R1

wg_width = 1.2;
etch_angle = 70;
wg_height = 0.25;
N_per_section = 401;

script_folder = fileparts(mfilename('fullpath'));
repo_root = fileparts(fileparts(script_folder));
addpath(fullfile(repo_root,'lib'));
addpath(script_folder);

[ratio_sbend,result] = Wcli_wg.cubic_ratio_sbend_gen(pose_1,pose_2,R_min, ...
    radius_ratio,N_per_section,wg_width,etch_angle,wg_height);

assert(result.position_error < 1e-6);
assert(result.angle_error < 1e-7);
if result.radius_constraint_met
    assert(result.R1 >= R_min*(1-1e-8));
    assert(result.R2 >= radius_ratio*R_min*(1-1e-8));
else
    assert(result.R1 >= result.R1_min_constraint*(1-1e-8));
    assert(result.R2 >= result.R2_min_constraint*(1-1e-8));
end
assert(abs(result.R2/result.R1-radius_ratio) < 1e-12);
assert(result.endpoint_kappa_max < 1e-10);
assert(result.middle_kappa_abs < 1e-10);
assert(result.middle_straight_length == 0);

fprintf('Cubic ratio S-bend verification passed.\n');
fprintf('  position error       = %.3e um\n',result.position_error);
fprintf('  angle error          = %.3e rad\n',result.angle_error);
fprintf('  requested R_min      = %.3f um\n',R_min);
fprintf('  effective R1/R2 limits = [%.3f, %.3f] um\n', ...
    result.R1_min_constraint,result.R2_min_constraint);
fprintf('  radius requirement   = %s\n',string(result.radius_constraint_met));
fprintf('  solved R1            = %.6f um\n',result.R1);
fprintf('  solved R2            = %.6f um\n',result.R2);
fprintf('  R2/R1                = %.9f\n',result.radius_ratio_actual);
fprintf('  turn angles          = [%.6f, %.6f] deg\n',rad2deg(result.turn_angles));
fprintf('  middle curvature     = %.3e 1/um\n',result.middle_kappa_abs);

fig_shape = figure('Color','w','Name','Cubic ratio S-bend');
ratio_sbend.plot_2d('face_color','#f59e0b','edge_color','#92400e', ...
    'face_alpha',0.8,'edge_width',0.8);
hold on;
plot(ratio_sbend.WTX,ratio_sbend.WTY,'k--','LineWidth',0.8);
plot(ratio_sbend.WTX(result.middle_index), ...
    ratio_sbend.WTY(result.middle_index),'ko','MarkerFaceColor','w');
axis equal;
grid on;
xlabel('x (um)'); ylabel('y (um)');
if result.radius_constraint_met
    title(sprintf('Cubic ratio S-bend: R_2/R_1 = %.3g',radius_ratio));
else
    title({'WARNING: R_{min} REQUIREMENT VIOLATED', ...
        sprintf('Cubic ratio S-bend: R_2/R_1 = %.3g',radius_ratio)});
end
exportgraphics(fig_shape,fullfile(script_folder, ...
    'demo_cubic_ratio_sbend.png'),'Resolution',180);

fig_kappa = figure('Color','w','Name','Cubic ratio S-bend curvature');
ratio_sbend.plot_kappa_all(fig_kappa);
hold on;
yline(result.kappa_peaks(1),'r--','LineWidth',1.1,'Label','\kappa_1');
yline(result.kappa_peaks(2),'m--','LineWidth',1.1,'Label','\kappa_2');
grid on;
exportgraphics(fig_kappa,fullfile(script_folder, ...
    'demo_cubic_ratio_sbend_kappa.png'),'Resolution',180);
