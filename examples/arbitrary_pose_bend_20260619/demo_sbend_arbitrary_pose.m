clc;
clear;
close all;

%% Two cubic-curvature bends: 0 -> +1/R1 -> 0 -> -1/R2 -> 0
pose_1 = [10, 15, deg2rad(0)];        % [x1, y1, theta1]
pose_2 = [125, 66, deg2rad(0)];       % [x2, y2, theta2]
R_min = 20;                           % hard minimum bend radius (um)

wg_width = 1.2;
etch_angle = 70;
wg_height = 0.25;
N_per_section = 401;

script_folder = fileparts(mfilename('fullpath'));
repo_root = fileparts(fileparts(script_folder));
addpath(fullfile(repo_root, 'lib'));
addpath(script_folder);

[sbend, result] = Wcli_wg.cubic_pose_bend_gen('sbend', pose_1, pose_2, ...
    R_min, N_per_section, wg_width, etch_angle, wg_height);

assert(result.position_error < 1e-6);
assert(result.angle_error < 1e-7);
assert(result.endpoint_kappa_max < 1e-10);
assert(result.middle_kappa_abs < 1e-10);
assert(result.middle_straight_length == 0);
if result.radius_constraint_met
    assert(result.minimum_radius >= R_min * (1 - 1e-8));
else
    assert(result.minimum_radius >= result.effective_R_limit * (1 - 1e-8));
    warning('DemoSBend:RadiusRequirementViolated', [ ...
        'This demo result violates requested R_min = %.3f um; ', ...
        'actual minimum radius is %.3f um.'], R_min, result.minimum_radius);
end
assert(result.curvature_sign_changes == 1);

fprintf('Cubic S-bend verification passed.\n');
fprintf('  position error       = %.3e um\n', result.position_error);
fprintf('  angle error          = %.3e rad\n', result.angle_error);
fprintf('  specified R_min      = %.3f um\n', R_min);
fprintf('  actual minimum R     = %.3f um\n', result.minimum_radius);
fprintf('  radius requirement   = %s\n', ...
    string(result.radius_constraint_met));
fprintf('  middle curvature     = %.3e 1/um\n', result.middle_kappa_abs);
fprintf('  middle straight      = %.3f um\n', result.middle_straight_length);
fprintf('  peak curvatures      = [%.6f, %.6f] 1/um\n', result.kappa_peaks);

fig_shape = figure('Color', 'w', 'Name', 'Cubic S-bend shape');
sbend.plot_2d('face_color', '#a855f7', 'edge_color', '#6b21a8', ...
    'face_alpha', 0.8, 'edge_width', 0.8);
hold on;
plot(sbend.WTX, sbend.WTY, 'k--', 'LineWidth', 0.8);
plot(sbend.WTX(result.middle_index), sbend.WTY(result.middle_index), ...
    'ko', 'MarkerFaceColor', 'w', 'DisplayName', 'kappa = 0 join');
axis equal;
grid on;
xlabel('x (um)'); ylabel('y (um)');
if result.radius_constraint_met
    title({'Cubic S-bend', sprintf('R_{min} limit = %.1f um; zero-length middle join', R_min)});
else
    title({'WARNING: R_{min} REQUIREMENT VIOLATED', ...
        sprintf('requested %.1f um; actual %.1f um; zero-length middle join', ...
        R_min, result.minimum_radius)});
end
shape_png = fullfile(script_folder, 'demo_sbend_arbitrary_pose.png');
exportgraphics(fig_shape, shape_png, 'Resolution', 180);

fig_kappa = figure('Color', 'w', 'Name', 'Cubic S-bend curvature');
sbend.plot_kappa_all(fig_kappa);
hold on;
yline(1/R_min, 'r--', 'LineWidth', 1.2, 'Label', '+1/R_{min}');
yline(-1/R_min, 'r--', 'LineWidth', 1.2, 'Label', '-1/R_{min}');
grid on;
kappa_png = fullfile(script_folder, 'demo_sbend_kappa.png');
exportgraphics(fig_kappa, kappa_png, 'Resolution', 180);
