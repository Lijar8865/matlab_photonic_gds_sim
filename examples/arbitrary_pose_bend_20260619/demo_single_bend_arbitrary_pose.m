clc;
clear;
close all;

%% One cubic-curvature bend: 0 -> +/-1/Rpeak -> 0
theta_1 = deg2rad(0);
theta_2 = deg2rad(62);
pose_1 = [10, 15, theta_1];           % [x1, y1, theta1]
% A symmetric single bend requires the chord direction to be exactly
% (theta_1 + theta_2)/2. Choose x2, then calculate the compatible y2.
x_2 = 105;
y_2 = pose_1(2)+(x_2-pose_1(1))*tan((theta_1+theta_2)/2);
pose_2 = [x_2, y_2, theta_2];         % [x2, y2, theta2]
R_min = 50;                           % hard minimum bend radius (um)

wg_width = 1.2;
etch_angle = 70;
wg_height = 0.25;
N_per_section = 401;

script_folder = fileparts(mfilename('fullpath'));
repo_root = fileparts(fileparts(script_folder));
addpath(fullfile(repo_root, 'lib'));
addpath(script_folder);

[single_bend, result] = Wcli_wg.cubic_pose_bend_gen('single', pose_1, pose_2, ...
    R_min, N_per_section, wg_width, etch_angle, wg_height);

assert(result.position_error < 1e-6);
assert(result.angle_error < 1e-7);
assert(result.endpoint_kappa_max < 1e-10);
if result.radius_constraint_met
    assert(result.minimum_radius >= R_min * (1 - 1e-8));
else
    assert(result.minimum_radius >= result.effective_R_limit * (1 - 1e-8));
end
assert(result.curvature_sign_changes == 0);
assert(result.single_length_symmetry_error < 1e-12);
assert(result.pose_symmetry_error < 1e-7);

fprintf('Single cubic bend verification passed.\n');
fprintf('  position error      = %.3e um\n', result.position_error);
fprintf('  angle error         = %.3e rad\n', result.angle_error);
fprintf('  specified R_min     = %.3f um\n', R_min);
fprintf('  actual minimum R    = %.3f um\n', result.minimum_radius);
fprintf('  radius requirement  = %s\n',string(result.radius_constraint_met));
fprintf('  peak curvature      = %.6f 1/um\n', result.peak_curvature);
fprintf('  each half length    = %.6f um\n', result.single_half_length);
fprintf('  half-length mismatch = %.3e um\n', result.single_length_symmetry_error);

fig_shape = figure('Color', 'w', 'Name', 'Single cubic bend shape');
single_bend.plot_2d('face_color', '#1493ce', 'edge_color', '#075985', ...
    'face_alpha', 0.8, 'edge_width', 0.8);
hold on;
plot(single_bend.WTX, single_bend.WTY, 'k--', 'LineWidth', 0.8);
axis equal;
grid on;
xlabel('x (um)'); ylabel('y (um)');
if result.radius_constraint_met
    title(sprintf('Symmetric single cubic bend, R_{min} limit = %.1f um', R_min));
else
    title({'WARNING: R_{min} REQUIREMENT VIOLATED', ...
        sprintf('requested %.1f um; actual %.1f um',R_min,result.minimum_radius)});
end
shape_png = fullfile(script_folder, 'demo_single_bend_arbitrary_pose.png');
exportgraphics(fig_shape, shape_png, 'Resolution', 180);

fig_kappa = figure('Color', 'w', 'Name', 'Single cubic bend curvature');
single_bend.plot_kappa_all(fig_kappa);
hold on;
yline(1/R_min, 'r--', 'LineWidth', 1.2, 'Label', '+1/R_{min}');
yline(-1/R_min, 'r--', 'LineWidth', 1.2, 'Label', '-1/R_{min}');
grid on;
kappa_png = fullfile(script_folder, 'demo_single_bend_kappa.png');
exportgraphics(fig_kappa, kappa_png, 'Resolution', 180);
